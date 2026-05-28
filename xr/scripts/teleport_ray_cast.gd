extends RayCast3D

## Very Basic teleport function
func teleport(player:XROrigin3D) -> void:
	if player and is_colliding():
		var p = get_collision_point()
		player.position = p

## Update the marker and pointer
func _physics_process(_delta) -> void:
	# Show and hide the pointer
	if enabled:
		$RayCastMesh.visible = true
	else:
		$RayCastMesh.visible = false
		return
	
	# Show the target circle only if a valid position has been hit
	if is_colliding():
		var p = get_collision_point()
		$TeleportMarker.visible = true
		$TeleportMarker.position = p
		$TeleportMarker.rotation = Vector3(0,0,0)
	else:
		$TeleportMarker.visible = false
