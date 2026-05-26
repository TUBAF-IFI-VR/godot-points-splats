extends Node3D

# Main class used to load the a potree project
class_name PotreeData

# Data structure for a single node in the hierarchy
class PotreeNode:
	var name : String
	var level : int
	var point_cloud : int
	var bounding_box : AABB
	var points : PackedVector3Array
	var normals : PackedVector3Array
	var colors : PackedColorArray
	var intensities : PackedFloat32Array
	var children : Array = []
	var binary_file_path : String
	var scale : float = 1.0
	
var root_node : PotreeNode
var metadata : Dictionary = {}
var attributes = {
	"position" : true,
	"normal" : false,
	"color" : false,
	"intensity" : false,
	"class"  : false
}
var point_bytes = 3*4
var point_material = preload("res://potree/basic_point.tres")


var bb_min : Vector3
var bb_max : Vector3

# Load metadata from the JSON base file
func load_potree(base_path:String) -> void:
	var file = FileAccess.open(base_path + "/cloud.js", FileAccess.READ)
	metadata = JSON.parse_string(file.get_as_text())
	file.close()
	
	# Check which attributes are available
	for a in metadata["pointAttributes"]:
		#attributes[a] = true
		if a == "COLOR_PACKED":
			attributes["color"] = true
			point_bytes += 4
		if a == "INTENSITY":
			attributes["intensity"] = true
			point_bytes += 4
		elif a == "NORMAL_SPHEREMAPPED":
			attributes["normal"] = true
			point_bytes += 2
	print(point_bytes, attributes)
	
	bb_min = Vector3(metadata["boundingBox"]["lx"],metadata["boundingBox"]["lz"],metadata["boundingBox"]["ly"])
	bb_max = Vector3(metadata["boundingBox"]["ux"],metadata["boundingBox"]["uz"],metadata["boundingBox"]["uy"])
	
	# TODO: check for available attributes + make robust for different potree versions
	# TODO: check for errors
	
	root_node = _load_hierarchy(base_path + metadata["octreeDir"])

# Read a 4byte float value and convert from big to little endian
func _read_coord(file:FileAccess):
	var buffer:PackedByteArray = PackedByteArray([file.get_8(),file.get_8(),file.get_8(),file.get_8()])	
	buffer.reverse()
	return buffer.decode_float(0)

func _load_hierarchy(hierarchy_path:String) -> PotreeNode:
	var current_path = hierarchy_path
	var root = PotreeNode.new()
	root.name = "r"
	
	var hrc_filename = hierarchy_path + "/r/r.hrc"
	var hrc_file = FileAccess.open(hrc_filename, FileAccess.READ)
	var hrc_data : PackedByteArray = hrc_file.get_buffer(hrc_file.get_length())
	hrc_file.close()
	
	var node = PotreeNode.new()
	var bin_path = hrc_filename.replace(".hrc", ".bin")
	node.binary_file_path = bin_path
	_load_pointcloud(node)
	
	root.children.append(node)
	
	#var dir = DirAccess.open(hierarchy_path)
	#dir.list_dir_begin()
	#var filename = dir.get_next()
	#while filename != "":
			#if dir.current_is_dir():
				#continue
			#
			#if filename.ends_with(".hrc"):
				#print("Found file: " + filename)
			#filename = dir.get_next()
	
	return root
	
const MAX_31B = 1 << 31
const MAX_32B = 1 << 32
func unsigned32_to_signed(unsigned):
	return (unsigned + MAX_31B) % MAX_32B - MAX_31B
	
func _load_pointcloud(node:PotreeNode) -> void:
	var file = FileAccess.open(node.binary_file_path, FileAccess.READ)
	if not file:
		push_error("Failed to open file: "+node.binary_file_path)
		return
	
	var point_count = int(file.get_length()/point_bytes)
	node.points = PackedVector3Array()
	node.points.resize(point_count)
	if attributes["color"]:
		node.colors = PackedColorArray()
		node.colors.resize(point_count)
	if attributes["normal"]:
		node.normals = PackedVector3Array()
		node.normals.resize(point_count)
	
	#var bb_scale = 
	var x = 0.0
	var y = 0.0
	var z = 0.0
	
	for i in range(point_count):
		if file.eof_reached():
			push_error("Failed to read point: reached end of file!")
		
		if float(metadata["version"]) > 1.3:
			x = file.get_32() * metadata["scale"]
			z = file.get_32() * metadata["scale"]
			y = file.get_32() * metadata["scale"]
			#x = unsigned32_to_signed(file.get_32()) * metadata["scale"]
			#y = unsigned32_to_signed(file.get_32()) * metadata["scale"]
			#z = unsigned32_to_signed(file.get_32()) * metadata["scale"]
		else:
			x = file.get_float()
			z = file.get_float()
			y = file.get_float()
		node.points[i] = Vector3(x,y,z) + bb_min
		
		if attributes["color"]:
		#for i in range(point_count):
			#if file.eof_reached():
			#	push_error("Failed to read point: reached end of file!")
			node.colors[i] = Color(
				file.get_8()/255.0,
				file.get_8()/255.0,
				file.get_8()/255.0,
				1.0
				#file.get_8()/255.0
			)
			file.get_8()
		if attributes["normal"]:
		#for i in range(point_count):
			#if file.eof_reached():
			#	push_error("Failed to read point: reached end of file!")
			node.normals[i] = _decode_normal(file.get_8(), file.get_8())
		
	for i in range(10):
		print(node.points[i],node.colors[i],node.normals[i])
	
	print(file.eof_reached())
	var extra_bytes = 0
	while !file.eof_reached():
		print(file.get_8())
		extra_bytes += 1
	print(extra_bytes, " extra bytes")
			
	print("Loaded %d points!" % node.points.size())
	file.close()
	
func _decode_normal(x:int, y:int) -> Vector3:
	var nx = (x / 255.0) * 2.0 - 1.0;
	var ny = (y / 255.0) * 2.0 - 1.0;
	
	#var z = 1.0 - abs(x) - abs(y)
	#if z < 0:
	#	x = (1.0-abs(y)) * (1.0 if x>=0.0 else -1.0) 
	#	y = (1.0-abs(x)) * (1.0 if y>=0.0 else -1.0) 
		
	var nz = 1.0;
	var nw = -1.0;
	var l = (nx * (-nx)) + (ny * (-ny)) + (nz * (-nw));
	nz = l;
	nx = nx * sqrt(l);
	ny = ny * sqrt(l);

	nx = nx * 2;
	ny = ny * 2;
	nz = nz * 2 - 1;
	
	return Vector3(nx,nz,ny).normalized()
	
#func _recursive_load_binary_files(path: String):
	#var dir = DirAccess.open(path)
	#if dir:
		#dir.list_dir_begin()
		#while true:
			#var file = dir.get_next()
			#if file == "":
				#break
			#
			#if file.ends_with(".bin"):
				#parse_binary_file(path + "/" + file)
			#elif dir.current_is_dir() and file != "." and file != "..":
				#_recursive_load_binary_files(path + "/" + file)
		#
		#dir.list_dir_end()
	
func _create_multimesh() -> void:
	var node:PotreeNode = root_node.children[0]
	
	#var inst = MultiMeshInstance3D.new()
	#var multimesh = MultiMesh.new()
	#
	#multimesh.transform_format = MultiMesh.TRANSFORM_3D
	#if attributes["color"]:
		#multimesh.use_colors = true
	#multimesh.instance_count = node.points.size()
	#multimesh.mesh = 
	
	#for i in range(node.points.size()):
		#var t = Transform3D(Basis(), node.points[i])
		#multimesh.set_instance_transform(i, t)
		#if attributes["color"]:
			#multimesh.set_instance_color(i, node.colors[i])
		
	#inst.multimesh = multimesh
	#inst.material_override = point_material
	#add_child(inst)
	
	var mesh = ArrayMesh.new()
	var arrays = []
	
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = node.points
	arrays[Mesh.ARRAY_COLOR] = node.colors
	
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arrays)
	mesh.surface_set_material(0, point_material)
	var inst = MeshInstance3D.new()
	inst.mesh = mesh
	add_child(inst)
	
func create_box(id:int):
	var x = 1 if id&1 else -1
	var z = 1 if id&2 else -1
	var y = 1 if id&4 else -1
	
	var scale = bb_max-bb_min
	
	var box = BoxMesh.new()
	box.size = Vector3(0.5,0.5,0.5)
	box.material = load("res://potree/octree_box.tres")
	var inst = MeshInstance3D.new()
	inst.scale = scale
	inst.position = Vector3(0.5+x*0.25,0.5+y*0.25,0.5+z*0.25) * scale + bb_min
	inst.mesh = box
	inst.visibility_range_end = 3.0;
	add_child(inst)

func read_hrc(filename:String):
	var file = FileAccess.open(filename, FileAccess.READ)
	
	var node_mask = file.get_8()
	var point_count = file.get_32()
	for i in range(8):
		if node_mask & (1<<i):
			create_box(i)
	
	file.close()
	
func _ready() -> void:
	load_potree("res://lion_takanawa/")
	_create_multimesh()
	read_hrc("res://lion_takanawa/data/r/r.hrc")
