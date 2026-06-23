@tool
extends Node3D

## Main class for octree data structures.
class_name Octree

@export var data_type : OctreeLoader.DataTypes
var data_loader : OctreeLoader = null	## Data loader that should be used.
var root : OctreeNode = null				## Root node
var octree_data : OctreeData = null		## Metadata
var loading_queue : Array = []			## Sub nodes that have to be loaded

## Complete bounding box
var aabb : AABB:							
	get:
		return octree_data.aabb

## Path to the root directory of the octree (location of JSON file).
## TODO: update octree if path has changed.
@export_file_path var octree_path : String = ""

## The rendered point size can be adapted in the editor.
@export_range(1.0,50.0) var point_size : float = 20.0:
	set(value):
		point_size=value
		if octree_data:
			octree_data.quad_material.set_shader_parameter("point_size", value)

@export_range(1.0,100) var initial_visibility_range : float = 100.0:
	set(value):
		initial_visibility_range = value
		if octree_data:
			octree_data.initial_visibility_range = value

@export_range(1.0,50.0) var projection_size_threshold : float = 50:
	set(value):
		projection_size_threshold = value
		if octree_data:
			octree_data.projection_size_threshold = value
			
func _init() -> void:
	data_loader = OctreeLoader.get_loader(data_type)

## Load and setup data structure on scene load
func _ready() -> void:
	if octree_path.is_empty() or (!DirAccess.dir_exists_absolute(octree_path) \
			and !FileAccess.file_exists(octree_path)):
		return
		
	octree_data = data_loader.load_metadata(octree_path)
	octree_data.initial_visibility_range = initial_visibility_range
	octree_data.projection_size_threshold = projection_size_threshold
	octree_data.request_subnode.connect(self.request_subnode)
	octree_data.defer_subnode.connect(self.defer_subnode)
	
	root = OctreeNode.new("r", aabb, octree_data)
	data_loader.load_hierarchy(root)
	data_loader.load_pointdata(root)
	root.create_multimesh()
	
	add_child(root)
	
func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	
	if len(loading_queue) > 0:
		var c : OctreeNode = loading_queue.pop_front()
		data_loader.load_pointdata(c)
		c.create_multimesh()
	
## Add child to the loading queue
func request_subnode(childnode:OctreeNode) -> void:
	loading_queue.push_back(childnode)
	
## Remove a child from the loading queue
func defer_subnode(childnode:OctreeNode) -> void:
	loading_queue.erase(childnode)
