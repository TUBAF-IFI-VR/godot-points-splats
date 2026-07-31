extends Node3D


@onready var octree: Octree = $Octree
@onready var file_dialog: FileDialog = $Panel/FileDialog

func _ready() -> void:
	$Panel/VBoxContainer/HBoxPointSize/HSlider.value = $Octree.point_size
	$Panel/VBoxContainer/HBoxVisibilityRange/HSlider.value = $Octree.initial_visibility_range
	$Panel/VBoxContainer/HBoxProjectionThreshold/HSlider.value = $Octree.projection_size_threshold
	$MenuPanel/MenuHBoxContainer/OpenFileButton.pressed.connect(_on_file_button_click)
	$MenuPanel/MenuHBoxContainer/SlidersButton.pressed.connect(_on_sliders_button_click)
	file_dialog.file_selected.connect(_on_file_selected)
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM

	file_dialog.clear_filters()
	file_dialog.add_filter("*.las", "LAS point cloud")
	file_dialog.add_filter("cloud.js", "Potree point cloud metadata")
	
func _on_pointsize_value_changed(value: float) -> void:
	$Panel/VBoxContainer/HBoxPointSize/Label.text = str(value)+" mm"
	$Octree.point_size = value
	
func _on_visibility_range_value_changed(value: float) -> void:
	$Panel/VBoxContainer/HBoxVisibilityRange/Label.text = str(value)
	$Octree.initial_visibility_range = value

func _projection_size_threshold_value_changed(value: float) -> void:
	$Panel/VBoxContainer/HBoxProjectionThreshold/Label.text = str(value) +" mm"
	$Octree.projection_size_threshold = value

func _on_file_button_click() -> void:
	$Panel/FileDialog.popup_centered()

func _on_file_selected(path: String) -> void:
	var extension = path.get_extension().to_lower()

	if extension == "las":
		octree.data_type = OctreeLoader.DataTypes.LAS
	elif extension == "js":
		if path.get_file() != "cloud.js":
			push_error(" File should be a cloud.js file.")
			return
			
		octree.data_type = OctreeLoader.DataTypes.Potree
	else:
		push_error("Unsupported file format.")
		return

	octree.octree_path = path

func _on_sliders_button_click() -> void:
	$Panel.visible = !$Panel.visible
