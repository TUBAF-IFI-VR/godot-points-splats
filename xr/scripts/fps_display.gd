extends MeshInstance3D

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta):
	$SubViewport/Label.text = str(Engine.get_frames_per_second())+" FPS"
