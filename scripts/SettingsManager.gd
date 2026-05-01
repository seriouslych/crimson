extends Node

const CONFIG_PATH = "user://settings.json"

# Настройки по умолчанию
var default_settings = {
	"music_enabled": false,
	"music_volume": -26.4443858946784,
	"language": "en"
}

var settings = {}

func _ready():
	load_settings()

# Загрузка настроек из файла
func load_settings() -> void:
	if not FileAccess.file_exists(CONFIG_PATH):
		print("Файл настроек не найден, создаём новый с параметрами по умолчанию")
		settings = default_settings.duplicate(true)
		save_settings()
		return
	
	var file = FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		print("Ошибка открытия файла настроек: ", FileAccess.get_open_error())
		settings = default_settings.duplicate(true)
		return
	
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var parse_result = json.parse(json_string)
	
	if parse_result != OK:
		print("Ошибка парсинга JSON: ", json.get_error_message())
		settings = default_settings.duplicate(true)
		return
	
	settings = json.data
	
	# Добавляем отсутствующие настройки из дефолтных
	for key in default_settings:
		if not settings.has(key):
			settings[key] = default_settings[key]
	
	print("Настройки загружены: ", settings)

# Сохранение настроек в файл
func save_settings() -> void:
	var file = FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if file == null:
		print("Ошибка создания файла настроек: ", FileAccess.get_open_error())
		return
	
	var json_string = JSON.stringify(settings, "\t")
	file.store_string(json_string)
	file.close()
	print("Настройки сохранены: ", settings)

# Получить значение настройки
func get_setting(key: String, default_value = null):
	if settings.has(key):
		return settings[key]
	return default_value

# Установить значение настройки и сохранить
func set_setting(key: String, value) -> void:
	settings[key] = value
	save_settings()

# Сброс настроек к значениям по умолчанию
func reset_to_defaults() -> void:
	settings = default_settings.duplicate(true)
	save_settings()
	print("Настройки сброшены к значениям по умолчанию")
