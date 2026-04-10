class_name CoverFlow
extends Control

@onready var viewport_container = $ViewportContainer
@onready var viewport_3d = $ViewportContainer/SubViewport
@onready var camera_3d = $ViewportContainer/SubViewport/Camera3D
@onready var animationplayer = $GameInfo/AnimationPlayer
@onready var file_dialog = $GameInfo/FileDialog

@onready var game_title_label = $GameTitleLabel
@onready var game_state_label = $GameTitleLabel/GameStateLabel

@onready var keyboard_control = $Keyboard
@onready var gamepad_control = $Gamepad
@onready var a_button = $Gamepad/Instruction/Zapusk/Play
@onready var dpad_button = $Gamepad/Instruction/Navigation/Navigation
@onready var start_button = $Gamepad/Add/Start
@onready var controller_icon = $Gamepad/Controller/Icon

@onready var game_info_node = $GameInfo
@onready var game_info_node_canvas = $GameInfo/CanvasLayer
@onready var game_info_logo = $GameInfo/CanvasLayer/Panel/GameLogo
@onready var game_fallback_label = $GameInfo/CanvasLayer/Panel/GameName
@onready var game_time_label = $GameInfo/CanvasLayer/Panel/Time
@onready var game_date_label = $GameInfo/CanvasLayer/Panel/Date

@onready var editgame_icon = $GameInfo/CanvasLayer/Panel/Edit/KeyIcon
@onready var editgame_gamepad_icon = $GameInfo/CanvasLayer/Panel/Edit/GamepadIcon
@onready var editgame_line = $GameInfo/CanvasLayer/Panel/LineEdit
@onready var editgame_label = $GameInfo/CanvasLayer/Panel/Edit
@onready var editgame_executable = $GameInfo/CanvasLayer/Panel/Executable
@onready var editgame_front = $GameInfo/CanvasLayer/Panel/Front
@onready var editgame_back = $GameInfo/CanvasLayer/Panel/Back
@onready var editgame_spine = $GameInfo/CanvasLayer/Panel/Spine
@onready var editgame_delete = $GameInfo/CanvasLayer/Panel/Delete
@onready var editgame_executable_icon = $GameInfo/CanvasLayer/Panel/Executable/TextureRect
@onready var editgame_front_icon = $GameInfo/CanvasLayer/Panel/Front/TextureRect
@onready var editgame_back_icon = $GameInfo/CanvasLayer/Panel/Back/TextureRect
@onready var editgame_spine_icon = $GameInfo/CanvasLayer/Panel/Spine/TextureRect

@onready var loading_icon = $Loading

var games: Array[GameLoader.GameData] = []
var game_covers: Array[GameCover3D] = []
var current_index: int = 0
var running_games := {}
var logo_cache: Dictionary = {}
var failed_api_games: Array[String] = []
var updated_game_data: Dictionary = {}

# ========== ОПТИМИЗАЦИЯ: Пул обложек ==========
const MAX_VISIBLE_COVERS = 7  # Максимум видимых обложек одновременно
var cover_pool: Array[GameCover3D] = []
var active_covers: Dictionary = {}  # {game_index: GameCover3D}

# ========== ОПТИМИЗАЦИЯ: Кэш материалов ==========
var material_cache: Dictionary = {}  # {texture_path: StandardMaterial3D}

# ========== ОПТИМИЗАЦИЯ: Асинхронная загрузка ==========
var logo_load_queue: Array[int] = []  # Индексы игр для загрузки логотипов
var is_loading_logo: bool = false

@export var cover_spacing: float = 6.0
@export var side_angle_y: float = 35.0
@export var side_angle_x: float = 0.0
@export var side_offset: float = 2.0

var notification
var notification_icon = load("res://logo.png")

const GamepadTypeClass = preload("res://scripts/GamepadType.gd")
var gamepadtype = GamepadTypeClass.new()

const GameTimeTrackerClass = preload("res://scripts/GameTimeTracker.gd")
var time_tracker: GameTimeTracker

var GameAddScript = load("res://scripts/GameAdd.gd")
var game_manager = GameAddScript.new()
var current_button: String = ""

var first_update: bool = true
var current_input_method = "keyboard"
var last_device_id: int = -1

var missing_logo_queue := []
var processing_request := ""

var edit_mode = false
var delete_mode = false
var editing = false
var edit_cooldown = 0.5

var edit_focusable_controls: Array[Control] = []
var edit_current_focus_index: int = 0
var edit_gamepad_mode: bool = false

var ud_animation_finished = true

# game_title -> { pid: int, start_time: int }
var logo_processes: Dictionary = {}

const LOGO_PROCESS_TIMEOUT_MS := 15000 # 15 секунд

func _ready():
	loading_icon.visible = true
	
	find_notification()
	time_tracker = GameTimeTrackerClass.get_instance()

	file_dialog.file_selected.connect(func(path): _on_file_selected(path))
	editgame_executable.pressed.connect(func(): _on_fs_pressed())
	editgame_front.pressed.connect(func(): _on_front_pressed())
	editgame_back.pressed.connect(func(): _on_back_pressed())
	editgame_spine.pressed.connect(func(): _on_spine_pressed())
	editgame_delete.pressed.connect(func(): _on_delete_pressed())
	
	load_games()
	setup_keyboard_ui()
	
	await get_tree().process_frame
	
	# ОПТИМИЗАЦИЯ: Создаём пул обложек вместо всех сразу
	create_cover_pool()
	
	# Предзагрузка логотипов в фоне
	start_background_logo_loading()
	
	for device_id in Input.get_connected_joypads():
		update_controller_icon(device_id)
		
	await get_tree().process_frame
	update_display()
	
	time_tracker.cleanup_game_time(games)
	
	loading_icon.visible = false
	
	MusicPlayer.enable_reverb_effect(false, 0.0, 0.0)

# ========== ОПТИМИЗАЦИЯ: Создание пула обложек ==========
func create_cover_pool():
	"""Создаёт ограниченный пул переиспользуемых обложек"""
	for i in range(MAX_VISIBLE_COVERS):
		var cover = GameCover3D.new()
		viewport_3d.add_child(cover)
		cover_pool.append(cover)
		cover.visible = false
	
	print("✓ Создан пул из ", MAX_VISIBLE_COVERS, " обложек")

func get_cover_from_pool() -> GameCover3D:
	"""Получает свободную обложку из пула"""
	for cover in cover_pool:
		if not cover.visible:
			return cover
	return null

func return_cover_to_pool(cover: GameCover3D):
	"""Возвращает обложку в пул"""
	cover.visible = false
	cover.game_data = null

# ========== ОПТИМИЗАЦИЯ: Кэширование материалов ==========
func get_cached_material(texture_path: String) -> StandardMaterial3D:
	"""Возвращает кэшированный материал или создаёт новый"""
	if material_cache.has(texture_path):
		return material_cache[texture_path]
	
	var texture = GameLoader.load_texture_from_path(texture_path)
	if not texture:
		return null
	
	var material = StandardMaterial3D.new()
	material.albedo_texture = texture
	material.albedo_color = Color.WHITE
	material.metallic = 0.1
	material.roughness = 0.7
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	
	material_cache[texture_path] = material
	return material

# ========== ОПТИМИЗАЦИЯ: Асинхронная загрузка логотипов ==========
func start_background_logo_loading():
	"""Запускает фоновую загрузку логотипов"""
	# Сначала загружаем логотип текущей игры
	if current_index < games.size():
		_load_logo_async(current_index)
	
	# Затем загружаем соседние
	for offset in [1, -1, 2, -2, 3, -3]:
		var idx = current_index + offset
		if idx >= 0 and idx < games.size():
			logo_load_queue.append(idx)
	
	_process_logo_queue()

func _process_logo_queue():
	"""Обрабатывает очередь загрузки логотипов"""
	if is_loading_logo or logo_load_queue.is_empty():
		return
	
	is_loading_logo = true
	var game_idx = logo_load_queue.pop_front()
	
	await _load_logo_async(game_idx)
	
	is_loading_logo = false
	_process_logo_queue()

func _load_logo_async(game_idx: int):
	"""Асинхронно загружает логотип для игры"""
	if game_idx < 0 or game_idx >= games.size():
		return
	
	var game_title = games[game_idx].title
	
	# Проверяем кэш
	if logo_cache.has(game_title):
		return
	
	# Проверяем на диске
	var cached_logo = load_logo_from_cache(game_title)
	if cached_logo:
		logo_cache[game_title] = {"texture": cached_logo, "is_fallback": false}
		return
	
	# Запускаем API запрос (без блокировки)
	request_logo_with_steamboxcover(game_title)
	
	# Небольшая задержка между запросами
	await get_tree().create_timer(0.1).timeout

func _init_edit_focusable_controls():
	edit_focusable_controls.clear()
	
	if editgame_line:
		edit_focusable_controls.append(editgame_line)
		editgame_line.focus_mode = Control.FOCUS_ALL
	
	if editgame_executable:
		edit_focusable_controls.append(editgame_executable)
		editgame_executable.focus_mode = Control.FOCUS_NONE
	
	if editgame_front:
		edit_focusable_controls.append(editgame_front)
		editgame_front.focus_mode = Control.FOCUS_NONE
	
	if editgame_back:
		edit_focusable_controls.append(editgame_back)
		editgame_back.focus_mode = Control.FOCUS_NONE
	
	if editgame_spine:
		edit_focusable_controls.append(editgame_spine)
		editgame_spine.focus_mode = Control.FOCUS_NONE
	
	if editgame_delete:
		edit_focusable_controls.append(editgame_delete)
		editgame_delete.focus_mode = Control.FOCUS_NONE
	
	edit_current_focus_index = 0

func _setup_edit_control_signals():
	for control in edit_focusable_controls:
		if control is Button or control is LineEdit:
			control.focus_entered.connect(func(): _on_edit_control_focus_entered(control))
			control.focus_exited.connect(func(): _on_edit_control_focus_exited(control))
			control.mouse_entered.connect(func(): _on_edit_control_mouse_entered(control))

func _on_edit_control_focus_entered(control: Control):
	for i in edit_focusable_controls.size():
		if edit_focusable_controls[i] == control:
			edit_current_focus_index = i
			break
	
	if control is Button:
		control.modulate = Color(1.2, 1.2, 1.2)
	elif control is LineEdit:
		control.modulate = Color(1.1, 1.1, 1.1)

func _on_edit_control_focus_exited(control: Control):
	control.modulate = Color(1, 1, 1)

func _on_edit_control_mouse_entered(control: Control):
	if not edit_gamepad_mode:
		return
	
	for i in edit_focusable_controls.size():
		if edit_focusable_controls[i] == control:
			edit_current_focus_index = i
			_set_edit_focus(i)
			break

func _move_edit_focus(direction: int):
	if edit_focusable_controls.is_empty():
		return
	
	_clear_all_edit_focus()
	edit_current_focus_index += direction
	
	if edit_current_focus_index < 0:
		edit_current_focus_index = edit_focusable_controls.size() - 1
	elif edit_current_focus_index >= edit_focusable_controls.size():
		edit_current_focus_index = 0
	
	_set_edit_focus(edit_current_focus_index)

func _set_edit_focus(index: int):
	if index < 0 or index >= edit_focusable_controls.size():
		return
	
	var control = edit_focusable_controls[index]
	
	if not control is LineEdit:
		control.focus_mode = Control.FOCUS_ALL
	
	control.grab_focus()

func _clear_all_edit_focus():
	for control in edit_focusable_controls:
		if not control is LineEdit:
			control.focus_mode = Control.FOCUS_NONE
		control.release_focus()

func _activate_edit_control():
	if edit_current_focus_index < 0 or edit_current_focus_index >= edit_focusable_controls.size():
		return
	
	var control = edit_focusable_controls[edit_current_focus_index]
	
	if control is Button:
		control.emit_signal("pressed")
		_trigger_vibration(0.5, 0.0, 0.1)

func is_animation_in_progress() -> bool:
	return not ud_animation_finished

func find_notification():
	var main_scene = get_tree().get_first_node_in_group("main_scene")
	if main_scene and main_scene.has_method("get_notification"):
		notification = main_scene.get_notification()
	else:
		var parent = get_parent()
		while parent:
			if parent.get("notification"):
				notification = parent.notification
				break
			parent = parent.get_parent()

func load_games():
	games = GameLoader.load_all_games()
	cleanup_unused_covers()

func cleanup_unused_covers():
	var covers_dir = "user://covers/"
	if not DirAccess.dir_exists_absolute(covers_dir):
		return
	
	var used_covers = {}
	
	for game in games:
		if game.get("front") != "":
			used_covers[game.front] = true
		if game.get("back") != "":
			used_covers[game.back] = true
		if game.get("spine") != "":
			used_covers[game.spine] = true
		
		var possible_logo_names = get_possible_logo_filenames(game.title)
		for logo_name in possible_logo_names:
			used_covers[covers_dir + logo_name] = true
	
	var dir = DirAccess.open(covers_dir)
	if not dir:
		return
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		if not file_name.begins_with("."):
			var full_path = covers_dir + file_name
			if not used_covers.has(full_path):
				dir.remove(file_name)
		file_name = dir.get_next()
	
	dir.list_dir_end()

func setup_keyboard_ui():
	keyboard_control.visible = true
	gamepad_control.visible = false
	editgame_icon.visible = true
	editgame_gamepad_icon.visible = false
	
func setup_gamepad_ui():
	keyboard_control.visible = false
	gamepad_control.visible = true
	editgame_icon.visible = false
	editgame_gamepad_icon.visible = true

func update_controller_icon(device_id: int):
	var joy_name = Input.get_joy_name(device_id).to_lower()
	var controller_type = gamepadtype.detect_controller_type(joy_name)
	
	match controller_type:
		gamepadtype.ControllerType.XBOX:
			controller_icon.texture = load(gamepadtype.ICON_XBOX_CONTROLLER)
			a_button.texture = load(gamepadtype.ICON_XBOX_A)
			dpad_button.texture = load(gamepadtype.ICON_XBOX_DPAD)
			start_button.texture = load(gamepadtype.ICON_XBOX_START)
			editgame_gamepad_icon.texture = load(gamepadtype.ICON_XBOX_BACK) 
		gamepadtype.ControllerType.PLAYSTATION:
			controller_icon.texture = load(gamepadtype.ICON_PS_CONTROLLER)
			a_button.texture = load(gamepadtype.ICON_PS_A)
			dpad_button.texture = load(gamepadtype.ICON_PS_DPAD)
			start_button.texture = load(gamepadtype.ICON_PS_START)
			editgame_gamepad_icon.texture = load(gamepadtype.ICON_PS_BACK)
		_:
			controller_icon.texture = load(gamepadtype.ICON_GENERIC_CONTROLLER)
			a_button.texture = load(gamepadtype.ICON_GENERIC_A)
			dpad_button.texture = load(gamepadtype.ICON_GENERIC_DPAD)
			start_button.texture = load(gamepadtype.ICON_GENERIC_START)
			editgame_gamepad_icon.texture = load(gamepadtype.ICON_GENERIC_BACK)

# ========== ОПТИМИЗАЦИЯ: Обновление только видимых обложек ==========
func update_display():
	if games.is_empty():
		game_title_label.text = tr("CF_NOGAMES_TIP")
		return
	
	game_title_label.text = games[current_index].title
	
	# Определяем диапазон видимых обложек
	var half_visible = MAX_VISIBLE_COVERS / 2
	var start_idx = max(0, current_index - half_visible)
	var end_idx = min(games.size() - 1, current_index + half_visible)
	
	# Очищаем старые активные обложки
	var new_active_covers = {}
	
	for i in range(start_idx, end_idx + 1):
		var cover: GameCover3D
		
		# Переиспользуем существующую или берём из пула
		if active_covers.has(i):
			cover = active_covers[i]
		else:
			cover = get_cover_from_pool()
			if not cover:
				continue
			
			# Устанавливаем данные игры с кэшированными материалами
			cover.set_game_data(games[i])
			
			# ОПТИМИЗАЦИЯ: Используем кэшированные материалы
			if games[i].front != "":
				var mat = get_cached_material(games[i].front)
				if mat and cover.mesh_instance:
					cover.front_material = mat
			if games[i].back != "":
				var mat = get_cached_material(games[i].back)
				if mat and cover.mesh_instance:
					cover.back_material = mat
			if games[i].spine != "":
				var mat = get_cached_material(games[i].spine)
				if mat and cover.mesh_instance:
					cover.spine_material = mat
			
			cover.apply_materials_to_mesh()
		
		cover.visible = true
		new_active_covers[i] = cover
		
		# Вычисляем позицию
		var offset = i - current_index
		var pos = Vector3()
		var rot = Vector3()
		var scl = Vector3.ONE
		
		if offset == 0:
			pos = Vector3(0, 0, 0)
			rot = Vector3(-side_angle_x, side_angle_y, 0)
			scl = Vector3(1.2, 1.2, 1.2)
			cover.set_selected(true)
			game_state_label.visible = running_games.has(games[i].title)
			show_game_info(games[current_index].title)
		else:
			var abs_offset = abs(offset)
			pos = Vector3(offset * abs_offset, offset * cover_spacing, abs_offset * 1.5)
			rot = Vector3(-side_angle_x, side_angle_y, 0)
			scl = Vector3(0.8, 0.8, 0.8)
			cover.set_selected(false)
		
		if first_update:
			cover.position = pos
			cover.rotation_degrees = rot
			cover.scale = scl
		
		if not active_covers.has(i):
			cover.position = pos
			cover.rotation_degrees = rot
			cover.scale = scl
		
		cover.set_target_transform(pos, rot, scl)
	
	# Возвращаем неиспользуемые обложки в пул
	for idx in active_covers.keys():
		if not new_active_covers.has(idx):
			return_cover_to_pool(active_covers[idx])
	
	active_covers = new_active_covers
	first_update = false

func _on_up_pressed():
	if games.size() <= 1:
		return
	
	current_index += 1
	if current_index >= games.size():
		current_index = games.size() - 1
	
	update_display()
	
	# Подгружаем логотипы для новых видимых игр
	_queue_nearby_logos()
	
func _on_down_pressed():
	if games.size() <= 1:
		return
	
	current_index -= 1
	if current_index < 0:
		current_index = 0
	
	update_display()
	
	# Подгружаем логотипы для новых видимых игр
	_queue_nearby_logos()

func _queue_nearby_logos():
	"""Добавляет соседние игры в очередь загрузки логотипов"""
	for offset in [-3, -2, -1, 1, 2, 3]:
		var idx = current_index + offset
		if idx >= 0 and idx < games.size():
			if not logo_load_queue.has(idx) and not logo_cache.has(games[idx].title):
				logo_load_queue.append(idx)
	
	_process_logo_queue()

func _input(event):
	var main_scene = get_tree().get_first_node_in_group("main_scene")
	var side_panel = main_scene.get_side_panel()
	
	if event is InputEventKey or event is InputEventMouseButton:
		if current_input_method != "keyboard":
			current_input_method = "keyboard"
			setup_keyboard_ui()
			if edit_mode:
				edit_gamepad_mode = false
				_clear_all_edit_focus()
	elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
		if current_input_method != "gamepad":
			current_input_method = "gamepad"
			setup_gamepad_ui()
			if edit_mode:
				edit_gamepad_mode = true
				_set_edit_focus(edit_current_focus_index)
		var device_id = event.device
		last_device_id = device_id
		update_controller_icon(device_id)

	if edit_mode and edit_gamepad_mode and not side_panel.side_panel_shown:
		if event.is_action_pressed("ui_up") or event.is_action_pressed("up_pad"):
			_move_edit_focus(-1)
			_trigger_vibration(1.0, 0.0, 0.1)
			get_viewport().set_input_as_handled()
			MusicPlayer.play_sfx("res://addons/fancy_editor_sounds/keyboard_sounds/button-sidebar-hover.wav", -8.0, 1.8)
			return
		
		elif event.is_action_pressed("ui_down") or event.is_action_pressed("down_pad"):
			_move_edit_focus(1)
			_trigger_vibration(1.0, 0.0, 0.1)
			get_viewport().set_input_as_handled()
			MusicPlayer.play_sfx("res://addons/fancy_editor_sounds/keyboard_sounds/button-sidebar-hover.wav", -8.0, 1.5)
			return
		
		elif event.is_action_pressed("ui_accept") or event.is_action_pressed("accept_pad"):
			_activate_edit_control()
			get_viewport().set_input_as_handled()
			MusicPlayer.play_sfx("res://addons/fancy_editor_sounds/keyboard_sounds/key-movement.mp3", -20.0, 1.5)
			return

	if event.is_action_pressed("ui_up"):
		if not edit_mode:
			_on_up_pressed()
			MusicPlayer.play_sfx("res://assets/sfx/Fantasy UI SFX/Skyward Hero/SkywardHero_UI (16).wav", -20.0, 2.0)
		_trigger_vibration(1.0, 0.0, 0.1)
	
	elif event.is_action_pressed("ui_down"):
		if not edit_mode:
			_on_down_pressed()
			MusicPlayer.play_sfx("res://assets/sfx/Fantasy UI SFX/Skyward Hero/SkywardHero_UI (16).wav", -25.0, 1.5)
		_trigger_vibration(1.0, 0.0, 0.1)
	
	elif event.is_action_pressed("ui_accept") or event.is_action_pressed("accept_pad"):
		if side_panel.side_panel_shown:
			side_panel.side_panel_change_scene()
			get_viewport().set_input_as_handled()
			MusicPlayer.play_sfx("res://assets/sfx/Fantasy UI SFX/Skyward Hero/SkywardHero_UI (5).wav", -25.0, 1.5)
			MusicPlayer.play_sfx("res://addons/fancy_editor_sounds/keyboard_sounds/key-movement.mp3", -20.0, 1.5)
			if not games.is_empty():
				await get_tree().create_timer(0.15).timeout
				game_info_node_canvas.visible = true
		elif not edit_mode and not editing:
			launch_game()
			MusicPlayer.play_sfx("res://assets/sfx/Fantasy UI SFX/Piano/Piano_Ui (7).wav", -15.0, 1.0)
	
	elif event.is_action_pressed("menu_key") or event.is_action_pressed("menu_pad"):
		if not side_panel.side_panel_shown:
			side_panel.show_panel()
			get_viewport().set_input_as_handled()
			game_info_node_canvas.visible = false
			MusicPlayer.play_sfx("res://assets/sfx/Fantasy UI SFX/Skyward Hero/SkywardHero_UI (5).wav", -25.0, 2.0)
		else:
			side_panel.hide_panel()
			get_viewport().set_input_as_handled()
			if not games.is_empty():
				await get_tree().create_timer(0.15).timeout
				game_info_node_canvas.visible = true
			MusicPlayer.play_sfx("res://assets/sfx/Fantasy UI SFX/Skyward Hero/SkywardHero_UI (5).wav", -25.0, 1.5)
	
	elif event.is_action_pressed("back_pad"):
		if side_panel.side_panel_shown:
			side_panel.hide_panel()
			get_viewport().set_input_as_handled()
			if not games.is_empty():
				await get_tree().create_timer(0.15).timeout
				game_info_node_canvas.visible = true
			MusicPlayer.play_sfx("res://assets/sfx/Fantasy UI SFX/Skyward Hero/SkywardHero_UI (5).wav", -25.0, 1.5)
	
	elif event.is_action_pressed("edit_key"):
		if edit_mode and not editing and not side_panel.side_panel_shown:
			exit_editmode()
			MusicPlayer.play_sfx("res://assets/sfx/Fantasy UI SFX/Skyward Hero/SkywardHero_UI (6).wav", -35.0, 0.5)
		elif not side_panel.side_panel_shown:
			if not games.is_empty() and not editing and not is_animation_in_progress():
				enter_editmode()
				MusicPlayer.play_sfx("res://assets/sfx/Fantasy UI SFX/Skyward Hero/SkywardHero_UI (6).wav", -25.0, 1.0)

func get_main_scene():
	var current = get_parent()
	while current:
		if current.has_method("load_scene"):
			return current
		current = current.get_parent()
	
	get_tree().change_scene_to_file("res://scenes/game_add.tscn")
	return null

func _trigger_vibration(weak_strength: float, strong_strength: float, duration_sec: float) -> void:
	if last_device_id >= 0 and current_input_method == "gamepad":
		Input.start_joy_vibration(last_device_id, weak_strength, strong_strength, duration_sec)

func move_viewport_container(x: int, time: float):
	var tween := create_tween()
	tween.tween_property(viewport_container, "position:x", x, time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished

func launch_game():
	if games.is_empty():
		return
	
	var game = games[current_index]
	var title = game.title
	
	if running_games.has(title):
		show_notification(tr("NTF_ALREADYSTARTED").format({"title": title}))
		return
	
	await get_tree().create_timer(1.0).timeout
	
	var exe_path = game.get("executable")
	if exe_path.is_empty():
		show_notification(tr("NTF_NOEXECSPECIFIED"))
		return
	
	if not FileAccess.file_exists(exe_path):
		show_notification(tr("NTF_NOEXECFOUND"))
		return
	
	var pid = _execute_game(exe_path)
	if pid > 0:
		_start_monitoring(title, pid)
		show_notification(tr("NTF_GAMESTARTED").format({"title": title}))
	else:
		show_notification(tr("NTF_STARTFAILED"))

func _execute_game(exe_path: String) -> int:
	var working_dir = exe_path.get_base_dir()
	var os_name = OS.get_name()
	
	match os_name:
		"Windows":
			return OS.create_process("cmd", ["/c", "cd /d \"" + working_dir + "\" && \"" + exe_path + "\""])
		
		"Linux":
			OS.execute("chmod", ["+x", exe_path])
			
			if exe_path.get_extension().to_lower() == "exe":
				if OS.execute("which", ["umu-run"]) == 0:
					return OS.create_process("umu-run", [exe_path])
				elif OS.execute("which", ["wine"]) == 0:
					return OS.create_process("wine", [exe_path])
				else:
					show_notification(tr("NTF_WINENOTFOUND"))
					return -1
			
			var lib_paths = []
			var potential_lib_dirs = ["lib", "libs", "../lib", "lib64", "lib32"]
			
			for dir in potential_lib_dirs:
				var full_path = working_dir + "/" + dir
				if DirAccess.dir_exists_absolute(full_path):
					lib_paths.append(full_path)
			
			lib_paths.append(working_dir)
			
			var ld_library_path = ":".join(lib_paths)
			var command = "cd \"" + working_dir + "\" && LD_LIBRARY_PATH=\"" + ld_library_path + ":$LD_LIBRARY_PATH\" ./" + exe_path.get_file()
			
			return OS.create_process("sh", ["-c", command])
		
		"macOS":
			if exe_path.get_extension().to_lower() == "app":
				return OS.create_process("open", [exe_path])
			else:
				OS.execute("chmod", ["+x", exe_path])
				return OS.create_process("sh", ["-c", "cd \"" + working_dir + "\" && ./" + exe_path.get_file()])
		_:	
			return -1

func _start_monitoring(title: String, pid: int):
	var game = games[current_index]
	var game_id = game.id
	
	running_games[title] = {"pid": pid}
	time_tracker.start_tracking(game_id, title, pid)
	update_display()
	_monitor_game(title)

func _monitor_game(title: String):
	var game_info = running_games[title]
	
	await get_tree().create_timer(3.0).timeout
	
	while running_games.has(title):
		if not OS.is_process_running(game_info.pid):
			_stop_game(title)
			break
		
		await get_tree().create_timer(5.0).timeout

func _stop_game(title: String):
	if running_games.has(title):
		var game_info = running_games[title]
		time_tracker.stop_tracking(game_info.pid)
		running_games.erase(title)
		update_display()
		show_notification(tr("NTF_STOPSUCCESS").format({"title": title}))
		game_state_label.visible = false

func show_notification(message: String):
	if notification:
		notification.show_notification(message, notification_icon)

func show_game_info(game_title: String):
	game_info_node_canvas.visible = true
	var game_time = time_tracker.get_game_time(game_title)
	if game_time:
		var game_time_format = game_time.get_formatted_total_time()
		var game_date_format = game_time.get_formatted_last_played()
		game_time_label.visible = true
		game_time_label.text = tr("CF_GT_TIME_TIP") + game_time_format
		game_date_label.text = tr("CF_GT_DATE_TIP") + game_date_format
	else:
		game_time_label.text = tr("CF_GT_NOTIME_TIP")
		game_date_label.text = tr("CF_GT_NODATE_TIP")

	load_logo_with_steamboxcover(game_title)

func show_fallback_text(game_title: String):
	game_fallback_label.text = game_title
	game_fallback_label.visible = true
	game_info_logo.visible = false

func load_logo_with_steamboxcover(game_title: String):
	if logo_cache.has(game_title):
		var cached = logo_cache[game_title]
		if cached.has("is_fallback") and cached.is_fallback:
			show_fallback_text(game_title)
		else:
			game_info_logo.texture = cached.texture
			game_info_logo.visible = true
			game_fallback_label.visible = false
		return

	var cached_logo = load_logo_from_cache(game_title)
	if cached_logo != null:
		logo_cache[game_title] = {"texture": cached_logo, "is_fallback": false}
		game_info_logo.texture = cached_logo
		game_info_logo.visible = true
		game_fallback_label.visible = false
		return

	show_fallback_text(game_title)
	request_logo_with_steamboxcover(game_title)

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

func request_logo_with_steamboxcover(game_title: String) -> void:
	if logo_cache.has(game_title) or failed_api_games.has(game_title):
		return

	var steamboxcover_path := get_steamboxcover_path()
	if not FileAccess.file_exists(steamboxcover_path):
		failed_api_games.append(game_title)
		logo_cache[game_title] = {"is_fallback": true}
		return

	var args := PackedStringArray([
		"--game", game_title,
		"--output_dir", ProjectSettings.globalize_path("user://covers/"),
		"--only_logo",
		"--only_steamgriddb",
		"-k", "ac6407f383cb7696689026c4576a7758"
	])

	var pid := OS.create_process(steamboxcover_path, args)

	if pid <= 0:
		failed_api_games.append(game_title)
		logo_cache[game_title] = {"is_fallback": true}
		return

	logo_processes[game_title] = {
		"pid": pid,
		"start_time": Time.get_ticks_msec()
	}

func save_logo_to_cache(game_title: String, texture: ImageTexture):
	if texture == null:
		return
	logo_cache[game_title] = {"texture": texture, "is_fallback": false}
	_save_logo_to_disk_async_once(game_title, texture)

func _save_logo_to_disk_async_once(game_title: String, texture: ImageTexture):
	if texture == null:
		return

	var safe_title = sanitize_filename(game_title)
	var file_path = "user://covers/" + safe_title + "_logo.png"

	if FileAccess.file_exists(file_path):
		return

	var covers_dir = "user://covers/"
	if not DirAccess.dir_exists_absolute(covers_dir):
		DirAccess.open("user://").make_dir_recursive("covers")

	var image = texture.get_image()
	if image == null:
		return

	await get_tree().process_frame
	var err = image.save_png(file_path)

func load_logo_from_cache(game_title: String) -> ImageTexture:
	var covers_dir = "user://covers/"
	var dir = DirAccess.open(covers_dir)
	if not dir:
		return null
	
	var possible_names = get_possible_logo_filenames(game_title)
	
	for filename in possible_names:
		var file_path = covers_dir + filename
		if FileAccess.file_exists(file_path):
			var image = Image.new()
			var error = image.load(file_path)
			if error == OK:
				var texture = ImageTexture.new()
				texture.set_image(image)
				return texture
	
	return null

func get_possible_logo_filenames(game_title: String) -> PackedStringArray:
	var possible_names = PackedStringArray()
	
	var variant1 = game_title
	var special_chars := ["<", ">", ":", "\"", "/", "\\", "|", "?", "*", ";", "!", ".", "'", "`", "~"]
	for c in special_chars:
		variant1 = variant1.replace(c, " ")
	while variant1.contains("  "):
		variant1 = variant1.replace("  ", " ")
	variant1 = variant1.strip_edges()
	while variant1.ends_with("."):
		variant1 = variant1.substr(0, variant1.length() - 1)
	if variant1.length() > 200:
		variant1 = variant1.substr(0, 200)
	variant1 = variant1.replace(" ", "")
	possible_names.append(variant1 + "_logo.png")
	
	var variant2 = game_title
	for c in special_chars:
		variant2 = variant2.replace(c, " ")
	while variant2.contains("  "):
		variant2 = variant2.replace("  ", " ")
	variant2 = variant2.strip_edges()
	while variant2.ends_with("."):
		variant2 = variant2.substr(0, variant2.length() - 1)
	if variant2.length() > 200:
		variant2 = variant2.substr(0, 200)
	possible_names.append(variant2 + "_logo.png")
	
	var variant3 = game_title
	for c in special_chars:
		variant3 = variant3.replace(c, "")
	variant3 = variant3.strip_edges()
	while variant3.ends_with("."):
		variant3 = variant3.substr(0, variant3.length() - 1)
	if variant3.length() > 200:
		variant3 = variant3.substr(0, 200)
	possible_names.append(variant3 + "_logo.png")
	
	var unique_names = []
	for name in possible_names:
		if not unique_names.has(name):
			unique_names.append(name)
	
	return PackedStringArray(unique_names)

func sanitize_filename(filename: String) -> String:
	var safe := filename
	var special_chars := ["<", ">", ":", "\"", "/", "\\", "|", "?", "*", ";", "!", ".", "'", "`", "~"]
	for c in special_chars:
		safe = safe.replace(c, " ")
	while safe.contains("  "):
		safe = safe.replace("  ", " ")
	safe = safe.strip_edges()
	while safe.ends_with("."):
		safe = safe.substr(0, safe.length() - 1)
	if safe.length() > 200:
		safe = safe.substr(0, 200)
	return safe.replace(" ", "")

func _file_dialog():
	file_dialog.clear_filters()
	if current_button == "executable":
		if OS.get_name() == "Windows":
			file_dialog.add_filter("*.exe", "Windows Executable")
			file_dialog.add_filter("*.bat", "Batch Files")
			file_dialog.add_filter("*.cmd", "Command Files")
		elif OS.get_name() == "Linux":
			file_dialog.add_filter("*.sh", "Shell Scripts")
			file_dialog.add_filter("*.exe", "Windows Executable (Wine)")
			file_dialog.add_filter("*.x86_64", "x86 64 Bit Executable")
			file_dialog.add_filter("*", "All Files")
		elif OS.get_name() == "macOS":
			file_dialog.add_filter("*.app", "macOS Applications")
			file_dialog.add_filter("*.sh", "Shell Scripts")
			file_dialog.add_filter("*", "All Files")
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
		"executable": editgame_executable_icon.texture = load(icon_path)
		"front": editgame_front_icon.texture = load(icon_path)
		"back": editgame_back_icon.texture = load(icon_path)
		"spine": editgame_spine_icon.texture = load(icon_path)
		
	if not FileAccess.file_exists(path):
		notification.show_notification(tr("NTF_FILENOTFOUND"), notification_icon)
		return
	
	updated_game_data[current_button] = path

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
	
func _on_delete_pressed() -> void:
	var game = games[current_index]
	var title = game.title
	var game_id = game_manager.find_game_id_by_title(title)
	
	delete_mode = true
	
	game_manager.delete_game_by_id(game_id)
	
	exit_editmode()

func enter_editmode():
	var game = games[current_index]
	var title = game.title
	var cover = active_covers.get(current_index)
	edit_mode = true
	
	editgame_line.visible = true
	editgame_line.text = title
	editgame_label.text = tr("CF_GE_STOP")
	editgame_executable.visible = true
	editgame_front.visible = true
	editgame_back.visible = true
	editgame_spine.visible = true
	editgame_delete.visible = true
	
	game_info_logo.visible = false
	game_fallback_label.visible = false
	game_time_label.visible = false
	game_date_label.visible = false
	
	_init_edit_focusable_controls()
	_setup_edit_control_signals()
	
	if current_input_method == "gamepad":
		edit_gamepad_mode = true
		_set_edit_focus(edit_current_focus_index)
	
	if cover:
		cover.start_fast_spin_move_animation()
	move_viewport_container(500, 0.4)
	game_info_node.set_notify_transform(true)
	animationplayer.play("GameEdit")
	game_info_node.queue_redraw()
	await get_tree().create_timer(0.3).timeout

func exit_editmode():
	if editgame_line.text == "":
		notification.show_notification(tr("NTF_TYPEGAMENAME"), notification_icon)
		return
	
	var game = games[current_index]
	var title = game.title
	var cover = active_covers.get(current_index)
	var game_id = game_manager.find_game_id_by_title(title)
	var plus_icon = load("res://assets/kenney_input-prompts_1.4/Nintendo Switch 2/Default/switch_button_plus.png")
	
	var new_title = editgame_line.text
	
	updated_game_data["title"] = new_title 
	
	if not delete_mode:
		game_manager.update_game_data_by_id(game_id, updated_game_data)
		notification.show_notification(tr("NTF_GAMEUPDATESUCCESS"), notification_icon)
	else:
		notification.show_notification(tr("NTF_GAMEDELETESUCCESS"), notification_icon)
	
	updated_game_data = {}
	
	game_info_logo.visible = true
	game_fallback_label.visible = true
	game_time_label.visible = true
	game_date_label.visible = true
	
	editgame_line.visible = false
	editgame_label.text = tr("CF_GE_EDIT")
	editgame_executable.visible = false
	editgame_front.visible = false
	editgame_back.visible = false
	editgame_spine.visible = false
	editgame_delete.visible = false
	
	editgame_executable_icon.texture = plus_icon
	editgame_front_icon.texture = plus_icon
	editgame_back_icon.texture = plus_icon
	editgame_spine_icon.texture = plus_icon
	
	show_game_info(title)

	if cover:
		editing = true
		cover.stop_fast_spin_move_animation()
	move_viewport_container(-500, 0.4)
	animationplayer.play("GameEdit_Back")
	await get_tree().create_timer(0.3).timeout
	
	await get_tree().create_timer(0.4).timeout
	refresh_games()
	
	if games.is_empty():
		game_info_node_canvas.visible = false
		
	edit_mode = false
	
	_clear_all_edit_focus()
	
	var t := get_tree().create_timer(edit_cooldown)
	t.timeout.connect(_reset_edit)

func _reset_edit():
	editing = false
	
func _exit_tree():
	logo_cache.clear()
	failed_api_games.clear()
	material_cache.clear()

func refresh_games():
	# Очищаем кэш материалов при обновлении
	material_cache.clear()
	
	load_games()
	if current_index >= games.size():
		current_index = max(0, games.size() - 1)
	
	# Возвращаем все обложки в пул
	for cover in active_covers.values():
		return_cover_to_pool(cover)
	active_covers.clear()
	
	await get_tree().process_frame
	update_display()

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			set_process_input(false)
		NOTIFICATION_WM_WINDOW_FOCUS_IN:
			set_process_input(true)
