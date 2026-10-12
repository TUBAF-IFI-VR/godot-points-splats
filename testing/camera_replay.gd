class_name CameraReplay
extends Node
## A basic helper node to record and play camera paths.


## The next camera checkpoint has been reached.
signal reached_next_pos


## Camera paths can either be recorded or played.
enum ReplayMode {Replay, Record}


@export var enabled : bool = false ## Processing is disabled by default
@export var camera : Node3D = null ## Reference to the used camera
@export var mode : ReplayMode = ReplayMode.Replay ## Switch recording and replay
@export var replay_speed : float = 1.0 ## Replay the recorded camera path slower / faster
@export var save_screenshots : bool = false ## Save a screenshot with each recorded location

var _index : int = 0 ## Index of the next checkpoint to target.
var _record_file_path : String = "" ## Path to the file to write or read.
var _camera_path : Array = [] ## List of camera checkpoints.
var _camera_timer : float = 0.0 ## Internal timer


func _ready() -> void:
	# This node does nothing if disabled.
	if not enabled:
		set_process(false)
		set_process_input(false)
		return
	
	var folder_path = ProjectSettings.globalize_path("user://")

	_record_file_path = folder_path + "_camera_path.json"

	# Read a recorded camera path and use the current camera position as initial
	# checkpoint.
	if camera and mode == ReplayMode.Replay:
		var record_file = FileAccess.open(_record_file_path, FileAccess.READ)
		_camera_path = str_to_var(record_file.get_as_text())
		record_file.close()
		_camera_path.push_front({
			"pos":camera.global_position, 
			"rot":camera.global_transform.basis, 
			"time":0.0
		})
		_index = 1


## Write the path to file if we are in recording mode.
func _exit_tree() -> void:
	if mode == ReplayMode.Record:
		var record_file = FileAccess.open(_record_file_path, FileAccess.WRITE)
		record_file.store_string(var_to_str(_camera_path))
		record_file.close()


## Update the camera transform if we are in replay mode.
func _process(delta):
	if not camera or mode != ReplayMode.Replay or _index < 1 or _index >= _camera_path.size():
		return
	
	_camera_timer += delta*replay_speed
	
	if _camera_timer >= _camera_path[_index]["time"]:
		_camera_timer = 0.0
		_index += 1
		reached_next_pos.emit()
		
		if _index >= _camera_path.size():
			return
	
	var t = _camera_timer / _camera_path[_index]["time"]
	var start = _camera_path[_index-1]
	var end = _camera_path[_index]
	var pos = start["pos"].lerp(end["pos"], t)
	var rot = start["rot"].slerp(end["rot"], t)
	camera.global_transform = Transform3D(rot, pos)


## Record the current camera position.
func record_camera_location() -> void:
	if mode != ReplayMode.Record:
		return
	if not camera:
		return
		
	_camera_path.append({"pos": camera.global_position, "rot": camera.global_transform.basis,
						"time": Time.get_ticks_msec()*0.001})
	
	if save_screenshots:
		var image = get_viewport().get_texture().get_image()
		image.save_png("user://screenshot_%d.png" % _index)
	
	_index += 1
