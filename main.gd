extends Node3D

func _ready() -> void:
	$Panel/VBoxContainer/HBoxPointSize/HSlider.value = $Octree.point_size
	$Panel/VBoxContainer/HBoxVisibilityRange/HSlider.value = $Octree.initial_visibility_range
	$Panel/VBoxContainer/HBoxPointBudget/HSlider.value = $Octree.point_budget

func _on_pointsize_value_changed(value: float) -> void:
	$Panel/VBoxContainer/HBoxPointSize/Label.text = str(value)+" mm"
	$Octree.point_size = value
	
func _on_visibility_range_value_changed(value: float) -> void:
	$Panel/VBoxContainer/HBoxVisibilityRange/Label.text = str(value)
	$Octree.initial_visibility_range = value

func _point_budget_value_changed(value: int) -> void:
	$Panel/VBoxContainer/HBoxPointBudget/Label.text = str(value) +" points"
	$Octree.point_budget = value
