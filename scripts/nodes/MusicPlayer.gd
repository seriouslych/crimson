extends Node

# Массив путей к трекам (теперь загружается автоматически)
var background_tracks: Array[String] = []
# Массив метаданных треков
var tracks_metadata: Array[MusicMetadata] = []

var target_volume: float = -35.0
var fade_in_duration: float = 5.0
var fade_pause_duration: float = 1.0
var music_enabled: bool = true

var default_cover = load("res://cover.png")

var shuffled_playlist: Array[int] = []  # Теперь храним индексы
var current_track_index: int = 0
var audio_player: AudioStreamPlayer
var tween: Tween

# Индексы эффектов на шине
var lowpass_effect_index: int = -1
var reverb_effect_index: int = -1
var music_bus_index: int = -1

# Состояния эффектов
var is_muffled: bool = false
var is_reverb_enabled: bool = false

const NotificationLogicClass = preload("res://scripts/NotificationLogic.gd")
var notification = NotificationLogicClass.new()

# Пул AudioStreamPlayer для SFX
var sfx_players: Array[AudioStreamPlayer] = []
var max_sfx_players: int = 32  # Максимальное количество одновременных звуков

func _ready():
	print("Инициализация музыки")
	add_child(notification)
	
	# Создаём отдельную шину для музыки если её нет
	if AudioServer.get_bus_index("Music") == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, "Music")
		AudioServer.set_bus_send(AudioServer.get_bus_index("Music"), "Master")
	
	if not audio_player:
		audio_player = AudioStreamPlayer.new()
		audio_player.bus = "Music"  # Музыка идёт через шину Music
		add_child(audio_player)
		audio_player.finished.connect(_on_audio_stream_player_finished)
	
	# Загружаем треки из папки
	load_music()
	
	# Загружаем настройки
	load_settings_from_config()
	
	await get_tree().process_frame
	
	# Запускаем музыку только если она включена
	if music_enabled:
		start_music()
	
	setup_audio_effects()
	setup_sfx_pool()

# Безопасное создание метаданных с обработкой ошибок
func create_metadata_safe(audio_stream: AudioStream, file_path: String) -> MusicMetadata:
	var metadata = MusicMetadata.new()
	
	# Пытаемся загрузить метаданные из стрима
	var error = metadata.update_from_stream(audio_stream)
	if error != OK:
		pass  # Тихо игнорируем ошибки
	
	# Если название пустое, используем имя файла
	if metadata.title.is_empty():
		metadata.title = file_path.get_file().get_basename().replace("_", " ").capitalize()
	
	# Сохраняем путь к файлу
	metadata.set_tag("file_path", file_path)
	
	return metadata

func get_music_folder_path() -> String:
	"""Возвращает путь к папке music с улучшенной отладкой"""
	var exe_path = OS.get_executable_path()
	var exe_dir = exe_path.get_base_dir()
	
	var music_path: String
	if OS.get_name() == "Windows":
		music_path = exe_dir + "/music"
	else:
		music_path = exe_dir + "/music"
	
	# Проверяем также в текущей рабочей директории
	var current_dir = OS.get_environment("PWD")
	if current_dir == "":
		current_dir = exe_dir
	
	var alt_path = current_dir + "/music"
	
	# Если основной путь не существует, пробуем альтернативный
	if not DirAccess.dir_exists_absolute(music_path) and DirAccess.dir_exists_absolute(alt_path):
		return alt_path
	
	return music_path

func load_audio_stream(file_path: String) -> AudioStream:
	"""Загружает аудиофайл из внешнего пути"""
	var extension := file_path.get_extension().to_lower()
	var file := FileAccess.open(file_path, FileAccess.READ)
	
	if file == null:
		return null
	
	var audio_stream: AudioStream
	
	if extension == "mp3":
		audio_stream = AudioStreamMP3.new()
		audio_stream.data = file.get_buffer(file.get_length())
	elif extension == "ogg":
		audio_stream = AudioStreamOggVorbis.load_from_file(file_path)
	elif extension == "wav":
		audio_stream = AudioStreamWAV.new()
		# WAV требует более сложной обработки, но базово:
		audio_stream.data = file.get_buffer(file.get_length())
	
	file.close()
	return audio_stream

func load_music():
	var music_folder := get_music_folder_path()
	var dir := DirAccess.open(music_folder)
	
	if dir == null:
		push_error("Не удалось открыть папку: " + music_folder)
		return
	
	background_tracks.clear()
	tracks_metadata.clear()
	
	dir.list_dir_begin()
	var file_name := dir.get_next()
	
	while file_name != "":
		if not dir.current_is_dir():
			# Проверяем, что это аудиофайл
			var extension := file_name.get_extension().to_lower()
			if extension in ["mp3", "ogg", "wav"]:
				var path := music_folder + "/" + file_name
				var audio_stream := load_audio_stream(path)
				
				if audio_stream:
					background_tracks.append(path)
					var metadata := create_metadata_safe(audio_stream, path)
					tracks_metadata.append(metadata)
				else:
					push_warning("Не удалось загрузить трек: " + path)
		
		file_name = dir.get_next()
	
	dir.list_dir_end()
	
	if background_tracks.is_empty():
		push_warning("Не найдено аудиофайлов в папке: " + music_folder)

# Загрузка настроек из SettingsManager
func load_settings_from_config():
	music_enabled = SettingsManager.get_setting("music_enabled", true)
	target_volume = SettingsManager.get_setting("music_volume", -35.0)
	fade_in_duration = SettingsManager.get_setting("fade_in_duration", 5.0)
	fade_pause_duration = SettingsManager.get_setting("fade_pause_duration", 1.0)

func start_music():
	if background_tracks.size() == 0:
		print("Нет треков для воспроизведения!")
		return
	
	# Создаём перемешанный плейлист из индексов
	shuffled_playlist.clear()
	for i in range(background_tracks.size()):
		shuffled_playlist.append(i)
	shuffled_playlist.shuffle()
	
	current_track_index = 0
	play_current_track()
	print("Музыка пошла, треков: ", shuffled_playlist.size())

func play_current_track():
	if shuffled_playlist.size() == 0 or current_track_index >= shuffled_playlist.size():
		print("Плейлист кончился, начинаем заново")
		shuffled_playlist.clear()
		for i in range(background_tracks.size()):
			shuffled_playlist.append(i)
		shuffled_playlist.shuffle()
		current_track_index = 0
	
	var track_idx = shuffled_playlist[current_track_index]
	var track_path = background_tracks[track_idx]
	
	if not ResourceLoader.exists(track_path):
		print("Файл не найден: ", track_path)
		next_track()
		return
	
	var audio_stream = load(track_path)
	if audio_stream == null:
		print("Не удалось загрузить трек: ", track_path)
		next_track()
		return
	
	audio_player.volume_db = -50.0
	audio_player.stream = audio_stream
	audio_player.play()
	
	start_fade_in()
	
	# Получаем метаданные текущего трека
	var metadata = tracks_metadata[track_idx]
	
	# Формируем текст уведомления
	var track_title = metadata.title if not metadata.title.is_empty() else track_path.get_file().get_basename()
	var track_artist = metadata.artist if not metadata.artist.is_empty() else ""
	
	print("♪ Играет: ", track_title, " - ", track_artist if not track_artist.is_empty() else "(Неизвестный исполнитель)")
	
	# Формируем текст для уведомления
	var notification_text = tr("NTF_NOWPLAYING")
	if not track_artist.is_empty():
		notification_text += track_artist + " - " + track_title
	else:
		notification_text += track_title
	
	# Получаем обложку (из метаданных или дефолтную)
	var cover_image = metadata.get_most_relevent_cover()
	if cover_image == null:
		cover_image = default_cover
	
	await get_tree().create_timer(0.5).timeout
	notification.show_notification(notification_text, cover_image)

func start_fade_in():
	if tween:
		tween.kill()
	
	tween = create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_method(set_audio_volume, -50.0, target_volume, fade_in_duration)
	tween.tween_callback(on_fade_in_complete)

func set_audio_volume(volume: float):
	if audio_player:
		audio_player.volume_db = volume
	else:
		print("audio_player не инициализирован")

func on_fade_in_complete():
	pass

func next_track():
	current_track_index += 1
	if current_track_index >= shuffled_playlist.size():
		shuffled_playlist.shuffle()
		current_track_index = 0
		print("плейлист кончился, мешаем заново")
	play_current_track()

func _on_audio_stream_player_finished():
	print("трек закончился, переключаем")
	next_track()

func stop_music():
	if audio_player:
		if tween:
			tween.kill()
		audio_player.stop()
		print("музыка стоп")

func pause_music():
	if audio_player and not audio_player.stream_paused:
		if tween:
			tween.kill()
		tween = create_tween()
		tween.set_ease(Tween.EASE_IN)
		tween.set_trans(Tween.TRANS_CUBIC)
		tween.tween_method(set_audio_volume, audio_player.volume_db, -50.0, fade_pause_duration)
		tween.tween_callback(func(): 
			audio_player.stream_paused = true
		)

func resume_music():
	if audio_player and audio_player.stream_paused:
		audio_player.stream_paused = false
		if tween:
			tween.kill()
		tween = create_tween()
		tween.set_ease(Tween.EASE_IN)
		tween.set_trans(Tween.TRANS_CUBIC)
		tween.tween_method(set_audio_volume, audio_player.volume_db, target_volume, fade_pause_duration)
		
func set_volume(volume_db: float):
	target_volume = volume_db
	SettingsManager.set_setting("music_volume", volume_db)
	if audio_player and (not tween or not tween.is_valid()):
		audio_player.volume_db = volume_db
		print("ГРОМКОСТЬ УСТАНОВЛЕНА: ", volume_db)

func set_fade_in_duration(duration: float):
	fade_in_duration = duration
	SettingsManager.set_setting("fade_in_duration", duration)
	print("длительность фейда: ", duration)

func skip_track():
	if tween:
		tween.kill()
	print("скипаем трек")
	next_track()

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_WINDOW_FOCUS_OUT when music_enabled:
			pause_music()
		NOTIFICATION_WM_WINDOW_FOCUS_IN when music_enabled:
			resume_music()

func _input(event):
	if event.is_action_pressed("skip_key"):
		skip_track()
	if event.is_action_pressed("now_playing"):
		show_now_playing_notification()

# Дополнительные методы для получения информации о текущем треке
func get_current_track_metadata() -> MusicMetadata:
	if shuffled_playlist.size() == 0 or current_track_index >= shuffled_playlist.size():
		return null
	var track_idx = shuffled_playlist[current_track_index]
	return tracks_metadata[track_idx]

func get_current_track_title() -> String:
	var metadata = get_current_track_metadata()
	if metadata:
		return metadata.title
	return ""

func get_current_track_artist() -> String:
	var metadata = get_current_track_metadata()
	if metadata:
		return metadata.artist
	return ""

func get_current_track_cover() -> ImageTexture:
	var metadata = get_current_track_metadata()
	if metadata:
		return metadata.get_most_relevent_cover()
	return default_cover

# Показать уведомление о текущем треке
func show_now_playing_notification():
	if shuffled_playlist.size() == 0 or current_track_index >= shuffled_playlist.size():
		print("Нет текущего трека для отображения")
		return
	
	var track_idx = shuffled_playlist[current_track_index]
	var metadata = tracks_metadata[track_idx]
	
	# Формируем текст уведомления
	var track_title = metadata.title if not metadata.title.is_empty() else background_tracks[track_idx].get_file().get_basename()
	var track_artist = metadata.artist if not metadata.artist.is_empty() else ""
	
	# Формируем текст для уведомления
	var notification_text = tr("NTF_NOWPLAYING")
	if not track_artist.is_empty():
		notification_text += track_artist + " - " + track_title
	else:
		notification_text += track_title
	
	# Получаем обложку (из метаданных или дефолтную)
	var cover_image = metadata.get_most_relevent_cover()
	if cover_image == null:
		cover_image = default_cover
	
	notification.show_notification(notification_text, cover_image)

# ============ АУДИО ЭФФЕКТЫ ============

func setup_audio_effects():
	# Получаем индекс МУЗЫКАЛЬНОЙ шины (эффекты только для музыки!)
	music_bus_index = AudioServer.get_bus_index("Music")
	
	# Создаём Low Pass фильтр для эффекта "соседней комнаты"
	var lowpass = AudioEffectLowPassFilter.new()
	lowpass.cutoff_hz = 500.0  # Частота среза (убираем всё выше 500Hz)
	lowpass.resonance = 1.0
	lowpass_effect_index = AudioServer.get_bus_effect_count(music_bus_index)
	AudioServer.add_bus_effect(music_bus_index, lowpass, lowpass_effect_index)
	AudioServer.set_bus_effect_enabled(music_bus_index, lowpass_effect_index, false)
	
	# Создаём Reverb для эффекта "помещения"
	var reverb = AudioEffectReverb.new()
	reverb.room_size = 0.8  # Размер комнаты (0-1)
	reverb.damping = 0.5    # Поглощение звука
	reverb.spread = 1.0     # Стерео-широта
	reverb.wet = 0.5        # Микс эффекта (0-1)
	reverb.dry = 0.7        # Оригинальный звук (0-1)
	reverb_effect_index = AudioServer.get_bus_effect_count(music_bus_index)
	AudioServer.add_bus_effect(music_bus_index, reverb, reverb_effect_index)
	AudioServer.set_bus_effect_enabled(music_bus_index, reverb_effect_index, false)

# ЭФФЕКТ: Заглушенность (музыка в соседней комнате)
func enable_muffled_effect(enable: bool = true, cutoff_frequency: float = 500.0):
	if music_bus_index < 0 or lowpass_effect_index < 0:
		return
	
	is_muffled = enable
	AudioServer.set_bus_effect_enabled(music_bus_index, lowpass_effect_index, enable)
	
	# Настраиваем частоту среза
	var effect = AudioServer.get_bus_effect(music_bus_index, lowpass_effect_index)
	if effect is AudioEffectLowPassFilter:
		effect.cutoff_hz = cutoff_frequency

# ЭФФЕКТ: Реверберация (музыка в помещении)
func enable_reverb_effect(enable: bool = true, room_size: float = 0.8, wet: float = 0.5):
	if music_bus_index < 0 or reverb_effect_index < 0:
		return
	
	is_reverb_enabled = enable
	AudioServer.set_bus_effect_enabled(music_bus_index, reverb_effect_index, enable)
	
	# Настраиваем параметры реверберации
	var effect = AudioServer.get_bus_effect(music_bus_index, reverb_effect_index)
	if effect is AudioEffectReverb:
		effect.room_size = room_size  # 0.0 = маленькая комната, 1.0 = огромный зал
		effect.wet = wet              # Насколько сильный эффект

# ЭФФЕКТ: Плавный переход к заглушенности (с анимацией)
func transition_to_muffled(duration: float = 2.0, target_cutoff: float = 500.0):
	if music_bus_index < 0 or lowpass_effect_index < 0:
		return
	
	var effect = AudioServer.get_bus_effect(music_bus_index, lowpass_effect_index)
	if not effect is AudioEffectLowPassFilter:
		return
	
	# Включаем эффект если выключен
	if not is_muffled:
		AudioServer.set_bus_effect_enabled(music_bus_index, lowpass_effect_index, true)
		is_muffled = true
	
	# Анимируем частоту среза
	var start_cutoff = effect.cutoff_hz
	var transition_tween = create_tween()
	transition_tween.tween_method(
		func(value: float):
			effect.cutoff_hz = value,
		start_cutoff,
		target_cutoff,
		duration
	).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)


# ЭФФЕКТ: Плавный переход из заглушенности
func transition_from_muffled(duration: float = 2.0):
	if music_bus_index < 0 or lowpass_effect_index < 0:
		return
	
	var effect = AudioServer.get_bus_effect(music_bus_index, lowpass_effect_index)
	if not effect is AudioEffectLowPassFilter:
		return
	
	# Анимируем частоту среза обратно к нормальной
	var start_cutoff = effect.cutoff_hz
	var transition_tween = create_tween()
	transition_tween.tween_method(
		func(value: float):
			effect.cutoff_hz = value,
		start_cutoff,
		20000.0,  # Максимальная частота (нормальный звук)
		duration
	).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	
	transition_tween.tween_callback(func():
		AudioServer.set_bus_effect_enabled(music_bus_index, lowpass_effect_index, false)
		is_muffled = false
	)
	

# ПРЕСЕТЫ для разных ситуаций
func apply_preset_neighbor_room():
	"""Музыка играет в соседней комнате"""
	enable_muffled_effect(true, 400.0)
	enable_reverb_effect(true, 0.6, 0.3)
	print("🏠 Пресет: Соседняя комната")

func apply_preset_underwater():
	"""Музыка под водой"""
	enable_muffled_effect(true, 300.0)
	enable_reverb_effect(true, 0.9, 0.7)
	print("🌊 Пресет: Под водой")

func apply_preset_concert_hall():
	"""Концертный зал"""
	enable_muffled_effect(false)
	enable_reverb_effect(true, 0.95, 0.6)
	print("🎭 Пресет: Концертный зал")

func apply_preset_small_room():
	"""Маленькая комната"""
	enable_muffled_effect(false)
	enable_reverb_effect(true, 0.3, 0.3)
	print("🚪 Пресет: Маленькая комната")

func apply_preset_cave():
	"""Пещера"""
	enable_muffled_effect(false)
	enable_reverb_effect(true, 1.0, 0.8)
	print("🗿 Пресет: Пещера")

func apply_preset_normal():
	"""Нормальный звук (без эффектов)"""
	enable_muffled_effect(false)
	enable_reverb_effect(false)
	print("🎵 Пресет: Нормальный звук")

# ============ SFX СИСТЕМА ============

# Инициализация пула AudioStreamPlayer для звуковых эффектов
func setup_sfx_pool():
	for i in range(max_sfx_players):
		var player = AudioStreamPlayer.new()
		player.bus = "Master"  # Можно создать отдельную шину "SFX"
		add_child(player)
		player.finished.connect(_on_sfx_finished.bind(player))
		sfx_players.append(player)
	print("SFX пул инициализирован: ", max_sfx_players, " плееров")

# Получить свободный плеер из пула
func get_free_sfx_player() -> AudioStreamPlayer:
	for player in sfx_players:
		if not player.playing:
			return player
	# Если все заняты, возвращаем первый (он перезапишется)
	return sfx_players[0]

# Воспроизвести звуковой эффект
func play_sfx(sfx_path: String, volume_db: float = 0.0, pitch_scale: float = 1.0) -> AudioStreamPlayer:
	if not ResourceLoader.exists(sfx_path):
		push_error("SFX файл не найден: " + sfx_path)
		return null
	
	var sound = load(sfx_path) as AudioStream
	if sound == null:
		push_error("Не удалось загрузить SFX: " + sfx_path)
		return null
	
	var player = get_free_sfx_player()
	player.stream = sound
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	player.play()
	
	return player

# Обработчик завершения SFX (освобождение плеера)
func _on_sfx_finished(player: AudioStreamPlayer):
	player.stream = null

# Остановить все SFX
func stop_all_sfx():
	for player in sfx_players:
		if player.playing:
			player.stop()

# Очистка эффектов при выходе
func _exit_tree():
	if music_bus_index >= 0:
		if lowpass_effect_index >= 0:
			AudioServer.remove_bus_effect(music_bus_index, lowpass_effect_index)
		if reverb_effect_index >= 0:
			AudioServer.remove_bus_effect(music_bus_index, reverb_effect_index)


# ============ ПРИМЕРЫ ИСПОЛЬЗОВАНИЯ ============

# === МУЗЫКА ===
# 1. Управление воспроизведением
# MusicPlayer.start_music()
# MusicPlayer.pause_music()
# MusicPlayer.resume_music()
# MusicPlayer.stop_music()
# MusicPlayer.skip_track()

# 2. Показать что сейчас играет
# MusicPlayer.show_now_playing_notification()

# 3. Эффекты заглушенности
# MusicPlayer.enable_muffled_effect(true, 500.0)
# MusicPlayer.enable_muffled_effect(false)
# MusicPlayer.transition_to_muffled(2.0, 400.0)
# MusicPlayer.transition_from_muffled(2.0)

# 3. Пресеты эффектов
# MusicPlayer.apply_preset_neighbor_room()
# MusicPlayer.apply_preset_underwater()
# MusicPlayer.apply_preset_concert_hall()
# MusicPlayer.apply_preset_normal()

# === SFX ===
# 1. Базовое воспроизведение
# MusicPlayer.play_sfx("res://assets/sfx/click.ogg")

# 2. С параметрами
# MusicPlayer.play_sfx("res://assets/sfx/explosion.ogg", -5.0, 1.2)

# 3. Случайная вариация
# var pitch = randf_range(0.9, 1.1)
# MusicPlayer.play_sfx("res://assets/sfx/step.ogg", -10.0, pitch)

# 4. Остановка всех SFX
# MusicPlayer.stop_all_sfx()
