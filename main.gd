extends Node3D

func _ready() -> void:
	$Panel/VBoxContainer/HBoxPointSize/HSlider.value = $Octree.point_size

func _on_pointsize_value_changed(value: float) -> void:
	$Panel/VBoxContainer/HBoxPointSize/Label.text = str(value)+" mm"
	$Octree.point_size = value
