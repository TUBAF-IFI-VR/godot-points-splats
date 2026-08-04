extends Node

class_name CameraReplay

enum ReplayMode {Replay, Record}

signal reached_next_pos

@export var enabled : bool = false					## Processing is disabled by default
@export var camera : Node3D = null					## Reference to the used camera
@export var mode : ReplayMode = ReplayMode.Replay		## Switch recording and replay
@export var replay_speed : float = 1.0				## Replay the recorded camera path slower / faster
@export var save_screenshots : bool = false			## Save a screenshot with each recorded location

var index : int = 0
var record_file_path : String = ""
var camera_path : Array = []
var camera_timer : float = 0.0

func _ready() -> void:
	if not enabled:
		set_process(false)
		set_process_input(false)
		return
	
	var folder_path = ProjectSettings.globalize_path("user://")

	record_file_path = folder_path + "camera_path.json"

	if camera and mode == ReplayMode.Replay:
		var record_file = FileAccess.open(record_file_path, FileAccess.READ)
		camera_path = str_to_var(record_file.get_as_text())
		record_file.close()
		camera_path.push_front({"pos":camera.global_position, "rot":camera.global_transform.basis, "time":0.0})
		index = 1
		
func _exit_tree() -> void:
	if mode == ReplayMode.Record:
		var record_file = FileAccess.open(record_file_path, FileAccess.WRITE)
		record_file.store_string(var_to_str(camera_path))
		record_file.close()
		
func _process(delta):
	if not camera or mode != ReplayMode.Replay or index < 1 or index >= camera_path.size():
		return
	
	camera_timer += delta*replay_speed
	
	if camera_timer >= camera_path[index]["time"]:
		camera_timer = 0.0
		index += 1
		reached_next_pos.emit()
		
		if index >= camera_path.size():
			return
	
	var t = camera_timer / camera_path[index]["time"]
	var start = camera_path[index-1]
	var end = camera_path[index]
	var pos = start["pos"].lerp(end["pos"], t)
	var rot = start["rot"].slerp(end["rot"], t)
	camera.global_transform = Transform3D(rot, pos)
			
func record_camera_location() -> void:
	if mode != ReplayMode.Record:
		return
	if not camera:
		return
		
	camera_path.append({"pos": camera.global_position, "rot": camera.global_transform.basis,
						"time": Time.get_ticks_msec()*0.001})
	
	if save_screenshots:
		var image = get_viewport().get_texture().get_image()
		image.save_png("user://screenshot_%d.png" % index)
	
	index += 1
