extends Node3D

## A single node in the octree hierarchy
class_name OctreeNode

## ID encoded as string (prefixed with IDs of higher order nodes)
var id : String = ""
## Depth in the point cloud hierarchy.
var depth : int = 0

# Point attribute storage
var points : PackedVector3Array			## Position data
var normals : PackedVector3Array			## Normal vectors
var colors : PackedColorArray			## Color values
var intensities : PackedFloat32Array		## Point intensity values (not used so far)

## Each node has its own AABB
var aabb : AABB

## Reference (copy) to the global properties of this octree 
var octree_data : OctreeData = null

## Path in the octree folder hierarchy
var path : String = ""

## Visual point cloud representation
var visual : GeometryInstance3D = null

# Child nodes and child nodes queued for loading on demand
# TODO: loading on demand and threaded (delayed) loading of deeper nodes
# TODO: improve loading queue approach? (currently per node queue and global queue in [Octree])
# TODO: we should also cosider to free nodes that are not necessary anymore!
var children : Dictionary = {}
var loading_queue : Array = []

## Initialize node properties and load a new HRC file if necessary
func _init(p_id:String, p_aabb:AABB, p_octree_data:OctreeData) -> void:
	self.octree_data = p_octree_data
	self.path = p_octree_data.data_dir+p_id
	
	self.id = p_id
	self.aabb = p_aabb
	
# Setup the node when entering the scene tree
func _ready() -> void:
	# TODO: replace code to load all children with a dynamic approach depending on visibility!
	# TODO: load children in a breadth-first approach!
	while len(loading_queue) > 0:
		var c = loading_queue.pop_front()
		octree_data.request_subnode.emit(c)
	
	#if id == "":
	#	self.visibility_range_end = 15.0;
	
	_create_bbox()
	
## Create a new bounding box mesh and scale it to the current nodes AABB
func _create_bbox():
	var box = BoxMesh.new()
	box.size = Vector3(1,1,1)
	box.material = load("res://octree/octree_box.tres")
	var inst = MeshInstance3D.new()
	inst.scale = aabb.size
	#inst.position = Vector3(0.5+x*0.25,0.5+y*0.25,0.5+z*0.25) * scaling - octree_data.aabb.size*0.5
	inst.mesh = box
	inst.visibility_range_end = 10.0;
	add_child(inst)
	
func create_multimesh() -> void:
	# Existing geometry will be replaced
	if visual != null:
		remove_child(visual)
		visual.queue_free()

	# By default we render the points as quads to apply shaders
	if octree_data.render_mode == OctreeData.RenderMode.QUAD:
		visual = MultiMeshInstance3D.new()
		var multimesh = MultiMesh.new()
		
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		if octree_data.attributes["color"]:
			multimesh.use_colors = true
		multimesh.instance_count = points.size()
		var quad = QuadMesh.new()
		quad.size = Vector2(0.1,0.1)
		multimesh.mesh = quad
		
		
		for i in range(points.size()):
			var up = Vector3.UP
			if abs(normals[i].dot(up))>0.99:
				up = Vector3.FORWARD
			var axis_x = up.cross(normals[i]).normalized()
			var axis_y = normals[i].cross(axis_x).normalized()
			var b = Basis(axis_x, axis_y, normals[i])
			var t = Transform3D(b, points[i])
			multimesh.set_instance_transform(i, t)
			if octree_data.attributes["color"]:
				multimesh.set_instance_color(i, colors[i])
			
		visual.multimesh = multimesh
		visual.material_override = octree_data.quad_material
		add_child(visual)
	
	# DEBUG: render just bare points
	else:
		# Render as pure points
		var mesh = ArrayMesh.new()
		var arrays = []
		
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = points
		arrays[Mesh.ARRAY_COLOR] = colors
		
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arrays)
		mesh.surface_set_material(0, octree_data.point_material)
		visual = MeshInstance3D.new()
		visual.mesh = mesh
		add_child(visual)
