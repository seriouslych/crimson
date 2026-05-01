extends Control

@onready var file_dialog = $FileDialog
@onready var panel = $Panel
@onready var executable_icon = $Panel/TabContainer/GA_TAB_AG/Executable/TextureRect
@onready var front_icon = $Panel/TabContainer/GA_TAB_AG/Front/TextureRect
@onready var back_icon = $Panel/TabContainer/GA_TAB_AG/Back/TextureRect
@onready var spine_icon = $Panel/TabContainer/GA_TAB_AG/Spine/TextureRect
@onready var download_icon = $Panel/TabContainer/GA_TAB_AG/Download/TextureRect
@onready var game_name = $Panel/TabContainer/GA_TAB_AG/LineEdit
@onready var download_button = $Panel/TabContainer/GA_TAB_AG/Download
@onready var option_button = $Panel/TabContainer/GA_TAB_AG/OptionButton
@onready var tab_container = $Panel/TabContainer/GA_TAB_AG/TabContainer

@onready var platexec_icon = $Panel/TabContainer/GA_TAB_OPT/PlatformExec/TextureRect
@onready var covtemp_icon = $Panel/TabContainer/GA_TAB_OPT/CoverTemplate/TextureRect
@onready var platforms_container = $Panel/TabContainer/GA_TAB_OPT/ScrollContainer/VBoxContainer
@onready var platform_name = $Panel/TabContainer/GA_TAB_OPT/LineEdit
@onready var check_button = $Panel/TabContainer/GA_TAB_OPT/CheckButton
@onready var platexec_button = $Panel/TabContainer/GA_TAB_OPT/PlatformExec
@onready var covtemp_button = $Panel/TabContainer/GA_TAB_OPT/CoverTemplate
@onready var platadd_button = $Panel/TabContainer/GA_TAB_OPT/PlatformAdd

# Данные о игре
@export var game_data = {
	"id": "",
	"title": "",
	"front": "",
	"back": "",
	"spine": "",
	"executable": "",
	"platform_executable": "",
	"cover_template": "",
	"box_type": "pc",
	"platform": "steam"
}

var covers_path = "user://covers/"

# Ввод
var current_input_method = "keyboard"
var last_device_id: int = 0
var current_button: String = ""

# Управление геймпадом
var focusable_controls: Array[Control] = []
var current_focus_index: int = 0
var gamepad_mode: bool = false

# Уведомления
const NotificationLogicClass = preload("res://scripts/NotificationLogic.gd")
var notification = NotificationLogicClass.new()
var notification_icon = load("res://logo.png")

var active_tab = 0
var platform_emulator = false

func _ready():
	add_child(notification)
	ensure_covers_directory()
	
	option_button.add_item("PC/Steam", 0)
	option_button.add_item("Xbox Original", 1)
	option_button.add_item("Xbox 360", 2)
	option_button.add_item("Xbox One", 3)
	option_button.add_item("Playstation 1", 4)
	option_button.add_item("Playstation 2", 5)
	option_button.add_item("Playstation 3", 6)
	option_button.add_item("Playstation 4", 7)
	option_button.add_item("Playstation 5", 8)
	option_button.add_item("Nintendo 64", 9)
	option_button.add_item("Nintendo GCube", 10)
	option_button.add_item("Nintendo Wii", 11)
	option_button.add_item("Nintendo Switch", 12)
	option_button.item_selected.connect(_on_option_button_item_selected)
	
	MusicPlayer.enable_reverb_effect(true, 0.2, 0.4)
	
	# Инициализация управления геймпадом
	_init_focusable_controls()
	_setup_control_signals()

func _init_focusable_controls():
	focusable_controls.clear()
	
	# Получаем кнопки из Panel
	var executable_button = $Panel/Executable
	var front_button = $Panel/Front
	var back_button = $Panel/Back
	var spine_button = $Panel/Spine
	var done_button = $Panel/Done
	
	# Добавляем элементы в порядке навигации
	if game_name:
		focusable_controls.append(game_name)
		# LineEdit должен оставаться с FOCUS_ALL для работы мыши
		game_name.focus_mode = Control.FOCUS_ALL
	
	if option_button:
		focusable_controls.append(option_button)
		option_button.focus_mode = Control.FOCUS_NONE
	
	if executable_button:
		focusable_controls.append(executable_button)
		executable_button.focus_mode = Control.FOCUS_NONE
	
	if front_button:
		focusable_controls.append(front_button)
		front_button.focus_mode = Control.FOCUS_NONE
	
	if back_button:
		focusable_controls.append(back_button)
		back_button.focus_mode = Control.FOCUS_NONE
	
	if spine_button:
		focusable_controls.append(spine_button)
		spine_button.focus_mode = Control.FOCUS_NONE
	
	if download_button:
		focusable_controls.append(download_button)
		download_button.focus_mode = Control.FOCUS_NONE
	
	if done_button:
		focusable_controls.append(done_button)
		done_button.focus_mode = Control.FOCUS_NONE
	
	current_focus_index = 0

# Также нужно обновить функцию _set_focus, чтобы она не меняла focus_mode для LineEdit
func _set_focus(index: int):
	if index < 0 or index >= focusable_controls.size():
		return
	
	var control = focusable_controls[index]
	
	# Для LineEdit не меняем focus_mode, так как он уже FOCUS_ALL
	if not control is LineEdit:
		control.focus_mode = Control.FOCUS_ALL
	
	control.grab_focus()

# И обновить функцию _clear_all_focus
func _clear_all_focus():
	for control in focusable_controls:
		# Для LineEdit оставляем FOCUS_ALL
		if not control is LineEdit:
			control.focus_mode = Control.FOCUS_NONE
		control.release_focus()
		

func _setup_control_signals():
	for control in focusable_controls:
		if control is Button or control is LineEdit or control is OptionButton:
			control.focus_entered.connect(func(): _on_control_focus_entered(control))
			control.focus_exited.connect(func(): _on_control_focus_exited(control))
			control.mouse_entered.connect(func(): _on_control_mouse_entered(control))

func _on_control_focus_entered(control: Control):
	for i in focusable_controls.size():
		if focusable_controls[i] == control:
			current_focus_index = i
			break
	
	# Визуальная обратная связь
	if control is Button or control is OptionButton:
		control.modulate = Color(1.2, 1.2, 1.2)
	elif control is LineEdit:
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

func _activate_current_control():
	if current_focus_index < 0 or current_focus_index >= focusable_controls.size():
		return
	
	var control = focusable_controls[current_focus_index]
	
	if control is Button:
		control.emit_signal("pressed")
		_trigger_vibration(0.5, 0.0, 0.1)
	elif control is OptionButton:
		control.emit_signal("pressed")
		_trigger_vibration(0.5, 0.0, 0.1)

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
			MusicPlayer.play_sfx("res://assets/sfx/Fantasy UI SFX/Skyward Hero/SkywardHero_UI (5).wav", -25.0, 1.5)
			MusicPlayer.play_sfx("res://addons/fancy_editor_sounds/keyboard_sounds/key-movement.mp3", -20.0, 1.5)
	
	# Управление элементами GameAdd
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
				if focusable_controls[current_focus_index] is OptionButton:
					_handle_option_button_navigation(-1)
					_trigger_vibration(1.0, 0.0, 0.1)
					get_viewport().set_input_as_handled()
					MusicPlayer.play_sfx("res://addons/fancy_editor_sounds/keyboard_sounds/button-sidebar-hover.wav", -8.0, 1.5)
			
			elif event.is_action_pressed("ui_right") or event.is_action_pressed("right_pad"):
				if focusable_controls[current_focus_index] is OptionButton:
					_handle_option_button_navigation(1)
					_trigger_vibration(1.0, 0.0, 0.1)
					get_viewport().set_input_as_handled()
					MusicPlayer.play_sfx("res://addons/fancy_editor_sounds/keyboard_sounds/button-sidebar-hover.wav", -8.0, 1.8)
			
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

# === Остальные функции остаются без изменений ===

func ensure_covers_directory():
	if not DirAccess.dir_exists_absolute(covers_path):
		var result = DirAccess.open("user://").make_dir_recursive(covers_path.get_file())
		if result == OK:
			print("Папка covers создана: ", covers_path)
		else:
			print("Ошибка создания папки covers: ", result)

func generate_unique_id() -> String:
	var timestamp = Time.get_unix_time_from_system()
	var random_part = randi() % 999999
	return "game_%d_%06d" % [timestamp, random_part]

func save_game_data() -> bool:
	var title = game_data["title"].strip_edges()
	if title == "":
		return false
	
	if game_data["id"] == "":
		game_data["id"] = generate_unique_id()
	
	var file_path = "user://games/" + game_data["id"] + ".json"
	
	if not DirAccess.dir_exists_absolute("user://games/"):
		var result = DirAccess.open("user://").make_dir("games")
		if result != OK:
			print("Ошибка создания директории games: ", result)
			return false
	
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file:
		var json_string = JSON.stringify(game_data)
		file.store_string(json_string)
		file.close()
		print("Игра сохранена в: ", file_path)
		return true
	else:
		print("Ошибка создания файла: ", file_path)
		return false

func reset_form():
	game_data = {
		"id": "",
		"title": "",
		"front": "",
		"back": "",
		"spine": "",
		"executable": "",
		"box_type": "xbox"
	}
	
	game_name.text = ""
	
	var plus_icon = load("res://assets/kenney_input-prompts_1.4/Nintendo Switch 2/Default/switch_button_plus.png")
	var download_icon_path = load("res://assets/icons/download.png")
	executable_icon.texture = plus_icon
	front_icon.texture = plus_icon
	back_icon.texture = plus_icon
	spine_icon.texture = plus_icon
	download_icon.texture = download_icon_path
	
	option_button.select(0)
	download_button.disabled = false
	download_button.text = tr("GA_COVERS_BT")
	
	print("Форма очищена")

func load_game_by_id(game_id: String) -> Dictionary:
	var file_path = "user://games/" + game_id + ".json"
	
	if not FileAccess.file_exists(file_path):
		print("Игра с ID не найдена: ", game_id)
		return {}
	
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		print("Ошибка открытия файла: ", file_path)
		return {}
	
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var parse_result = json.parse(json_string)
	
	if parse_result != OK:
		print("Ошибка парсинга JSON: ", file_path)
		return {}
	
	return json.data

func find_game_id_by_title(game_title: String) -> String:
	var dir = DirAccess.open("user://games/")
	if not dir:
		print("Не удалось открыть папку games")
		return ""
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		if file_name.ends_with(".json"):
			var file_path = "user://games/" + file_name
			var file = FileAccess.open(file_path, FileAccess.READ)
			
			if file:
				var json_string = file.get_as_text()
				file.close()
				
				var json = JSON.new()
				if json.parse(json_string) == OK:
					var data = json.data
					if data.has("title") and data["title"] == game_title:
						dir.list_dir_end()
						return data["id"]
		
		file_name = dir.get_next()
	
	dir.list_dir_end()
	return ""

func update_game_data_by_id(game_id: String, updated_data: Dictionary) -> bool:
	var file_path = "user://games/" + game_id + ".json"
	
	if not FileAccess.file_exists(file_path):
		print("Игра с ID не найдена: ", game_id)
		return false
	
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		print("Ошибка открытия файла: ", file_path)
		return false
	
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var parse_result = json.parse(json_string)
	
	if parse_result != OK:
		print("Ошибка парсинга JSON: ", file_path)
		return false
	
	var existing_data = json.data
	
	for key in updated_data.keys():
		if key == "id":
			print("Предупреждение: изменение ID запрещено")
			continue
		if key in existing_data:
			existing_data[key] = updated_data[key]
		else:
			print("Предупреждение: неизвестное поле '", key, "'")
	
	file = FileAccess.open(file_path, FileAccess.WRITE)
	if not file:
		print("Ошибка записи файла: ", file_path)
		return false
	
	var updated_json_string = JSON.stringify(existing_data)
	file.store_string(updated_json_string)
	file.close()
	
	print("Игра обновлена: ", game_id)
	return true

func update_game_data_by_title(game_title: String, updated_data: Dictionary) -> bool:
	var game_id = find_game_id_by_title(game_title)
	if game_id == "":
		print("Игра не найдена по названию: ", game_title)
		return false
	
	return update_game_data_by_id(game_id, updated_data)

func delete_game_by_id(game_id: String) -> bool:
	var file_path = "user://games/" + game_id + ".json"

	if not FileAccess.file_exists(file_path):
		print("Игра с таким ID не найдена: ", game_id)
		return false

	var err := DirAccess.remove_absolute(file_path)
	if err != OK:
		print("Ошибка удаления файла: ", err)
		return false

	print("Игра удалена: ", game_id)
	return true

func get_steamboxcover_path() -> String:
	var exe_path = OS.get_executable_path()
	var exe_dir = exe_path.get_base_dir()
	
	var steamboxcover_path: String
	if OS.get_name() == "Windows":
		steamboxcover_path = exe_dir + "/bin/steamboxcover.exe"
	else:
		steamboxcover_path = exe_dir + "/bin/steamboxcover"
	
	var current_dir = OS.get_environment("PWD")
	if current_dir == "":
		current_dir = exe_dir
	
	var alt_path: String
	if OS.get_name() == "Windows":
		alt_path = current_dir + "/bin/steamboxcover.exe"
	else:
		alt_path = current_dir + "/bin/steamboxcover"
	
	if not FileAccess.file_exists(steamboxcover_path) and FileAccess.file_exists(alt_path):
		return alt_path
	
	return steamboxcover_path

func get_spine_template_path() -> String:
	var exe_path = OS.get_executable_path()
	var exe_dir = exe_path.get_base_dir()
	return exe_dir + "/bin/" + game_data["platform"] + "_spine.png"

func normalize_filename_for_comparison(filename: String) -> Dictionary:
	var normalized = filename
	
	if normalized.ends_with(".png") or normalized.ends_with(".jpg") or normalized.ends_with(".jpeg") or normalized.ends_with(".bmp") or normalized.ends_with(".webp"):
		normalized = normalized.get_basename()
	
	var cover_type = "front"
	if normalized.to_lower().ends_with("_back"):
		cover_type = "back"
		normalized = normalized.substr(0, normalized.length() - 5)
	elif normalized.to_lower().ends_with("_spine"):
		cover_type = "spine"
		normalized = normalized.substr(0, normalized.length() - 6)
	
	var original_normalized = normalized
	normalized = normalized.replace(";", " ").replace(":", " ").replace("!", " ").replace("?", " ").replace(",", " ").replace("-", " ").replace("_", " ")
	normalized = normalized.strip_edges()
	normalized = normalized.to_lower()
	var normalized_no_spaces = normalized.replace(" ", "")
	
	return {"name": normalized, "name_no_spaces": normalized_no_spaces, "original": original_normalized.to_lower(), "type": cover_type}

func find_covers_for_game(game_title: String) -> Dictionary:
	var found = {}
	
	var dir = DirAccess.open(covers_path)
	if not dir:
		print("Не удалось открыть папку covers: ", covers_path)
		return found
	
	print("Ищем обложки для игры: ", game_title, " в папке: ", covers_path)
	
	var sanitized_game_title = sanitize_filename_for_steamboxcover(game_title)
	print("Санитизированный заголовок игры для поиска: ", sanitized_game_title)
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		if file_name.ends_with(".png") or file_name.ends_with(".jpg") or file_name.ends_with(".jpeg") or file_name.ends_with(".bmp") or file_name.ends_with(".webp"):
			var original_basename = file_name.get_basename()
			var lower_filename = original_basename.to_lower()
			
			var cover_type = "front"
			if lower_filename.ends_with("_back"):
				cover_type = "back"
			elif lower_filename.ends_with("_spine"):
				cover_type = "spine"
			elif lower_filename.ends_with("_logo"):
				file_name = dir.get_next()
				continue
			
			var filename_without_suffix = original_basename
			if cover_type == "back":
				filename_without_suffix = original_basename.substr(0, original_basename.length() - 5)
			elif cover_type == "spine":
				filename_without_suffix = original_basename.substr(0, original_basename.length() - 6)
			
			var sanitized_filename = sanitize_filename_for_steamboxcover(filename_without_suffix)
			
			print("Сравниваем: '", sanitized_filename, "' (тип: ", cover_type, ") с '", sanitized_game_title, "'")
			
			if sanitized_filename == sanitized_game_title:
				found[cover_type] = covers_path + file_name
				print("Найдена ", cover_type, " обложка: ", file_name)
		
		file_name = dir.get_next()
	
	dir.list_dir_end()
	
	print("Найдено обложек: ", found.size())
	for key in found:
		print("  ", key, ": ", found[key])
	
	return found

func apply_found_covers(covers: Dictionary):
	var icon_path: String = "res://assets/icons/check.png"
	
	for cover_type in covers:
		var path = covers[cover_type]
		game_data[cover_type] = path
		
		match cover_type:
			"front": 
				front_icon.texture = load(icon_path)
				print("Применена передняя обложка: ", path)
			"back": 
				back_icon.texture = load(icon_path)
				print("Применена задняя обложка: ", path)
			"spine": 
				spine_icon.texture = load(icon_path)
				print("Применена боковая обложка: ", path)

	if not covers.has("front"):
		var plus_icon = load("res://assets/kenney_input-prompts_1.4/Nintendo Switch 2/Default/switch_button_plus.png")
		front_icon.texture = plus_icon
		print("Не найдена передняя обложка, оставлена иконка плюса")
	
	if not covers.has("back"):
		var plus_icon = load("res://assets/kenney_input-prompts_1.4/Nintendo Switch 2/Default/switch_button_plus.png")
		back_icon.texture = plus_icon
		print("Не найдена задняя обложка, оставлена иконка плюса")
	
	if not covers.has("spine"):
		var plus_icon = load("res://assets/kenney_input-prompts_1.4/Nintendo Switch 2/Default/switch_button_plus.png")
		spine_icon.texture = plus_icon
		print("Не найдена боковая обложка, оставлена иконка плюса")

func sanitize_filename_for_steamboxcover(filename: String) -> String:
	var safe := filename
	var invalid_chars := ["<", ">", ":", "\"", "/", "\\", "|", "?", "*", ";", "!", ".", "'", "`", "~"]
	
	for c in invalid_chars:
		safe = safe.replace(c, " ")
	
	while safe.contains("  "):
		safe = safe.replace("  ", " ")
	
	safe = safe.strip_edges()
	
	while safe.ends_with("."):
		safe = safe.substr(0, safe.length() - 1)
	
	if safe.length() > 200:
		safe = safe.substr(0, 200)
	
	var no_spaces = safe.replace(" ", "")
	return no_spaces

func _on_fs_pressed() -> void:
	current_button = "executable"
	_file_dialog()

func _on_front_pressed() -> void:
	current_button = "front"
	_file_dialog()

func _on_back_pressed() -> void:
	current_button = "back"
	_file_dialog()

func _on_spine_pressed() -> void:
	current_button = "spine"
	_file_dialog()

func _on_download_pressed() -> void:
	var title = game_name.text.strip_edges()
	if title == "":
		notification.show_notification(tr("NTF_TYPEGAMENAME"), notification_icon)
		return
	
	var steamboxcover_path = get_steamboxcover_path()
	var spine_template_path = get_spine_template_path()
	
	if not FileAccess.file_exists(steamboxcover_path):
		notification.show_notification(tr("NTF_SBCNOTFOUND"), notification_icon)
		return
		
	var args = []
	args.append("--game")
	args.append(title)
	args.append("--output_dir")
	args.append(ProjectSettings.globalize_path(covers_path))
	args.append("-k")
	args.append("ac6407f383cb7696689026c4576a7758")
	args.append("--only_steamgriddb")
	
	if spine_template_path != "":
		args.append("--spine_template")
		args.append(ProjectSettings.globalize_path(spine_template_path))
		
	download_button.text = tr("GA_DOWNCOVERS_BT")
	download_button.disabled = true
	
	await get_tree().create_timer(0.1).timeout
	
	var output = []
	var result = OS.execute(steamboxcover_path, args, output, true, false)
	
	download_button.text = tr("GA_COVERS_BT")
	download_button.disabled = false
	download_icon.texture = load("res://assets/icons/check.png")
	
	if result != OK:
		notification.show_notification(tr("NTF_COVERDOWNFAILED"), notification_icon)
		
	if result == OK:
		notification.show_notification(tr("NTF_COVERDOWNSUCCESS"), notification_icon)
		
		var found_covers = find_covers_for_game(title)
		if found_covers.size() > 0:
			apply_found_covers(found_covers)

func _on_done_pressed() -> void:
	if game_name.text.strip_edges() == "":
		notification.show_notification(tr("NTF_TYPEGAMENAME"), notification_icon)
		return
		
	game_data["title"] = game_name.text.strip_edges()
	
	if save_game_data():
		notification.show_notification(tr("NTF_GAMESAVESUCCESS"), notification_icon)
		await get_tree().create_timer(1.0).timeout
		reset_form()
	else:
		notification.show_notification(tr("NTF_GAMESAVEFAILED"), notification_icon)

func _file_dialog():
	file_dialog.clear_filters()
	if current_button == "executable" or current_button == "platform_executable":
		if OS.get_name() == "Windows":
			file_dialog.add_filter("*.exe", "Windows Executable")
			file_dialog.add_filter("*.bat", "Batch Files")
			file_dialog.add_filter("*.cmd", "Command Files")
			file_dialog.add_filter("*.lnk", "Link")
			file_dialog.add_filter("*.url", "Browser link")
		elif OS.get_name() == "Linux":
			file_dialog.add_filter("*.sh", "Shell Scripts")
			file_dialog.add_filter("*.exe", "Windows Executable (Wine)")
			file_dialog.add_filter("*.x86_64", "x86 64 Bit Executable")
			file_dialog.add_filter("*.desktop", "Desktop link")
			file_dialog.add_filter("*", "All Files")
		elif OS.get_name() == "macOS":
			file_dialog.add_filter("*.app", "macOS Applications")
			file_dialog.add_filter("*.sh", "Shell Scripts")
			file_dialog.add_filter("*", "All Files")
	elif current_button == "cover_template":
		file_dialog.add_filter("*.png", "PNG Images")
	else:
		file_dialog.add_filter("*.png", "PNG Images")
		file_dialog.add_filter("*.jpg", "JPEG Images") 
		file_dialog.add_filter("*.jpeg", "JPEG Images")
		file_dialog.add_filter("*.bmp", "BMP Images")
		file_dialog.add_filter("*.webp", "WebP Images")
		
	file_dialog.popup()

func _on_file_selected(path):
	var icon_path: String = "res://assets/icons/check.png"
	match current_button:
		"executable": executable_icon.texture = load(icon_path)
		"front": front_icon.texture = load(icon_path)
		"back": back_icon.texture = load(icon_path)
		"spine": spine_icon.texture = load(icon_path)
		"platform_executable": platexec_icon.texture = load(icon_path)
		"cover_template": covtemp_icon.texture = load(icon_path)
		
	if not FileAccess.file_exists(path):
		notification.show_notification(tr("NTF_FILENOTFOUND"), notification_icon)
		return
	
	game_data[current_button] = path

func _on_option_button_item_selected(index):
	match index:
		0:
			game_data["box_type"] = "pc"
			game_data["platform"] = "steam"
		1:
			game_data["box_type"] = "xbox"
			game_data["platform"] = "xorig"
		2:
			game_data["box_type"] = "xbox"
			game_data["platform"] = "x360"
		3:
			game_data["box_type"] = "xbox"
			game_data["platform"] = "xone"
		4:
			game_data["box_type"] = "pc"
			game_data["platform"] = "psx"
		5:
			game_data["box_type"] = "pc"
			game_data["platform"] = "ps2"
		6:
			game_data["box_type"] = "pc"
			game_data["platform"] = "ps3"
		7:
			game_data["box_type"] = "pc"
			game_data["platform"] = "ps4"
		8:
			game_data["box_type"] = "pc"
			game_data["platform"] = "ps5"
		9:
			game_data["box_type"] = "pc"
			game_data["platform"] = "n64"
		10:
			game_data["box_type"] = "pc"
			game_data["platform"] = "gc"
		11:
			game_data["box_type"] = "pc"
			game_data["platform"] = "wii"
		12:
			game_data["box_type"] = "pc"
			game_data["platform"] = "switch"

func _trigger_vibration(weak_strength: float, strong_strength: float, duration_sec: float) -> void:
	if last_device_id < 0 or current_input_method == "keyboard":
		return
	else:
		Input.start_joy_vibration(last_device_id, weak_strength, strong_strength, duration_sec)

func _on_tab_container_tab_selected(tab: int) -> void:
	active_tab = tab

func _on_check_button_toggled(state: bool) -> void:
	platform_emulator = state
	if active_tab == 1:
		if platform_emulator:
			platexec_button.disabled = false
			platexec_icon.visible = true
		else:
			platexec_button.disabled = true
			platexec_icon.visible = false

func _on_platform_exec_pressed() -> void:
	current_button = "platform_executable"
	_file_dialog()

func _on_cover_template_pressed() -> void:
	current_button = "cover_template"
	_file_dialog()

func _on_platform_add_pressed() -> void:
	game_data["platform"] = platform_name.text.strip_edges()
