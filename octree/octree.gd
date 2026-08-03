@tool
extends StaticBody3D

## Main class for octree data structures.
class_name Octree

@export var data_type : OctreeLoader.DataTypes
var data_loader : OctreeLoader = null	## Data loader that should be used.
var root : OctreeNode = null				## Root node
var octree_data : OctreeData = null		## Metadata
var loading_queue : Array = []			## Sub nodes that have to be loaded
var _loading_thread_count : int = 1		## Number of threads that will be used for point loading
var _loading_threads : Array = []		## Array of threads performing point loading
var _loading_stopped : bool = false		## Notify the loading threads to exit

## Complete bounding box
var aabb : AABB:	
	get:
		return octree_data.aabb
		
## Total number of points in point cloud
var point_count : int:
	get:
		return octree_data.point_count
		
## Currently loaded number of points
var loaded_point_count : int:
	get:
		return octree_data.loaded_point_count

## Path to the root directory of the octree (location of JSON file).
## TODO: update octree if path has changed.
@export_file_path var octree_path : String = "":
	set(value):
		if root:
			free_octree()
			
		octree_path = value
		load_octree()

## The rendered point size in mm, can be adapted in the editor.
@export_range(1.0,100.0) var point_size : float = 20.0:
	set(value):
		point_size=value
		if octree_data:
			octree_data.quad_material.set_shader_parameter("point_size", value)

@export_range(1.0,100) var initial_visibility_range : float = 100.0:
	set(value):
		initial_visibility_range = value
		if octree_data:
			octree_data.initial_visibility_range = value

## Threshold to trigger visiblity of a subnode (in % of screen size)
@export_range(0.01,2.0,0.01) var projection_size_threshold : float = 0.2:
	set(value):
		projection_size_threshold = value
		if octree_data:
			octree_data.projection_size_threshold = value
			
@export var adaptive_point_size : bool = true:
	set(value):
		adaptive_point_size = value
		if octree_data:
			octree_data.quad_material.set_shader_parameter("adaptive_point_size", value)
			
@export var show_debug_objects : bool = false:
	set(value):
		show_debug_objects = value
		if octree_data:
			octree_data.show_debug_objects = value
			
func _init() -> void:
	pass
	
## Load and setup data structure on scene load
func _ready() -> void:
	pass

func _exit_tree() -> void:
	free_octree()
	
func _process(_delta: float) -> void:
	pass
	
## Wait for new nodes until loading ended, meant to be executed by individal threads
func _loading_loop() -> void:
	while not _loading_stopped:
		if len(loading_queue) > 0:
			var c : OctreeNode = loading_queue.pop_front()
			data_loader.load_pointdata(c)
			c.call_deferred("create_multimesh")
		else:
			OS.delay_msec(50)
		
## Load a point cloud file
func load_octree() -> void:
	data_loader = OctreeLoader.get_loader(data_type)
	
	if octree_path.is_empty() or (!DirAccess.dir_exists_absolute(octree_path) \
			and !FileAccess.file_exists(octree_path)):
		return
		
	octree_data = data_loader.load_metadata(octree_path)
	octree_data.quad_material.set_shader_parameter("point_size", point_size)
	octree_data.initial_visibility_range = initial_visibility_range
	octree_data.projection_size_threshold = projection_size_threshold
	octree_data.request_subnode.connect(self.request_subnode)
	octree_data.defer_subnode.connect(self.defer_subnode)
	
	root = OctreeNode.new("r", aabb, octree_data)
	data_loader.load_hierarchy(root)
	data_loader.load_pointdata(root)
	root.create_multimesh()
	
	self.set_collision_layer_value(1,false)
	self.set_collision_layer_value(17,true)
	var collision = CollisionShape3D.new()
	collision.shape = BoxShape3D.new()
	collision.shape.size = root.aabb.size
	add_child(collision)
	
	add_child(root)
	
	# Only load deeper nodes if not in editor mode
	if Engine.is_editor_hint():
		return
		
	# Create a set of loading threads which wait for requested octree nodes
	_loading_thread_count = max(1, OS.get_processor_count()-1)
	for i in _loading_thread_count:
		var t = Thread.new()
		_loading_stopped = false
		_loading_threads.push_back(t)
		t.start(_loading_loop, Thread.PRIORITY_LOW)

## Free and remove the current octree nodes
func free_octree() -> void:
	# Stop the loading process
	_loading_stopped = true
	for t in _loading_threads:
		t.wait_to_finish()
	
	# Free the created loader and data structure
	data_loader.free()
	data_loader = null
	
	remove_child(root)
	root.queue_free()
	root = null
	
	octree_data = null
	
## Add child to the loading queue
func request_subnode(childnode:OctreeNode) -> void:
	# Top most nodes of hierarchy get higher priority
	if loading_queue.size() > 0 and childnode.depth < loading_queue[0].depth:
		loading_queue.push_front(childnode)
	else:
		loading_queue.push_back(childnode)
	
## Remove a child from the loading queue
func defer_subnode(childnode:OctreeNode) -> void:
	loading_queue.erase(childnode)
