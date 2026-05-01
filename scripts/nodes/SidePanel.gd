class_name SidePanel
extends Node

var side_panel_moving = false
var side_panel_shown = false
var side_panel_buttons: Array[Button] = []
var side_panel_current_index: int = 0

# Загружаем сцену side_panel
var side_panel_scene = preload("res://scenes/side_panel.tscn")
var side_panel_instance = side_panel_scene.instantiate()

@onready var side_panel = side_panel_instance
@onready var dark_node = side_panel_instance.get_node("Dark")
@onready var side_panel_animation = side_panel_instance.get_node("AnimationPlayer")
@onready var side_panel_container = side_panel_instance.get_node("CanvasLayer/VBoxContainer")
@onready var side_panel_button_hover = side_panel_instance.get_node("CanvasLayer/VBoxContainer/Home/Hover")
@onready var home_button = side_panel_instance.get_node("CanvasLayer/VBoxContainer/Home")
@onready var mplayer_button = side_panel_instance.get_node("CanvasLayer/VBoxContainer/MusicPlayer")
@onready var gameadd_button = side_panel_instance.get_node("CanvasLayer/VBoxContainer/GameAdd")
@onready var settings_button = side_panel_instance.get_node("CanvasLayer/VBoxContainer/Settings")
@onready var exit_button = side_panel_instance.get_node("CanvasLayer/VBoxContainer/Exit")

func _ready():
	side_panel_init()
	home_button.pressed.connect(func(): side_panel_change_scene(home_button))
	mplayer_button.pressed.connect(func(): side_panel_change_scene(mplayer_button))
	gameadd_button.pressed.connect(func(): side_panel_change_scene(gameadd_button))
	settings_button.pressed.connect(func(): side_panel_change_scene(settings_button))
	exit_button.pressed.connect(func(): side_panel_change_scene(exit_button))
	
	home_button.visible = false
	mplayer_button.visible = false
	gameadd_button.visible = false
	settings_button.visible = false
	exit_button.visible = false

func _input(event):
	# Обрабатываем ввод только когда панель открыта
	if not side_panel_shown or side_panel_moving:
		return
	
	# Навигация по кнопкам
	if event.is_action_pressed("ui_up"):
		side_panel_move_focus(-1)
		get_viewport().set_input_as_handled()
		MusicPlayer.play_sfx("res://addons/fancy_editor_sounds/keyboard_sounds/button-sidebar-hover.wav", -8.0, 1.8)
	elif event.is_action_pressed("ui_down"):
		side_panel_move_focus(1)
		get_viewport().set_input_as_handled()
		MusicPlayer.play_sfx("res://addons/fancy_editor_sounds/keyboard_sounds/button-sidebar-hover.wav", -8.0, 1.5)
	
	# Подтверждение выбора
	#elif event.is_action_pressed("ui_accept"):
		#side_panel_change_scene()
		#get_viewport().set_input_as_handled()
	
	# Закрытие панели
	#elif event.is_action_pressed("ui_cancel"):
		#hide_panel()
		#get_viewport().set_input_as_handled()

func show_panel():
	if side_panel_moving or side_panel_shown or side_panel_buttons.is_empty():
		return
	
	MusicPlayer.transition_to_muffled(0.3, 450.0)
	
	#var main_scene = get_tree().get_first_node_in_group("main_scene")
	#var current_scene = main_scene.get_current_scene()
	
	dark_node.visible = true
	dark_node.mouse_filter = Control.MOUSE_FILTER_STOP
	side_panel.visible = true
	
	if side_panel_animation.has_animation("show_panel"):
		side_panel_animation.play("show_panel")
		side_panel_moving = true
		await side_panel_animation.animation_finished
		side_panel_moving = false
		side_panel_shown = true
		
		home_button.visible = true
		mplayer_button.visible = true
		gameadd_button.visible = true
		settings_button.visible = true
		exit_button.visible = true
		
		## Определяем индекс текущей сцены
		#if current_scene.name == "CoverFlow":
			#side_panel_current_index = 0
		#elif current_scene.name == "GameAdd":
			#side_panel_current_index = 1
		#elif current_scene.name == "Settings":
			#side_panel_current_index = 2
		
		# Устанавливаем фокус на текущую кнопку
		_set_button_focus(side_panel_current_index)
		

func hide_panel():
	if side_panel_moving or not side_panel_shown:
		return
	
	MusicPlayer.transition_from_muffled(1.0) 
	
	# Очищаем фокусы перед скрытием панели
	_clear_all_focus()
		
	if side_panel_animation.has_animation("hide_panel"):
		side_panel_animation.play("hide_panel")
		side_panel_moving = true
		home_button.visible = false
		mplayer_button.visible = false
		gameadd_button.visible = false
		settings_button.visible = false
		exit_button.visible = false
		await side_panel_animation.animation_finished
		side_panel_moving = false
		dark_node.visible = false
		dark_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		side_panel.visible = false
		side_panel_shown = false
		side_panel_current_index = 0

func side_panel_init():
	if side_panel_instance:
		side_panel.position = Vector2(-365, 136.5)
		
	side_panel_buttons.clear()
	
	var vbox_container = side_panel_container
	if not vbox_container:
		print("Ошибка: VBoxContainer не найден")
		return
	
	# Собираем кнопки в правильном порядке
	var home_btn = vbox_container.get_node_or_null("Home")
	var mplayer_btn = vbox_container.get_node_or_null("MusicPlayer")
	var gameadd_btn = vbox_container.get_node_or_null("GameAdd") 
	var settings_btn = vbox_container.get_node_or_null("Settings")
	var exit_btn = vbox_container.get_node_or_null("Exit")
	
	if home_btn and home_btn is Button:
		side_panel_buttons.append(home_btn)
		home_btn.focus_mode = Control.FOCUS_NONE
		_setup_button_signals(home_btn)
		
	if mplayer_btn and mplayer_btn is Button:
		side_panel_buttons.append(mplayer_btn)
		mplayer_btn.focus_mode = Control.FOCUS_NONE
		_setup_button_signals(mplayer_btn)
		
	if gameadd_btn and gameadd_btn is Button:
		side_panel_buttons.append(gameadd_btn)
		gameadd_btn.focus_mode = Control.FOCUS_NONE
		_setup_button_signals(gameadd_btn)
		
	if settings_btn and settings_btn is Button:
		side_panel_buttons.append(settings_btn)
		settings_btn.focus_mode = Control.FOCUS_NONE
		_setup_button_signals(settings_btn)
		
	if exit_btn and exit_btn is Button:
		side_panel_buttons.append(exit_btn)
		exit_btn.focus_mode = Control.FOCUS_NONE
		_setup_button_signals(exit_btn)
	
	side_panel_current_index = 0

# Настройка сигналов для визуальной обратной связи
func _setup_button_signals(button: Button):
	button.focus_entered.connect(func(): _on_button_focus_entered(button))
	button.focus_exited.connect(func(): _on_button_focus_exited(button))
	button.mouse_entered.connect(func(): _on_button_mouse_entered(button))

# Визуальная обратная связь при получении фокуса
func _on_button_focus_entered(button: Button):
	# Обновляем текущий индекс при фокусе
	for i in side_panel_buttons.size():
		if side_panel_buttons[i] == button:
			side_panel_current_index = i
			break
	
	# Добавьте свою логику подсветки (например, изменение modulate)
	button.modulate = Color(1.2, 1.2, 1.2)

func _on_button_focus_exited(button: Button):
	button.modulate = Color(1, 1, 1)

# Синхронизация с мышью
func _on_button_mouse_entered(button: Button):
	if side_panel_shown and not side_panel_moving:
		for i in side_panel_buttons.size():
			if side_panel_buttons[i] == button:
				side_panel_current_index = i
				_set_button_focus(i)
				break

func side_panel_move_focus(direction: int):
	if side_panel_buttons.is_empty():
		return
	
	# Очищаем текущий фокус
	_clear_all_focus()
	
	# Вычисляем новый индекс с циклической навигацией
	side_panel_current_index += direction
	
	if side_panel_current_index < 0:
		side_panel_current_index = side_panel_buttons.size() - 1
	elif side_panel_current_index >= side_panel_buttons.size():
		side_panel_current_index = 0
	
	# Устанавливаем фокус на новую кнопку
	_set_button_focus(side_panel_current_index)

# Устанавливает фокус на кнопку по индексу
func _set_button_focus(index: int):
	if index < 0 or index >= side_panel_buttons.size():
		return
	
	side_panel_buttons[index].focus_mode = Control.FOCUS_ALL
	side_panel_buttons[index].grab_focus()

# Очищает фокусы со всех кнопок
func _clear_all_focus():
	for button in side_panel_buttons:
		button.focus_mode = Control.FOCUS_NONE

func side_panel_change_scene(button: Button = null):
	var button_name := ""
	var main_scene = get_tree().get_first_node_in_group("main_scene")
	var current_scene = main_scene.get_current_scene()

	if button != null:
		# Если пришла кнопка с UI (мышь), берём её имя
		button_name = button.name
	else:
		# Иначе берём текущую по индексу (геймпад/клава)
		if side_panel_current_index < side_panel_buttons.size():
			button_name = side_panel_buttons[side_panel_current_index].name
		else:
			return

	match button_name:
		"Home":
			if current_scene.name != "CoverFlow":
				await hide_panel()
				main_scene.load_scene("res://scenes/CoverFlow.tscn")
			else:
				hide_panel()
		"MusicPlayer":
			if current_scene.name != "VinylGrid":
				await hide_panel()
				main_scene.load_scene("res://scenes/VinylGrid.tscn")
			else:
				hide_panel()
		"GameAdd":
			if current_scene.name != "GameAdd":
				await hide_panel()
				main_scene.load_scene("res://scenes/GameAdd.tscn")
			else:
				hide_panel()
		"Settings":
			if current_scene.name != "Settings":
				await hide_panel()
				main_scene.load_scene("res://scenes/Settings.tscn")
			else:
				hide_panel()
		"Exit":
			get_tree().quit()
