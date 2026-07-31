extends XRController3D

@onready var player = get_parent()
@onready var xr_node = get_tree().current_scene.find_child("StartXR",true)
@onready var environment_node = get_tree().current_scene.find_child("WorldEnvironment",true)
@onready var floor_node = get_tree().current_scene.find_child("Floor",true)
@onready var teleport_raycast = find_child("TeleportRayCast")
var use_ar = false
var is_grabbing = false
var grabbed_object : Node3D = null
var grabbed_dist = 0.0
var last_position = Vector3(0,0,0)

## Enable and disable the teleport tool
## If it gets disabled and a valid position had been selected, the player will be teleported.
func toggle_raycast(enabled:bool) -> void:
	if teleport_raycast:
		if not enabled:
			teleport_raycast.teleport(player)
			
		teleport_raycast.enabled = enabled

## Switch to see-through mode
func switch_to_ar() -> bool:
	if not xr_node:
		return false
	
	var xr_interface = xr_node.xr_interface
	if xr_interface:
		var modes = xr_interface.get_supported_environment_blend_modes()
		if XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND in modes:
			xr_interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND
		elif XRInterface.XR_ENV_BLEND_MODE_ADDITIVE in modes:
			xr_interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ADDITIVE
		else:
			return false
	else:
		return false
		
	use_ar = true
	
	# Change visibility of surrounding objects
	$controller_right.visible = false
	
	if floor_node:
		floor_node.visible = false
	if environment_node:
		environment_node.environment.background_mode = Environment.BG_CLEAR_COLOR
		environment_node.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		
	get_viewport().transparent_bg = true
	return true
	
## Switch to full VR mode
func switch_to_vr() -> bool:
	if not xr_node:
		return false
		
	var xr_interface = xr_node.xr_interface
	if xr_interface:
		var modes = xr_interface.get_supported_environment_blend_modes()
		if XRInterface.XR_ENV_BLEND_MODE_OPAQUE in modes:
			xr_interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_OPAQUE
		else:
			return false
	else:
		return false
		
	use_ar = false
	
	# Change visibility of surrounding objects
	$controller_right.visible = true
		
	if floor_node:
		floor_node.visible = true
	if environment_node:
		environment_node.environment.background_mode = Environment.BG_SKY
		environment_node.environment.ambient_light_source = Environment.AMBIENT_SOURCE_BG
	
	get_viewport().transparent_bg = false
	return true

func _on_button_pressed(button_name:String) -> void:
	if button_name == "trigger_click":
		toggle_raycast(true)
	elif button_name == "by_button":
		if use_ar:
			switch_to_vr()
		else:
			switch_to_ar()
	elif button_name == "grip_click":
		if $GrabRaycast.is_colliding():
			is_grabbing = true
			grabbed_object = $GrabRaycast.get_collider()
			grabbed_dist = ($GrabRaycast.get_collision_point()-self.global_position).length()
			last_position = self.global_position
	elif button_name == "primary_click":
		if grabbed_object:
			grabbed_object.scale = Vector3(1,1,1)

func _on_button_released(button_name:String) -> void:
	if button_name == "trigger_click":
		toggle_raycast(false)
	elif button_name == "grip_click":
		is_grabbing = false
		grabbed_object = null
		
func _physics_process(_delta: float) -> void:
	if is_grabbing and grabbed_object != null:
		var dist = self.global_position - last_position
		dist *= pow(1.5, max(0.0, grabbed_dist))
		grabbed_object.global_translate(dist)
		last_position = self.global_position
		
		var obj_scale = self.get_vector2("primary").y
		var obj_rotate = self.get_vector2("primary").x
		if abs(obj_scale) > 0.8:
			obj_scale *= 0.005
			var target_scale = clamp(grabbed_object.scale.y+obj_scale,0.05,100.0)
			grabbed_object.scale = Vector3(target_scale,target_scale,target_scale)
		if abs(obj_rotate) > 0.1:
			grabbed_object.rotate_y(0.02*obj_rotate)
		
