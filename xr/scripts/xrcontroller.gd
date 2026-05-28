extends XRController3D

@onready var player = get_parent()
@onready var xr_node = get_tree().current_scene.find_child("StartXR",true)
@onready var environment_node = get_tree().current_scene.find_child("WorldEnvironment",true)
@onready var floor_node = get_tree().current_scene.find_child("Floor",true)
@onready var teleport_raycast = find_child("TeleportRayCast")
var use_ar = false
var is_grabbing = false
var grabbed_object : Node3D = null
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
			last_position = self.global_position

func _on_button_released(button_name:String) -> void:
	if button_name == "trigger_click":
		toggle_raycast(false)
	elif button_name == "grip_click":
		is_grabbing = false
		grabbed_object = null
		
func _physics_process(delta: float) -> void:
	if is_grabbing and grabbed_object != null:
		var dist = self.global_position - last_position
		grabbed_object.global_translate(dist)
		last_position = self.global_position
		
