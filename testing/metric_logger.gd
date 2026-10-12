class_name MetricLogger
extends Node
## A very basic helper node to collect some performane metrics.


## Slect the logging mode to use.
##
## Logging can be permanent with a specific rate, triggered by key press
## or whenever a camera checkpoint has been reached.
enum LoggingMode {Permanent, OnKeyPress, OnCameraEvent}


@export var enabled : bool = false ## Processing is disabled by default
@export var octree : Octree = null ## Reference to the logged octree

## Collect metrics permanently by default
@export var logging_mode : LoggingMode = LoggingMode.Permanent 

## Number of seconds between 2 log entries
@export var logging_rate : float = 2.0

## Optional reference to a camera replay recorder
@export var camera_recorder : CameraReplay = null

## Log file that has been opened for writing.
var _log_file: FileAccess

## Internal counter for the timer mechanism.
var _log_timer := 0.0


## Prepare an empty log file.
func _ready() -> void:
	if not enabled:
		set_process(false)
		set_process_input(false)
		return
		
	var folder_path := ProjectSettings.globalize_path("user://")

	var file_path := folder_path + "performance_profile.csv"

	_log_file = FileAccess.open(file_path, FileAccess.WRITE)
	_log_file.store_line("time,fps,process_ms,memory_mb,video_memory_mb,objects_drawn,"+\
						"primitives_drawn,draw_calls,objects,nodes,viewport_width,viewport_height,"+\
						"point_count,loaded_point_count,visibility_range,point_size,threshold")
	_log_file.flush()
	
	if logging_mode == LoggingMode.OnCameraEvent and camera_recorder:
		camera_recorder.reached_next_pos.connect(self.log_performance_data)


## Trigger logging by key pressed if enabled.
func _input(event: InputEvent) -> void:
	if logging_mode != LoggingMode.OnKeyPress or camera_recorder == null:
		return
	
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ENTER:
			log_performance_data()
			camera_recorder.record_camera_location()


## Write permanently to the log file if enabled.
func _process(delta: float) -> void:
	if logging_mode != LoggingMode.Permanent:
		return
		
	_log_timer += delta

	if _log_timer >= logging_rate:
		_log_timer = 0.0
		log_performance_data()


## Add a new entry to the log file.
func log_performance_data() -> void:
	if _log_file == null:
		return

	if octree == null:
		return

	if octree.octree_path.is_empty():
		return

	var time_seconds: float = Time.get_ticks_msec() / 1000.0
	var process_ms: float = float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0
	var memory_mb: float = float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1024.0 / 1024.0
	var video_memory_mb: float = float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / 1024.0 / 1024.0
	var objects_drawn: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	var primitives_drawn: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var draw_calls: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var objects: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var nodes: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var viewport_size = get_viewport().get_visible_rect().size

	var point_count : int = octree.point_count
	var loaded_point_count : int = octree.loaded_point_count
	var visibility_range: float = octree.initial_visibility_range
	var point_size: float = octree.point_size
	var threshold: float = octree.projection_size_threshold

	var row_data := [
		"%.2f" % time_seconds,
		str(Engine.get_frames_per_second()),
		"%.3f" % process_ms,
		"%.2f" % memory_mb,
		"%.2f" % video_memory_mb,
		str(objects_drawn),
		str(primitives_drawn),
		str(draw_calls),
		str(objects),
		str(nodes),
		str(int(viewport_size[0])),
		str(int(viewport_size[1])),
		str(point_count),
		str(loaded_point_count),
		str(visibility_range),
		str(point_size),
		str(threshold)
	]

	_log_file.store_line(",".join(row_data))


## Flush and close the opened log file.
func _exit_tree() -> void:
	if not enabled:
		return
	
	_log_file.flush()
	if _log_file != null:
		_log_file.close()
