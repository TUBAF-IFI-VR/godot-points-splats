extends OctreeLoader

## Load potree projects into the [OctreeNode] and [OctreeData] classes
class_name LASLoader

const color_data_offset = {
	2: 20,
	3: 28,
	5: 28,
	7: 30,
	8: 30,
	
}

var point_data_offset : int = 0

## Load a main file describing the hierarchical point cloud.
func load_metadata(filename:String) -> OctreeData:
	var octree_data = OctreeData.new()
	
	print("Loading LAS file '%s'." % filename)
	
	# The user should provide the path to a cloud.js, if not we try to fix it
	if filename.get_extension() != "las":
		return
	octree_data.base_path = filename #.get_base_dir()
	
	# Load metadata
	var file = FileAccess.open(filename, FileAccess.READ)
	
	if not file:
		push_error("Failed to open LAS file '%s'." % filename)
		return null
	
	# Get basic buffer data
	var header = file.get_buffer(96)
	if header.size() != 96:
		push_error("Failed to read header from LAS file: "+filename)
		return null
	
	# Every LAS file should start with 'LASF'
	var signature = header.slice(0,4).get_string_from_ascii()
	if signature != "LASF":
		push_error("Wrong signature. %s is not a valid LAS file!" % filename)
		return null
	
	# Check the LAS version
	var version = 0.0
	version += header[24]
	version += 0.1*header[25]
	print("Detected LAS version %.1f." % version)
	
	# Now we check the actual header size...
	var header_size = file.get_16()
	if header_size <= 0:
		push_error("Invalid header size '%d' in file %s !" % [header_size,filename])
		return null
	
	file.seek(0)
	header = file.get_buffer(header_size)
	if header.size() != header_size:
		push_error("Failed to read header. %s is not a valid LAS file!" % filename)
		return null
		
	# Read legacy point count first
	octree_data.point_count = header.decode_u32(107)
	if octree_data.point_count == 0:
		# Try to read the LAS 1.4 64bit point count
		if header_size > 255:
			octree_data.point_count = header.decode_u64(247)
		else:
			push_error("Invalid point count detected! Legacy point count is zero but there is no\
				LAS 1.4 header either!")
	
	# TODO: consider that Godot uses 32bit floats only!
	# Read scale and offset
	octree_data.scale.x = header.decode_double(131)
	octree_data.scale.y = header.decode_double(139)
	octree_data.scale.z = header.decode_double(147)
	octree_data.offset.x = header.decode_double(155)
	octree_data.offset.y = header.decode_double(163)
	octree_data.offset.z = header.decode_double(171)
	
	# Read point cloud extends
	var min : Vector3
	var max : Vector3
	
	min.x = header.decode_double(155)
	min.y = header.decode_double(163)
	min.z = header.decode_double(171)
	max.x = header.decode_double(179)
	max.y = header.decode_double(187)
	max.z = header.decode_double(195)
	
	octree_data.aabb = AABB(min, max-min)
	
	# Check data format
	point_data_offset = header.decode_u32(96)
	var point_format = header[104]
	var point_record_len = header.decode_u16(105)
	
	octree_data.format["point_format"] = point_format
	octree_data.point_bytes = point_record_len
	octree_data.attributes["intensity"] = true
	if point_format == 2 or point_format == 3:
		octree_data.attributes["color"] = true
	
	print("Detected point format #%d." % point_format)
	
	file.close()
	
	return octree_data

## Load a subfile that describes the hierarchy of a new branch (or the root).
func load_hierarchy(node:OctreeNode) -> bool:
	var sum_points = 0
	var current = node
	var base_aabb = current.aabb
	
	current.path = current.octree_data.base_path
	
	for i in range(8):
		var child_index = current.id+str(i)
		var child_aabb = base_aabb
		
		# Determine the correct octant
		var y = 1 if i&1 else -1
		var z = 1 if i&2 else -1
		var x = 1 if i&4 else -1
		
		# Spawn the new child node and adjust its position
		child_aabb.position = Vector3(0,0,0)
		var child:OctreeNode = OctreeNode.new(child_index, child_aabb, node.octree_data)
		
		child.position = base_aabb.size*Vector3(x,y,z)*0.5
		current.children[i] = child
		#current.loading_queue.push_back(child)
		current.add_child(child)
		
	return true

## Load the actual point cloud data and store in a single node.
func load_pointdata(node:OctreeNode) -> bool:
	var filename = node.path
	
	var file = FileAccess.open(filename, FileAccess.READ)
	if not file:
		push_error("Failed to open point cloud data file: "+filename)
		return false
		
	print("Loading %s..." % filename)
	
	node.points.resize(node.octree_data.point_count)
	if node.octree_data.attributes["color"]:
		node.colors.resize(node.octree_data.point_count)
		
	print("Expecting %d points..." % node.octree_data.point_count)
	
	file.seek(self.point_data_offset)
	for i in range(node.octree_data.point_count):
		var buffer = file.get_buffer(node.octree_data.point_bytes)
		
		var x = buffer.decode_s32(0)
		var z = buffer.decode_s32(4)
		var y = buffer.decode_s32(8)
		
		node.points[i] = Vector3(x,y,z) * node.octree_data.scale + node.octree_data.offset
		print(node.points[i])
		
		if node.octree_data.attributes["color"]:
			var r = buffer.decode_u16(node.octree_data.point_bytes-6) / float(0xFFFF)
			var g = buffer.decode_u16(node.octree_data.point_bytes-4) / float(0xFFFF)
			var b = buffer.decode_u16(node.octree_data.point_bytes-2) / float(0xFFFF)
			node.colors[i] = Color(r,g,b)
	
	file.close()
	return true
