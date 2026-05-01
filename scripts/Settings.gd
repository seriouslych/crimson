extends Control

@onready var music_check_button = $Panel/MusicPanel/Music
@onready var volume_slider = $Panel/MusicVolumePanel/HSlider
@onready var language_option = $Panel/LanguageOption

var current_input_method = "keyboard"
var last_device_id: int = 0
var current_button: String = ""

# Управление геймпадом
var focusable_controls: Array[Control] = []
var current_focus_index: int = 0
var gamepad_mode: bool = false

const NotificationLogicClass = preload("res://scripts/NotificationLogic.gd")
var notification = NotificationLogicClass.new()
var notification_icon = load("res://logo.png")

func _ready():
	add_child(notification)
	
	# Ждём один кадр чтобы все узлы точно инициализировались
	await get_tree().process_frame
	
	# === МУЗЫКА ===
	var music_enabled = SettingsManager.get_setting("music_enabled", true)
	music_check_button.button_pressed = music_enabled
	
	# === ГРОМКОСТЬ ===
	var volume_db = SettingsManager.get_setting("music_volume", -26.0)
	var slider_value = db_to_linear(volume_db) * 210.0
	volume_slider.set_value_no_signal(slider_value)
	volume_slider.value_changed.connect(_on_volume_slider_value_changed)
	
	# === ЯЗЫК ===
	language_option.add_item("English", 0)
	language_option.add_item("Русский", 1)
	language_option.add_item("日本語", 2)
	
	# Загружаем сохранённый язык
	var selected_language = SettingsManager.get_setting("language", "en")
	match selected_language:
		"en":
			language_option.select(0)
		"ru":
			language_option.select(1)
		"ja":
			language_option.select(2)
	
	# Применяем язык
	TranslationServer.set_locale(selected_language)
	
	# Подключаем сигнал
	language_option.item_selected.connect(_on_language_selected)
	
	MusicPlayer.enable_reverb_effect(true, 0.2, 0.4)
	
	# Инициализация управления геймпадом
	_init_focusable_controls()
	_setup_control_signals()

func _init_focusable_controls():
	focusable_controls.clear()
	
	# Добавляем элементы в порядке навигации
	if music_check_button:
		focusable_controls.append(music_check_button)
		music_check_button.focus_mode = Control.FOCUS_NONE
	
	if volume_slider:
		focusable_controls.append(volume_slider)
		volume_slider.focus_mode = Control.FOCUS_NONE
	
	if language_option:
		focusable_controls.append(language_option)
		language_option.focus_mode = Control.FOCUS_NONE
	
	current_focus_index = 0

func _setup_control_signals():
	for control in focusable_controls:
		if control is Button or control is CheckButton or control is Slider or control is OptionButton:
			control.focus_entered.connect(func(): _on_control_focus_entered(control))
			control.focus_exited.connect(func(): _on_control_focus_exited(control))
			control.mouse_entered.connect(func(): _on_control_mouse_entered(control))

func _on_control_focus_entered(control: Control):
	for i in focusable_controls.size():
		if focusable_controls[i] == control:
			current_focus_index = i
			break
	
	# Визуальная обратная связь
	if control is Button or control is CheckButton or control is OptionButton:
		control.modulate = Color(1.2, 1.2, 1.2)
	elif control is Slider:
		control.modulate = Color(1.1, 1.1, 1.1)

func _on_control_focus_exited(control: Control):
	control.modulate = Color(1, 1, 1)

func _on_control_mouse_entered(control: Control):
	if not gamepad_mode:
		return
	
	for i in focusable_controls.size():
		if focusable_controls[i] == control:
			current_focus_index = i
			_set_focus(i)
			break

func _move_focus(direction: int):
	if focusable_controls.is_empty():
		return
	
	_clear_all_focus()
	current_focus_index += direction
	
	if current_focus_index < 0:
		current_focus_index = focusable_controls.size() - 1
	elif current_focus_index >= focusable_controls.size():
		current_focus_index = 0
	
	_set_focus(current_focus_index)

func _set_focus(index: int):
	if index < 0 or index >= focusable_controls.size():
		return
	
	var control = focusable_controls[index]
	control.focus_mode = Control.FOCUS_ALL
	control.grab_focus()

func _clear_all_focus():
	for control in focusable_controls:
		control.focus_mode = Control.FOCUS_NONE
		control.release_focus()

func _activate_current_control():
	if current_focus_index < 0 or current_focus_index >= focusable_controls.size():
		return
	
	var control = focusable_controls[current_focus_index]
	
	if control is CheckButton:
		control.button_pressed = not control.button_pressed
		control.emit_signal("toggled", control.button_pressed)
		_trigger_vibration(0.5, 0.0, 0.1)
	elif control is OptionButton:
		control.emit_signal("pressed")
		_trigger_vibration(0.5, 0.0, 0.1)

func _handle_slider_adjustment(direction: float):
	var control = focusable_controls[current_focus_index]
	if control is Slider:
		var step = control.step if control.step > 0 else 1.0
		var new_value = control.value + (direction * step * 5.0)  # Умножаем на 5 для более быстрого изменения
		new_value = clamp(new_value, control.min_value, control.max_value)
		control.value = new_value
		_trigger_vibration(0.3, 0.0, 0.05)

func _handle_option_button_navigation(direction: int):
	var control = focusable_controls[current_focus_index]
	if control is OptionButton:
		var current_selected = control.selected
		var new_selected = current_selected + direction
		
		if new_selected < 0:
			new_selected = control.item_count - 1
		elif new_selected >= control.item_count:
			new_selected = 0
		
		control.selected = new_selected
		control.emit_signal("item_selected", new_selected)
		_trigger_vibration(0.5, 0.0, 0.1)

func _on_volume_slider_value_changed(value: float) -> void:
	var volume_db = linear_to_db(value / 210.0)
	
	if value < 1.0:
		volume_db = -80.0
	
	MusicPlayer.set_volume(volume_db)

func _on_music_toggled(toggled_on: bool) -> void:
	SettingsManager.set_setting("music_enabled", toggled_on)
	MusicPlayer.music_enabled = toggled_on
	
	if toggled_on:
		if not MusicPlayer.audio_player.playing:
			MusicPlayer.start_music()
		else:
			MusicPlayer.resume_music()
	else:
		MusicPlayer.pause_music()

func _on_language_selected(index: int) -> void:
	var locale = ""
	
	match index:
		0:  # English
			locale = "en"
		1:  # Русский
			locale = "ru"
		2:  # 日本語
			locale = "ja"
	
	# Сохраняем и применяем
	SettingsManager.set_setting("language", locale)
	TranslationServer.set_locale(locale)
	print("Язык изменён на: ", locale)
	
	# Показываем уведомление
	var lang_names = {
		"en": "English",
		"ru": "Русский",
		"ja": "日本語"
	}
	notification.show_notification("Language changed to " + lang_names[locale], notification_icon)

func _input(event):
	var main_scene = get_tree().get_first_node_in_group("main_scene")
	var side_panel = main_scene.get_side_panel()
	
	# Определяем метод ввода
	if event is InputEventKey or event is InputEventMouseButton:
		if current_input_method != "keyboard":
			current_input_method = "keyboard"
			gamepad_mode = false
			_clear_all_focus()
	elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
		if current_input_method != "gamepad":
			current_input_method = "gamepad"
			gamepad_mode = true
			if not side_panel.side_panel_shown:
				_set_focus(current_focus_index)
		var device_id = event.device
		last_device_id = device_id
	
	# Управление боковой панелью
	if side_panel.side_panel_shown:
		if event.is_action_pressed("ui_up") or event.is_action_pressed("up_pad"):
			side_panel.side_panel_move_focus(-1)
			_trigger_vibration(1.0, 0.0, 0.1)
			get_viewport().set_input_as_handled()
		
		elif event.is_action_pressed("ui_down") or event.is_action_pressed("down_pad"):
			side_panel.side_panel_move_focus(1)
			_trigger_vibration(1.0, 0.0, 0.1)
			get_viewport().set_input_as_handled()
		
		elif event.is_action_pressed("ui_accept") or event.is_action_pressed("accept_pad"):
			side_panel.side_panel_change_scene()
			get_viewport().set_input_as_handled()
			MusicPlayer.play_sfx("res://addons/fancy_editor_sounds/keyboard_sounds/key-movement.mp3", -20.0, 1.5)
			MusicPlayer.play_sfx("res://assets/sfx/Fantasy UI SFX/Skyward Hero/SkywardHero_UI (5).wav", -25.0, 1.5)
	
	# Управление элементами Settings
	else:
		if gamepad_mode:
			if event.is_action_pressed("ui_up") or event.is_action_pressed("up_pad"):
				_move_focus(-1)
				_trigger_vibration(1.0, 0.0, 0.1)
				get_viewport().set_input_as_handled()
				MusicPlayer.play_sfx("res://addons/fancy_editor_sounds/keyboard_sounds/button-sidebar-hover.wav", -8.0, 1.8)
			
			elif event.is_action_pressed("ui_down") or event.is_action_pressed("down_pad"):
				_move_focus(1)
				_trigger_vibration(1.0, 0.0, 0.1)
				get_viewport().set_input_as_handled()
				MusicPlayer.play_sfx("res://addons/fancy_editor_sounds/keyboard_sounds/button-sidebar-hover.wav", -8.0, 1.5)
			
			elif event.is_action_pressed("ui_left") or event.is_action_pressed("left_pad"):
				var current_control = focusable_controls[current_focus_index]
				if current_control is Slider:
					_handle_slider_adjustment(-0.15)
					get_viewport().set_input_as_handled()
				elif current_control is OptionButton:
					_handle_option_button_navigation(-1)
					get_viewport().set_input_as_handled()
			
			elif event.is_action_pressed("ui_right") or event.is_action_pressed("right_pad"):
				var current_control = focusable_controls[current_focus_index]
				if current_control is Slider:
					_handle_slider_adjustment(0.1)
					get_viewport().set_input_as_handled()
				elif current_control is OptionButton:
					_handle_option_button_navigation(1)
					get_viewport().set_input_as_handled()
			
			elif event.is_action_pressed("ui_accept") or event.is_action_pressed("accept_pad"):
				_activate_current_control()
				get_viewport().set_input_as_handled()
				MusicPlayer.play_sfx("res://addons/fancy_editor_sounds/keyboard_sounds/key-movement.mp3", -20.0, 1.5)
	
	# Открытие/закрытие боковой панели
	if event.is_action_pressed("menu_key") or event.is_action_pressed("menu_pad"):
		if not side_panel.side_panel_shown:
			_clear_all_focus()
			side_panel.show_panel()
			MusicPlayer.play_sfx("res://assets/sfx/Fantasy UI SFX/Skyward Hero/SkywardHero_UI (5).wav", -25.0, 2.0)
		else:
			side_panel.hide_panel()
			MusicPlayer.play_sfx("res://assets/sfx/Fantasy UI SFX/Skyward Hero/SkywardHero_UI (5).wav", -25.0, 1.5)
			if gamepad_mode:
				_set_focus(current_focus_index)
		get_viewport().set_input_as_handled()
	
	elif event.is_action_pressed("back_pad"):
		if side_panel.side_panel_shown:
			side_panel.hide_panel()
			MusicPlayer.play_sfx("res://assets/sfx/Fantasy UI SFX/Skyward Hero/SkywardHero_UI (5).wav", -25.0, 1.5)
			if gamepad_mode:
				_set_focus(current_focus_index)
			get_viewport().set_input_as_handled()

func _trigger_vibration(weak_strength: float, strong_strength: float, duration_sec: float) -> void:
	if last_device_id < 0 or current_input_method == "keyboard":
		return
	else:
		Input.start_joy_vibration(last_device_id, weak_strength, strong_strength, duration_sec)
