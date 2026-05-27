extends Node3D

# A single node in the octree hierarchy
class_name OctreeNode

# ID encoded as string (prefixed with IDs of higher order nodes)
var id : String = ""

# Point attribute storage
var points : PackedVector3Array
var normals : PackedVector3Array
var colors : PackedColorArray
var intensities : PackedFloat32Array

# Each node has its own AABB
var aabb : AABB

# Reference (copy) to the global properties of this octree 
var octree_data : OctreeData = null

# Path in the octree folder hierarchy
var path : String = ""

# Visual point cloud representation
var pc_instance = null

# Child nodes and child nodes queued for loading on demand
# TODO: loading on demand and threaded (delayed) loading of deeper nodes
var children : Dictionary = {}
var loading_queue : Array = []

# Initialize node properties and load a new HRC file if necessary
func _init(p_id:String, p_aabb:AABB, p_new_subtree:bool, p_octree_data:OctreeData) -> void:
	self.octree_data = p_octree_data
	self.path = p_octree_data.data_dir+"r"+p_id
	
	self.id = p_id
	self.aabb = p_aabb
	if p_new_subtree:
		_load_potree_hrc(self.path+".hrc")
	
# Setup the node when entering the scene tree
func _ready() -> void:
	# Load the binary point data
	_load_potree_bin(self.path+".bin")
	
	#var base_aabb = self.aabb
	#base_aabb.size *= 0.5
	#while loading_queue.size() > 0:
		#var next = loading_queue.pop_front()
		#var child_aabb = base_aabb
		#var y = 1 if int(next)&1 else 0
		#var z = 1 if int(next)&2 else 0
		#var x = 1 if int(next)&4 else 0
		#child_aabb.position += base_aabb.size*Vector3(x,y,z)
		#children[next] = OctreeNode.new(id+next, child_aabb, false, octree_data)
		##children[next].position = base_aabb.size*Vector3(x,y,z)
		#add_child(children[next])
	
	# Create the multi mesh used for point rendering
	_create_multimesh()
	#var label = Label3D.new()
	#label.text = id
	#add_child(label)
	
	#if id == "":
	#	self.visibility_range_end = 15.0;
	
	# Create a new bounding box mesh and scale it to the current nodes AABB
	var box = BoxMesh.new()
	box.size = Vector3(1,1,1)
	box.material = load("res://octree/octree_box.tres")
	var inst = MeshInstance3D.new()
	inst.scale = aabb.size
	#inst.position = Vector3(0.5+x*0.25,0.5+y*0.25,0.5+z*0.25) * scaling - octree_data.aabb.size*0.5
	inst.mesh = box
	inst.visibility_range_end = 10.0;
	add_child(inst)
	
#func _create_box(p_id:int):
	#var y = 1 if p_id&1 else -1
	#var z = 1 if p_id&2 else -1
	#var x = 1 if p_id&4 else -1
	#
	#var scaling = octree_data.aabb.size
	#
	#var box = BoxMesh.new()
	#box.size = Vector3(0.5,0.5,0.5)
	#box.material = load("res://potree/octree_box.tres")
	#var inst = MeshInstance3D.new()
	#inst.scale = scaling
	#inst.position = Vector3(0.5+x*0.25,0.5+y*0.25,0.5+z*0.25) * scaling - octree_data.aabb.size*0.5
	#inst.mesh = box
	#inst.visibility_range_end = 10.0;
	#add_child(inst)
	
# Load the binary hrc (hierarchy) file which describes a new branch
func _load_potree_hrc(filename:String):
	var file = FileAccess.open(filename, FileAccess.READ)
	
	# We are the root node of the new branch
	var index_queue = [self]

	# Walk through the hrc file and push necessary subnodes into the queue
	while !file.eof_reached() and index_queue.size() > 0:
		var current = index_queue.pop_front()
		var node_mask = file.get_8()
		var point_count = file.get_32()
		var base_aabb = current.aabb
		base_aabb.size *= 0.5
		
		# Check the node mask and spawn necessary subnodes as children
		for i in range(8):
			if node_mask & (1<<i):
				var child_index = current.id+str(i)
				if len(child_index) <= octree_data.step_size:
					var child_aabb = base_aabb
					
					# Determine the correct octant
					var y = 1 if i&1 else -1
					var z = 1 if i&2 else -1
					var x = 1 if i&4 else -1
					
					# Spawn the new child node and adjust its position
					child_aabb.position = Vector3(0,0,0)#+= base_aabb.size*Vector3(x,y,z)
					var child:OctreeNode = OctreeNode.new(child_index, child_aabb, false, octree_data)
					child.position = base_aabb.size*Vector3(x,y,z)*0.5
					current.children[i] = child
					current.add_child(child)
					index_queue.push_back(child)
	
	file.close()

# Convert the 2 byte integer representation into a correct normal vector
func _decode_normal(x:int, y:int) -> Vector3:
	# Based on Potree BinaryDecoderWorker
	# https://github.com/potree/potree/blob/develop/src/workers/BinaryDecoderWorker.js
	var nx = (x / 255.0) * 2.0 - 1.0;
	var ny = (y / 255.0) * 2.0 - 1.0;
	var nz = 1.0;
	var nw = -1.0;
	var l = (nx * (-nx)) + (ny * (-ny)) + (nz * (-nw));
	nz = l;
	nx = nx * sqrt(l);
	ny = ny * sqrt(l);
	
	# Convert from 0/1 range to -1/+1
	nx = nx * 2;
	ny = ny * 2;
	nz = nz * 2 - 1;
	
	return Vector3(nx,nz,ny).normalized()

# Load the actual point data from bin files
func _load_potree_bin(binary_file_path:String) -> void:
	var file = FileAccess.open(binary_file_path, FileAccess.READ)
	if not file:
		push_error("Failed to open file: "+binary_file_path)
		return
	
	# For the following line, integer division is desired
	@warning_ignore("integer_division")
	var point_count = file.get_length()/octree_data.point_bytes
	
	# Create and resize the necessary data arrays
	points = PackedVector3Array()
	points.resize(point_count)
	if octree_data.attributes["color"]:
		colors = PackedColorArray()
		colors.resize(point_count)
	if octree_data.attributes["normal"]:
		normals = PackedVector3Array()
		normals.resize(point_count)
	
	#var bb_scale = 
	var x = 0.0
	var y = 0.0
	var z = 0.0
	
	# There should be exactly point_count*point_bytes bytes in the file
	# TODO: check with the point count read from the hrc file to validate
	for i in range(point_count):
		if file.eof_reached():
			push_error("Failed to read point: reached end of file!")
		
		# TODO: not sure about the correct interpretation for specific versions
		if octree_data.version > 1.3:
			x = file.get_32() * octree_data.scale
			z = file.get_32() * octree_data.scale
			y = file.get_32() * octree_data.scale
		else:
			x = file.get_float()
			z = file.get_float()
			y = file.get_float()
		
		# Arrange the points around the AABB's center
		points[i] = Vector3(x,y,z) - self.aabb.get_center()
		
		# Read color values if they exist in the bin file
		if octree_data.attributes["color"]:
			colors[i] = Color(
				file.get_8()/255.0,
				file.get_8()/255.0,
				file.get_8()/255.0,
				1.0
				#file.get_8()/255.0
			)
			file.get_8()
		# Read the normal vector if present
		if octree_data.attributes["normal"]:
			normals[i] = _decode_normal(file.get_8(), file.get_8())
	
	# Check if all bytes have been read to validate the data
	# There usually is a single 0 byte at the end
	var extra_bytes = 0
	var last_byte = -1
	while !file.eof_reached():
		last_byte = file.get_8()
		extra_bytes += 1
	
	# DEBUG: print validation result
	print("Loaded %d points!" % points.size())
	if extra_bytes == 1 and last_byte == 0:
		print("Binary file is valid.")
	else:
		print("Invalid binary file size?")
	
	file.close()
	
func _create_multimesh() -> void:

	if octree_data.render_mode == OctreeData.RenderMode.QUAD:
		var inst = MultiMeshInstance3D.new()
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
			
		inst.multimesh = multimesh
		inst.material_override = octree_data.quad_material
		add_child(inst)
	
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
		pc_instance = MeshInstance3D.new()
		pc_instance.mesh = mesh
		add_child(pc_instance)
