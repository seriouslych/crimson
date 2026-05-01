class_name VinylCover3D
extends Node3D

# ==============================
# ДАННЫЕ АЛЬБОМА
# ==============================
class AlbumData:
	var id: String = ""
	var title: String = ""
	var artist: String = ""
	var cover: String = ""   # Путь к обложке
	var tracks: Array = []

	func _init(data: Dictionary = {}):
		id = data.get("id", "")
		title = data.get("title", "")
		artist = data.get("artist", "")
		cover = data.get("cover", "")
		tracks = data.get("tracks", [])


var album_data: AlbumData

@export var model_scale_multiplier: float = 1.0

# Состояния (оставлены, но без визуальных эффектов)
@export var is_selected: bool = false
@export var is_hovered: bool = false

# ==============================
# ТРАНСФОРМЫ
# ==============================
var target_position: Vector3
var target_rotation: Vector3
var target_scale: Vector3
var original_scale: Vector3

# ==============================
# НОДЫ И МЕШИ
# ==============================
var model_node: Node3D
var mesh_circle: MeshInstance3D      # vinyl_case_Circle
var mesh_plane: MeshInstance3D       # vinyl_case_Plane

# ==============================
# МАТЕРИАЛЫ
# ==============================
var disc_material: StandardMaterial3D
var cover_material: StandardMaterial3D

# ==============================
# GRID
# ==============================
var grid_index: int = 0


# ==============================
# READY
# ==============================
func _ready():
	original_scale = Vector3.ONE * model_scale_multiplier
	scale = original_scale

	target_position = position
	target_rotation = rotation_degrees
	target_scale = original_scale

	load_model()


# ==============================
# ЗАГРУЗКА МОДЕЛИ
# ==============================
func load_model():
	var model_scene: PackedScene = load("res://models/vinyl_case.glb")
	if not model_scene:
		push_error("VinylCover3D: не удалось загрузить модель")
		return

	model_node = model_scene.instantiate()
	model_node.scale = Vector3.ONE * model_scale_multiplier
	model_node.rotation_degrees = Vector3(0, 180, 0)
	add_child(model_node)

	find_meshes()
	setup_materials()


# ==============================
# ПОИСК МЕШЕЙ
# ==============================
func find_meshes():
	mesh_circle = model_node.find_child("vinyl_case_Circle", true, false) as MeshInstance3D
	mesh_plane = model_node.find_child("vinyl_case_Plane", true, false) as MeshInstance3D

	if not mesh_circle:
		push_warning("VinylCover3D: vinyl_case_Circle не найден")
	if not mesh_plane:
		push_warning("VinylCover3D: vinyl_case_Plane не найден")


# ==============================
# МАТЕРИАЛЫ
# ==============================
func setup_materials():
	# Материал диска
	disc_material = StandardMaterial3D.new()
	disc_material.albedo_color = Color.BLACK
	disc_material.metallic = 0.2
	disc_material.roughness = 0.4

	# Материал обложки
	cover_material = StandardMaterial3D.new()
	cover_material.albedo_color = Color.WHITE
	cover_material.metallic = 0.05
	cover_material.roughness = 0.7
	cover_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	if album_data:
		load_cover_texture()

	apply_materials()


func apply_materials():
	if mesh_circle and mesh_circle.mesh:
		mesh_circle.set_surface_override_material(0, disc_material)

	if mesh_plane and mesh_plane.mesh:
		mesh_plane.set_surface_override_material(0, cover_material)


# ==============================
# АЛЬБОМ / ТЕКСТУРА
# ==============================
func set_album_data(data: AlbumData):
	album_data = data
	load_cover_texture()


func load_cover_texture():
	if not album_data or not mesh_plane:
		return

	if album_data.cover != "" and FileAccess.file_exists(album_data.cover):
		var texture := load_texture_from_path(album_data.cover)
		if texture:
			cover_material.albedo_texture = texture
			cover_material.albedo_color = Color.WHITE

	apply_materials()


func load_texture_from_path(path: String) -> Texture2D:
	var image := Image.new()
	if image.load(path) != OK:
		return null

	var texture := ImageTexture.new()
	texture.set_image(image)
	return texture


# ==============================
# СОСТОЯНИЯ (БЕЗ ЭФФЕКТОВ)
# ==============================
func set_selected(selected: bool):
	is_selected = selected


func set_hovered(hovered: bool):
	is_hovered = hovered


# ==============================
# GRID / TRANSFORM
# ==============================
func set_grid_index(index: int):
	grid_index = index


func set_target_transform(pos: Vector3, rot: Vector3, scl: Vector3):
	target_position = pos
	target_rotation = rot
	target_scale = scl


# ==============================
# UPDATE
# ==============================
func _process(delta):
	position = position.lerp(target_position, delta * 10.0)
	rotation_degrees = rotation_degrees.lerp(target_rotation, delta * 10.0)
	scale = scale.lerp(target_scale, delta * 10.0)
