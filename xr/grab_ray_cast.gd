extends RayCast3D

## Update the marker
func _physics_process(_delta) -> void:
	# Show and hide the pointer
	if not enabled:
		$GrabMarker.visible = false
		return
	
	# Show the target circle only if a valid position has been hit
	if is_colliding():
		var p = get_collision_point()
		$GrabMarker.visible = true
		$GrabMarker.position = 0.25 * ($GrabMarker.position*3+p)
		
		var normal = get_collision_normal()
		var target_pos = p + normal
		if (target_pos-p).length_squared() > 0.1:
			$GrabMarker.transform = $GrabMarker.transform.looking_at(target_pos,Vector3(0,1,0))
	else:
		$GrabMarker.visible = false
