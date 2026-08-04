extends Node3D

@onready var octree: Octree = $Octree
@onready var file_dialog: FileDialog = $Panel/FileDialog
@onready var label_points: Label = $Panel/VBoxContainer/LabelPoints
@onready var label_loaded_points: Label = $Panel/VBoxContainer/LabelLoadedPoints


func _ready() -> void:
	$Panel/VBoxContainer/HBoxPointSize/HSlider.value = octree.point_size
	$Panel/VBoxContainer/HBoxPointSize/Label.text = str(octree.point_size) + " mm"
	$Panel/VBoxContainer/HBoxVisibilityRange/HSlider.value = octree.initial_visibility_range
	$Panel/VBoxContainer/HBoxVisibilityRange/Label.text = str(octree.initial_visibility_range) + " m"
	$Panel/VBoxContainer/HBoxProjectionThreshold/HSlider.value = octree.projection_size_threshold * 100.0
	$Panel/VBoxContainer/HBoxProjectionThreshold/Label.text = str(
		octree.projection_size_threshold * 100.0
	) + " %"
	$Panel/VBoxContainer/CheckAdaptiveSize.button_pressed = octree.adaptive_point_size
	$Panel/VBoxContainer/CheckShowDebug.button_pressed = octree.show_debug_objects
	$MenuPanel/MenuHBoxContainer/OpenFileButton.pressed.connect(_on_file_button_click)
	$MenuPanel/MenuHBoxContainer/SlidersButton.pressed.connect(_on_sliders_button_click)
	file_dialog.file_selected.connect(_on_file_selected)
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM

	file_dialog.clear_filters()
	file_dialog.add_filter("*.las", "LAS point cloud")
	file_dialog.add_filter("cloud.js", "Potree point cloud metadata")


func _process(_delta: float) -> void:
	label_points.text = "Total points: " + str(octree.point_count)
	label_loaded_points.text = "Loaded points: " + str(octree.loaded_point_count)


func _on_pointsize_value_changed(value: float) -> void:
	$Panel/VBoxContainer/HBoxPointSize/Label.text = str(value) + " mm"
	octree.point_size = value


func _on_visibility_range_value_changed(value: float) -> void:
	$Panel/VBoxContainer/HBoxVisibilityRange/Label.text = str(value) + "m"
	octree.initial_visibility_range = value


func _projection_size_threshold_value_changed(value: float) -> void:
	$Panel/VBoxContainer/HBoxProjectionThreshold/Label.text = str(value) + " %"
	octree.projection_size_threshold = value * 0.01


func _adaptive_point_size_changed(value: bool) -> void:
	octree.adaptive_point_size = value


func _show_debug_objects_changed(value: bool) -> void:
	$gizmo.visible = value
	octree.show_debug_objects = value


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
