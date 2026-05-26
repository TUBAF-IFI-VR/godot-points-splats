extends Node3D

# Main class for octree data structures
class_name Octree

var root : OctreeNode = null	# Root node
var data : OctreeData = null	# Metadata
var aabb : AABB:				# Complete bounding box
	get:
		return data.aabb

# Path to the root directory of the octree (location of JSON file)
# TODO: update octree if path has changed
@export_dir var octree_path : String = ""

# Rendered point size can be adapted in the editor
@export_range(1.0,50.0) var point_size : float = 20.0:
	set(value):
		point_size=value
		if data:
			data.quad_material.set_shader_parameter("point_size", value)

func _init() -> void:
	data = OctreeData.new()

# Load and setup data structure on scene load
func _ready() -> void:
	if octree_path.is_empty() || !DirAccess.dir_exists_absolute(octree_path):
		return
		
	load_potree(octree_path)
	root = OctreeNode.new("", aabb, true, data)
	add_child(root)
	
	# DEBUG:
	var hrc_data = analyze_hrc(octree_path + "/data/r/r.hrc")
	for n in hrc_data:
		var str = "%5s | %8d | " % [n["name"], n["points"]]
		for i in range(8):
			str += "1" if n["mask"] & (1<<i) else "0"
		print(str)

# Load a octree from its root path
func load_potree(base_path:String) -> bool:
	# Load metadata
	var file = FileAccess.open(base_path + "/cloud.js", FileAccess.READ)
	var metadata = JSON.parse_string(file.get_as_text())
	file.close()
	
	# Apply relevant values to provided properties
	data.version = float(metadata["version"])
	data.data_dir = base_path+"/"+metadata["octreeDir"]+"/r/"
	data.spacing = metadata["spacing"]
	data.scale = metadata["scale"]
	data.step_size = metadata["hierarchyStepSize"] 
	#scale = Vector3(octree_scale, octree_scale, octree_scale)
	
	# We have to calculate the correct number of bytes per point
	# Position is always expected, start with 3 floats per point
	data.point_bytes = 3*4
	
	# Walk through the available point attributes and calculate byte count
	for a in metadata["pointAttributes"]:
		#attributes[a] = true
		if a == "COLOR_PACKED":
			data.attributes["color"] = true
			data.point_bytes += 4
		if a == "INTENSITY":
			data.attributes["intensity"] = true
			data.point_bytes += 4
		elif a == "NORMAL_SPHEREMAPPED":
			data.attributes["normal"] = true
			data.point_bytes += 2
			
	# For debugging
	print(data.point_bytes, data.attributes)
	
	# Convert the bounding boxes into Godot AABBs (swap y and z coordinates)
	var bb_min = Vector3(metadata["boundingBox"]["lx"],metadata["boundingBox"]["lz"],metadata["boundingBox"]["ly"])
	var bb_max = Vector3(metadata["boundingBox"]["ux"],metadata["boundingBox"]["uz"],metadata["boundingBox"]["uy"])
	data.aabb = AABB(bb_min, bb_max-bb_min)
	
	bb_min = Vector3(metadata["tightBoundingBox"]["lx"],metadata["tightBoundingBox"]["lz"],metadata["tightBoundingBox"]["ly"])
	bb_max = Vector3(metadata["tightBoundingBox"]["ux"],metadata["tightBoundingBox"]["uz"],metadata["tightBoundingBox"]["uy"])
	data.aabb_tight = AABB(bb_min, bb_max-bb_min)
	
	# TODO: check for errors
	
	#root = _load_hierarchy(base_path + metadata["octreeDir"])
	return true

# For debugging
func analyze_hrc(hrc_path:String) -> Array:
	var f = FileAccess.open(hrc_path,FileAccess.READ)
	var next_nodes = ["r"]
	var results = []
	
	if f.is_open():
		while len(next_nodes) > 0:
			if f.eof_reached():
				print("Error: reached end of hrc file before all nodes have been read!")
				break
			var current = next_nodes.pop_front() 	# FIFO queue
				
			# Read node data: 1 byte mask and 4 byte point count
			var mask = f.get_8()
			var num_points = f.get_32()
			
			results.append({
				'name': current,
				'points': num_points,
				'mask': mask
			})
			
			# Check node mask for existing children
			for i in range(8):
				# Check individual bytes
				if mask & (1 << i):
					# Construct the childs name with 'r'+parent_id+i
					var child_name = current + str(i)
					next_nodes.append(child_name)
	f.close()
					
	return results
