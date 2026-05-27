extends Node3D

## Made for simple Godot editor like camera movement (but can be attached to any node to move it).
class_name FlyingCamera

@export var move_speed :float = 0.2
@export var mouse_sensitivity : float = 0.002
var velocity = Vector3()
var direction = Vector3()

# Called when the node enters the scene tree for the first time.
func _ready():
	pass

func _input(event):
	# Rotate with right mouse button (just like the Godot editor camera)
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		var change_x = -event.relative.x * mouse_sensitivity
		var change_y = -event.relative.y * mouse_sensitivity
		
		rotation.y += change_x
		rotation.x = clamp(rotation.x + change_y, -1.5, 1.5)

func _physics_process(_delta):
	# Set direction vectors for camera movement
	direction = Vector3()
	var aim = global_transform.basis.z
	var side = global_transform.basis.x
	#var up = global_transform.basis.y
	
	# Speed up with shift key
	var speed_multiplier = 1.0
	if Input.is_key_pressed(KEY_SHIFT):
		speed_multiplier *= 3.0
	
	# Evaluate key presses
	direction = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	direction.x += int(Input.is_key_pressed(KEY_D)) - int(Input.is_key_pressed(KEY_A))
	direction.y += int(Input.is_key_pressed(KEY_S)) - int(Input.is_key_pressed(KEY_W))
	
	direction = (aim*direction.y) + (side*direction.x)
	
	# Move the camera in world space
	velocity = direction * move_speed * speed_multiplier
	global_translate(velocity)
	
