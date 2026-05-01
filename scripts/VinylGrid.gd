class_name VinylGrid
extends Control

@onready var viewport_container = $ViewportContainer
@onready var viewport_3d = $ViewportContainer/SubViewport
@onready var camera_3d = $ViewportContainer/SubViewport/Camera3D
@onready var grid_container = $ViewportContainer/SubViewport/GridContainer

# UI элементы
@onready var album_title_label = $AlbumTitleLabel
@onready var artist_label = $ArtistLabel
@onready var loading_icon = $Loading

# Данные альбомов
var albums: Array[VinylCover3D.AlbumData] = []
var vinyl_covers: Array[VinylCover3D] = []

# Параметры сетки
@export var grid_columns: int = 5
@export var grid_rows: int = 5
@export var spacing_x: float = 2.5  # Увеличен spacing
@export var spacing_y: float = 2.5  # Увеличен spacing
@export var spacing_z: float = 0.5

# Прокрутка
var scroll_offset: int = 0
var max_scroll: int = 0
var visible_items: int = 0

# Выбор
var selected_index: int = -1
var hovered_index: int = -1

# Управление
var current_input_method = "keyboard"
var last_device_id: int = -1

# Навигация по сетке
var cursor_x: int = 0
var cursor_y: int = 0

func _ready():
	loading_icon.visible = true
	
	visible_items = grid_columns * grid_rows
	
	# Создаём контейнер для сетки если его нет
	if not grid_container:
		grid_container = Node3D.new()
		grid_container.name = "GridContainer"
		viewport_3d.add_child(grid_container)
	
	# Загружаем альбомы
	load_albums()
	
	await get_tree().process_frame
	setup_grid()
	await get_tree().process_frame
	update_display()
	
	loading_icon.visible = false

func load_albums():
	# TODO: Загрузка альбомов из файлов/базы данных
	# Пока создадим тестовые данные
	for i in range(20):
		var album = VinylCover3D.AlbumData.new()
		album.id = "album_" + str(i)
		album.title = "Album " + str(i + 1)
		album.artist = "Artist " + str((i % 10) + 1)
		album.cover = ""  # Путь к обложке
		albums.append(album)
	
	# Вычисляем максимальную прокрутку
	var total_rows = ceili(float(albums.size()) / float(grid_columns))
	max_scroll = max(0, total_rows - grid_rows)
	
	print("Загружено альбомов: ", albums.size())
	print("Максимальная прокрутка: ", max_scroll)

func setup_grid():
	# Очищаем существующие обложки
	for cover in vinyl_covers:
		if is_instance_valid(cover):
			cover.queue_free()
	vinyl_covers.clear()
	
	await get_tree().process_frame
	
	if albums.is_empty():
		return
	
	# Создаём видимые элементы сетки
	for i in range(visible_items):
		# Создаём контейнер для элемента (обложка + фон)
		var item_container = Node3D.new()
		grid_container.add_child(item_container)
		
		# Создаём фоновый квадрат
		var background = create_grid_background()
		item_container.add_child(background)
		
		# Создаём обложку винила
		var cover_instance = VinylCover3D.new()
		item_container.add_child(cover_instance)
		vinyl_covers.append(cover_instance)
		cover_instance.set_grid_index(i)
		
		# Сохраняем ссылку на фон в метаданных
		cover_instance.set_meta("background", background)
		cover_instance.set_meta("container", item_container)

func create_grid_background() -> MeshInstance3D:
	"""Создаёт полупрозрачный квадрат-фон для элемента сетки"""
	var mesh_instance = MeshInstance3D.new()
	var quad_mesh = QuadMesh.new()
	quad_mesh.size = Vector2(2.0, 2.0)  # Увеличен размер квадрата
	mesh_instance.mesh = quad_mesh
	
	# Создаём полупрозрачный материал с границей
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.15, 0.15, 0.15, 0.5)  # Темнее и заметнее
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	
	# Добавляем легкое свечение для лучшей видимости
	material.emission_enabled = true
	material.emission = Color(0.3, 0.3, 0.3, 1.0)
	material.emission_energy = 0.2
	
	mesh_instance.material_override = material
	
	# Позиционируем чуть позади обложки
	mesh_instance.position = Vector3(0, 0, -0.15)
	
	return mesh_instance

func update_display():
	if albums.is_empty():
		album_title_label.text = tr("VG_NOALBUMS_TIP")
		return
	
	# Обновляем позиции всех видимых элементов
	for i in range(vinyl_covers.size()):
		var cover = vinyl_covers[i]
		if not is_instance_valid(cover):
			continue
		
		var container = cover.get_meta("container") as Node3D
		var background = cover.get_meta("background") as MeshInstance3D
		
		# Вычисляем индекс в массиве альбомов с учётом прокрутки
		var album_index = get_album_index_from_grid(i)
		
		if album_index >= 0 and album_index < albums.size():
			# Устанавливаем данные альбома
			cover.set_album_data(albums[album_index])
			cover.visible = true
			
			# Вычисляем позицию в сетке
			var grid_x = i % grid_columns
			var grid_y = int(i / grid_columns)
			
			var pos = Vector3(
				(grid_x - grid_columns / 2.0 + 0.5) * spacing_x,
				-(grid_y - grid_rows / 2.0 + 0.5) * spacing_y,
				0
			)
			
			# Устанавливаем позицию контейнера
			if container:
				container.position = pos
			
			# Проверяем, выбран ли этот элемент
			var is_selected = (cursor_x == grid_x and cursor_y == grid_y)
			cover.set_selected(is_selected)
			
			# Обновляем фон в зависимости от выбора
			if background:
				var bg_material = background.material_override as StandardMaterial3D
				if is_selected:
					# Яркое красное выделение для выбранного элемента
					bg_material.albedo_color = Color(0.85, 0.29, 0.29, 0.8)
					bg_material.emission = Color(0.85, 0.29, 0.29, 1.0)
					bg_material.emission_energy = 0.8
					background.scale = Vector3(1.0, 1.0, 1.0)
				else:
					# Темный фон для обычных элементов
					bg_material.albedo_color = Color(0.15, 0.15, 0.15, 0.5)
					bg_material.emission = Color(0.3, 0.3, 0.3, 1.0)
					bg_material.emission_energy = 0.2
					background.scale = Vector3.ONE
			
			if is_selected:
				selected_index = album_index
				update_info_display()
			
			# Сбрасываем локальную позицию и масштаб обложки
			cover.position = Vector3(0.5, -0.8, 0)
			var rot = Vector3(0, 90, 0)
			var scl = Vector3(0.7, 0.7, 0.7)
			
			cover.set_target_transform(cover.position, rot, scl)
		else:
			# Скрываем элементы за пределами списка
			cover.visible = false
			if container:
				container.visible = false

func get_album_index_from_grid(grid_index: int) -> int:
	var grid_x = grid_index % grid_columns
	var grid_y = int(grid_index / grid_columns)
	return (scroll_offset + grid_y) * grid_columns + grid_x

func update_info_display():
	if selected_index >= 0 and selected_index < albums.size():
		var album = albums[selected_index]
		album_title_label.text = album.title
		artist_label.text = album.artist

func move_cursor(dx: int, dy: int):
	cursor_x = clamp(cursor_x + dx, 0, grid_columns - 1)
	cursor_y = clamp(cursor_y + dy, 0, grid_rows - 1)
	
	# Проверяем, нужна ли прокрутка
	if dy > 0 and cursor_y >= grid_rows - 1:
		scroll_down()
	elif dy < 0 and cursor_y <= 0:
		scroll_up()
	
	update_display()

func scroll_up():
	if scroll_offset > 0:
		scroll_offset -= 1
		update_display()

func scroll_down():
	if scroll_offset < max_scroll:
		scroll_offset += 1
		update_display()

func _input(event):
	# Определяем метод ввода
	if event is InputEventKey or event is InputEventMouseButton:
		if current_input_method != "keyboard":
			current_input_method = "keyboard"
	elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
		if current_input_method != "gamepad":
			current_input_method = "gamepad"
		last_device_id = event.device
	
	# Навигация
	if event.is_action_pressed("ui_left"):
		move_cursor(-1, 0)
		MusicPlayer.play_sfx("res://assets/sfx/Fantasy UI SFX/Skyward Hero/SkywardHero_UI (16).wav", -20.0, 2.0)
		_trigger_vibration(0.5, 0.0, 0.1)
	
	elif event.is_action_pressed("ui_right"):
		move_cursor(1, 0)
		MusicPlayer.play_sfx("res://assets/sfx/Fantasy UI SFX/Skyward Hero/SkywardHero_UI (16).wav", -20.0, 2.0)
		_trigger_vibration(0.5, 0.0, 0.1)
	
	elif event.is_action_pressed("ui_up"):
		move_cursor(0, -1)
		MusicPlayer.play_sfx("res://assets/sfx/Fantasy UI SFX/Skyward Hero/SkywardHero_UI (16).wav", -25.0, 1.5)
		_trigger_vibration(0.5, 0.0, 0.1)
	
	elif event.is_action_pressed("ui_down"):
		move_cursor(0, 1)
		MusicPlayer.play_sfx("res://assets/sfx/Fantasy UI SFX/Skyward Hero/SkywardHero_UI (16).wav", -25.0, 1.5)
		_trigger_vibration(0.5, 0.0, 0.1)
	
	# Действия
	elif event.is_action_pressed("ui_accept") or event.is_action_pressed("accept_pad"):
		on_album_selected()
		MusicPlayer.play_sfx("res://assets/sfx/Fantasy UI SFX/Piano/Piano_Ui (7).wav", -15.0, 1.0)
		_trigger_vibration(1.0, 0.5, 0.2)

# ============ ЗАГОТОВКИ ФУНКЦИЙ ============

func on_album_selected():
	"""Вызывается при нажатии на альбом"""
	if selected_index >= 0 and selected_index < albums.size():
		var album = albums[selected_index]
		print("Выбран альбом: ", album.title, " от ", album.artist)
		# TODO: Открыть детальную информацию об альбоме
		# TODO: Начать воспроизведение альбома
		show_album_details(album)

func show_album_details(album: VinylCover3D.AlbumData):
	"""Показывает детальную информацию об альбоме"""
	# TODO: Реализовать панель с информацией об альбоме
	# - Список треков
	# - Кнопки управления (Play, Add to Queue, etc.)
	# - Информация об исполнителе
	print("Показываем детали альбома: ", album.title)
	pass

func play_album(album: VinylCover3D.AlbumData):
	"""Начинает воспроизведение альбома"""
	# TODO: Добавить треки в очередь воспроизведения
	# TODO: Начать воспроизведение первого трека
	print("Воспроизводим альбом: ", album.title)
	pass

func add_album_to_queue(album: VinylCover3D.AlbumData):
	"""Добавляет альбом в очередь воспроизведения"""
	# TODO: Добавить все треки альбома в конец очереди
	print("Добавляем альбом в очередь: ", album.title)
	pass

func add_album_to_favorites(album: VinylCover3D.AlbumData):
	"""Добавляет альбом в избранное"""
	# TODO: Сохранить альбом в список избранного
	print("Добавляем в избранное: ", album.title)
	pass

func shuffle_album(album: VinylCover3D.AlbumData):
	"""Воспроизводит альбом в случайном порядке"""
	# TODO: Перемешать треки и начать воспроизведение
	print("Перемешиваем альбом: ", album.title)
	pass

func show_artist_info(album: VinylCover3D.AlbumData):
	"""Показывает информацию об исполнителе"""
	# TODO: Открыть панель с информацией об исполнителе
	# - Другие альбомы исполнителя
	# - Биография
	print("Показываем информацию об исполнителе: ", album.artist)
	pass

func edit_album(album: VinylCover3D.AlbumData):
	"""Редактирует информацию об альбоме"""
	# TODO: Открыть форму редактирования
	# - Изменить обложку
	# - Изменить название
	# - Изменить исполнителя
	print("Редактируем альбом: ", album.title)
	pass

func delete_album(album: VinylCover3D.AlbumData):
	"""Удаляет альбом из библиотеки"""
	# TODO: Показать диалог подтверждения
	# TODO: Удалить альбом и обновить сетку
	print("Удаляем альбом: ", album.title)
	pass

func filter_albums_by_artist(artist_name: String):
	"""Фильтрует альбомы по исполнителю"""
	# TODO: Показать только альбомы указанного исполнителя
	print("Фильтруем по исполнителю: ", artist_name)
	pass

func filter_albums_by_genre(genre: String):
	"""Фильтрует альбомы по жанру"""
	# TODO: Показать только альбомы указанного жанра
	print("Фильтруем по жанру: ", genre)
	pass

func search_albums(query: String):
	"""Поиск альбомов по названию"""
	# TODO: Фильтровать альбомы по поисковому запросу
	print("Ищем: ", query)
	pass

func sort_albums(sort_by: String):
	"""Сортирует альбомы"""
	# sort_by может быть: "title", "artist", "year", "date_added"
	# TODO: Пересортировать массив albums и обновить дисплей
	print("Сортируем по: ", sort_by)
	pass

func refresh_grid():
	"""Обновляет сетку после изменений в данных"""
	load_albums()
	await get_tree().process_frame
	setup_grid()
	await get_tree().process_frame
	update_display()

# ============ ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ============

func _trigger_vibration(weak: float, strong: float, duration: float):
	if last_device_id >= 0 and current_input_method == "gamepad":
		Input.start_joy_vibration(last_device_id, weak, strong, duration)

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			set_process_input(false)
		NOTIFICATION_WM_WINDOW_FOCUS_IN:
			set_process_input(true)
