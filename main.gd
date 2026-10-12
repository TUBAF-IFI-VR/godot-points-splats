extends Node3D
## Add parameter controls for a main octree dataset


## Store last detected number of total points
var last_total_points: int = 0
var last_loaded_points: int = 0

## The main octree node influenced by the UI settings
@export var octree: Octree = null

## A predefined file dialog to use for dataset loading
@onready var file_dialog: FileDialog = $FileDialog

## Direct access to the label to display the total number of points
@onready var label_points: Label = $SettingsPanel/VBoxContainer/LabelPoints

## Direct access to the label to display the actually loaded number of points
@onready var label_loaded_points: Label = $SettingsPanel/VBoxContainer/LabelLoadedPoints


## Prepare UI on application start
func _ready() -> void:
	# Initialize UI controls with values currently applied to the octree
	$SettingsPanel/VBoxContainer/HBoxPointSize/HSlider.value = octree.point_size
	$SettingsPanel/VBoxContainer/HBoxPointSize/Label.text = str(octree.point_size) + " mm"
	$SettingsPanel/VBoxContainer/HBoxVisibilityRange/HSlider.value = octree.initial_visibility_range
	$SettingsPanel/VBoxContainer/HBoxVisibilityRange/Label.text = str(octree.initial_visibility_range) + " m"
	$SettingsPanel/VBoxContainer/HBoxProjectionThreshold/HSlider.value = octree.projection_size_threshold * 100.0
	$SettingsPanel/VBoxContainer/HBoxProjectionThreshold/Label.text = str(
		octree.projection_size_threshold * 100.0
	) + " %"
	$SettingsPanel/VBoxContainer/CheckAdaptiveSize.button_pressed = octree.adaptive_point_size
	$SettingsPanel/VBoxContainer/CheckShowDebug.button_pressed = octree.show_debug_objects

	# Add signal connections
	$SettingsPanel/VBoxContainer/HBoxFlip/CheckFlipX.toggled.connect(_on_orientation_changed)
	$SettingsPanel/VBoxContainer/HBoxFlip/OptionUpAxis.item_selected.connect(_on_orientation_changed)
	$SettingsPanel/VBoxContainer/HBoxPointSize/HSlider.value_changed.connect(_on_pointsize_value_changed)
	$SettingsPanel/VBoxContainer/HBoxVisibilityRange/HSlider.value_changed.connect(_on_visibility_range_value_changed)
	$SettingsPanel/VBoxContainer/HBoxProjectionThreshold/HSlider.value_changed.connect(_projection_size_threshold_value_changed)
	$SettingsPanel/VBoxContainer/CheckAdaptiveSize.toggled.connect(_adaptive_point_size_changed)
	$SettingsPanel/VBoxContainer/CheckShowDebug.toggled.connect(_show_debug_objects_changed)
	$ToolBar/MenuHBoxContainer/OpenFileButton.pressed.connect(_on_file_button_click)
	$ToolBar/MenuHBoxContainer/SlidersButton.pressed.connect(_on_settings_toggled)
	file_dialog.file_selected.connect(_on_file_selected)

	# Prepare file dialog
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM

	file_dialog.clear_filters()
	file_dialog.add_filter("*.las", "LAS point cloud")
	file_dialog.add_filter("*.ply", "PLY points, mesh or 3dgs")
	file_dialog.add_filter("cloud.js, metadata.json", "Potree point cloud metadata")

## Check for updated point counts to display
func _process(_delta: float) -> void:
	if octree.point_count != last_total_points:
		label_points.text = "Total points: " + str(octree.point_count)
		last_total_points = octree.point_count
	if octree.loaded_point_count != last_loaded_points:
		label_loaded_points.text = "Loaded points: " + str(octree.loaded_point_count)
		last_loaded_points = octree.loaded_point_count


## Show and hide the whole panel
func _on_settings_toggled() -> void:
	$SettingsPanel.visible = !$SettingsPanel.visible


## Flip or rotate the point cloud if necessary to orient it correctly
func _on_orientation_changed(_index:int = -1) -> void:
	var flip_x = $SettingsPanel/VBoxContainer/HBoxFlip/CheckFlipX.button_pressed
	$Octree.scale.x = -1 if flip_x else 1
	
	match $SettingsPanel/VBoxContainer/HBoxFlip/OptionUpAxis.selected:
		# Y up
		0:
			$Octree.scale.y = 1
			$Octree.root.rotation.x = 0
		# -Y up
		1:
			$Octree.scale.y = -1
			$Octree.root.rotation.x = 0
		# Z up
		2:
			$Octree.scale.y = 1
			$Octree.root.rotation.x = PI*0.5
		# -Z up
		3:
			$Octree.scale.y = -1
			$Octree.root.rotation.x = PI*0.5


## Adjust the default point size
func _on_pointsize_value_changed(value: float) -> void:
	$SettingsPanel/VBoxContainer/HBoxPointSize/Label.text = str(value) + " mm"
	octree.point_size = value


## Adjust the range for deeper nodes to become visible
func _on_visibility_range_value_changed(value: float) -> void:
	$SettingsPanel/VBoxContainer/HBoxVisibilityRange/Label.text = str(value) + "m"
	octree.initial_visibility_range = value


## Adjust the covered screen size threshold to trigger loading the next level
func _projection_size_threshold_value_changed(value: float) -> void:
	$SettingsPanel/VBoxContainer/HBoxProjectionThreshold/Label.text = str(value) + " %"
	octree.projection_size_threshold = value * 0.01


## Enable and disable adaptive scaling of points with distance
func _adaptive_point_size_changed(value: bool) -> void:
	octree.adaptive_point_size = value


## Show additional visual elements if requested
func _show_debug_objects_changed(value: bool) -> void:
	$WorldOrigin.visible = value
	octree.show_debug_objects = value


## Open the file loading dialog
func _on_file_button_click() -> void:
	$FileDialog.popup_centered()


## Load a new dataset if the dialog has been accepted
func _on_file_selected(path: String) -> void:
	var extension = path.get_extension().to_lower()

	# Detect the correct loader to use by file extension
	if extension == "las":
		octree.data_type = OctreeLoader.DataTypes.LAS
	elif extension == "ply":
		octree.data_type = OctreeLoader.DataTypes.PLY
	elif extension in ["js", "json"]:
		if path.get_file() != "cloud.js" and path.get_file() != "metadata.json":
			push_error(" File should be a 'cloud.js' or 'metadata.json' file.")
			return

		octree.data_type = OctreeLoader.DataTypes.Potree
	else:
		push_error("Unsupported file format.")
		return

	octree.octree_path = path
