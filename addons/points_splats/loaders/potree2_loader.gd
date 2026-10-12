extends OctreeLoader

## Load potree projects into the [OctreeNode] and [OctreeData] classes
class_name Potree2Loader

const _debug_print_node = false

## Load a main file describing the hierarchical point cloud.
func load_metadata(filename: String) -> OctreeData:
	var octree_data = OctreeData.new()

	# The user should provide the path to a cloud.js, if not we try to fix it
	if filename.get_extension() == "json":
		octree_data.base_path = filename.get_base_dir()
	else:
		octree_data.base_path = filename
		filename += "/metadata.json"

	# Load metadata
	var file = FileAccess.open(filename, FileAccess.READ)

	if not file:
		push_error("Failed to open metadata file: " + filename)
		return null

	var metadata = JSON.parse_string(file.get_as_text())
	file.close()

	# Apply relevant values to provided properties
	octree_data.format["version"] = float(metadata["version"])
	octree_data.metadata["name"] = metadata["name"]
	octree_data.metadata["description"] = metadata["description"]
	octree_data.point_count = metadata["points"]
	octree_data.spacing = metadata["spacing"]
	octree_data.metadata["projection"] = metadata["projection"]
	var scale = metadata["scale"]
	octree_data.scale = Vector3(scale[0], scale[2], scale[1])

	var hierarchy = metadata["hierarchy"]
	for h in hierarchy:
		octree_data.format[h] = hierarchy[h]
	octree_data.format["encoding"] = metadata["encoding"]
	
	# Convert the bounding boxes into Godot AABBs (swap y and z coordinates)
	var bb = metadata["boundingBox"]
	var bb_min = Vector3(
		bb["min"][0],
		bb["min"][2],
		bb["min"][1],
	)
	var bb_max = Vector3(
		bb["max"][0],
		bb["max"][2],
		bb["max"][1],
	)
	octree_data.aabb = get_valid_aabb(bb_min, bb_max)
	octree_data.aabb_tight = octree_data.aabb

	# We start with expected byte count of 0
	octree_data.point_bytes = 0

	# Walk through the available point attributes and calculate byte count
	var byte_offset: int = 0
	for a in metadata["attributes"]:
		var name = a["name"]
		octree_data.point_bytes += a["size"]
		
		var attr_data = OctreeData.Attribute.new(name, a["type"], a["num_elements"], a["element_size"])
		
		if name == "position":
			print("position uses "+a["type"])
		elif name == "rgb":
			print("color uses "+a["type"])
			octree_data.has_attribute["color"] = true
			self.offsets["color"] = byte_offset
		elif name == "intensity":
			octree_data.has_attribute["intensity"] = true
		elif name == "normal":
			octree_data.has_attribute["normal"] = true
			
		octree_data.attributes["name"] = attr_data
		byte_offset += a["size"]

	# DEBUG:
	#print(octree_data.point_bytes, octree_data.attributes)

	return octree_data


## Load a subfile that describes the hierarchy of a new branch (or the root).
func load_hierarchy(node: OctreeNode) -> bool:
	var filename = node.octree_data.base_path + "/hierarchy.bin"
	var file = FileAccess.open(filename, FileAccess.READ)
	if not file:
		push_error("Failed to open hierarchy file: "+filename)
		return false
	
	# We read the file in chunks of 128 nodes
	const bytes_per_node: int = 22
	const chunk_size: int = 128 * bytes_per_node
	var chunk_offset: int = 0
	
	# Load all nodes into a flat array, similar to Potree 2.0+
	var nodes: Array[OctreeNode] = []
	var i: int = 0
	nodes.resize(file.get_length() / bytes_per_node)
	nodes[0] = node

	if node.spacing == 0.0:
		node.spacing = node.octree_data.spacing
	
	# Initialization of node children uses a separate index
	var node_pos: int = 1
	
	# Load all nodes from the hierarchy file
	# Potree may integrate proxy nodes to represent deeper levels for later loading
	var buffer: PackedByteArray
	buffer = file.get_buffer(chunk_size)
	var buffer_len: int = buffer.size()
	var chunk_nodes: int = buffer_len / bytes_per_node
	var sum_nodes: int = chunk_nodes
	var sum_points: int = 0

	# Loop until all chunks have been processed
	while chunk_nodes > 0:
		var current = nodes[i]
		var type = buffer.decode_u8(chunk_offset)
		var node_mask = buffer.decode_u8(chunk_offset + 1)
		current.num_points = buffer.decode_u32(chunk_offset + 2)
		current.byte_offset = buffer.decode_s64(chunk_offset + 6)
		current.byte_size = buffer.decode_s64(chunk_offset + 14)
		
		# According to Potree source this fixes an issue with invalid files:
		if current.byte_size == 0:
			current.num_points = 0
			
		# Process children only if it isn't a proxy node
		if type != 2:
			var base_aabb = current.aabb
			base_aabb.size *= 0.5
			sum_points += current.num_points

			for index in 8:
				if node_mask & (1 << index):
					# Create a new child node
					var child: OctreeNode = OctreeNode.new(
						current.id + str(index),
						base_aabb,
						node.octree_data,
					)
					child.spacing = current.spacing * 0.5

					# Determine the correct octant
					var y = 1 if i & 1 else -1
					var z = 1 if i & 2 else -1
					var x = 1 if i & 4 else -1

					# Add child to its parent
					child.position = base_aabb.size * Vector3(x, y, z) * 0.5
					current._data_mutex.lock()
					current.children[i] = child
					current.loading_queue.push_back(child)
					current.add_child(child)
					current._data_mutex.unlock()

					nodes[node_pos] = child
					node_pos += 1
		
		# Read next chunk
		i += 1
		chunk_offset += bytes_per_node
		if chunk_offset >= chunk_size:
			chunk_offset = 0
			buffer = file.get_buffer(chunk_size)
			buffer_len = buffer.size()
			chunk_nodes = buffer_len / bytes_per_node
			sum_nodes += chunk_nodes
		else:
			chunk_nodes -= 1

	var extra_bytes = 0
	var _last_byte = -1
	while !file.eof_reached():
		_last_byte = file.get_8()
		extra_bytes += 1

	# Validate the binary file
	if extra_bytes != 0:
		push_error(
			"Invalid binary file size in '%s', %d bytes left to read!"
			% [filename, extra_bytes - 1]
		)

	if sum_nodes < nodes.size():
		push_error("Still %d unread nodes left for file '%s'!" % [nodes.size()-sum_nodes, filename])

	file.close()

	print("Finished parsing hierarchy file with %d points in %d nodes." % [sum_points, sum_nodes])
	node.octree_data.point_count += sum_points
	
	return true


## Load the actual point cloud data and store in a single node.
func load_pointdata(node: OctreeNode) -> bool:
	var filename = node.octree_data.base_path + "/octree.bin"

	var file = FileAccess.open(filename, FileAccess.READ)
	if not file:
		push_error("Failed to open point cloud data file: " + filename)
		return false

	file.seek(node.byte_offset)
	var buffer: PackedByteArray = file.get_buffer(node.byte_size)
	var byte_per_point = node.byte_size / node.num_points

	# Create and resize the necessary data arrays
	node._data_mutex.lock()
	node.points = PackedVector3Array()
	node.points.resize(node.num_points)
	if node.octree_data.attributes["color"]:
		node.colors = PackedColorArray()
		node.colors.resize(node.num_points)
	if node.octree_data.attributes["normal"]:
		node.normals = PackedVector3Array()
		node.normals.resize(node.num_points)
	node._data_mutex.unlock()

	var x = 0.0
	var y = 0.0
	var z = 0.0
	var pos_offset: Vector3 = node.octree_data.offset - node.aabb.size*0.5
	var byte_pos: int
	var r = 0.0
	var g = 0.0
	var b = 0.0
	var color_byte_offset = self.offsets["color"]
	var color_scale: float = 1.0 / 0xFFFF

	for i in node.num_points:
		byte_pos = i*byte_per_point
		x = buffer.decode_s32(byte_pos)
		z = buffer.decode_s32(byte_pos+4)
		y = buffer.decode_s32(byte_pos+8)
		node.points[i] = Vector3(x,y,z) * node.octree_data.scale + pos_offset

		if node.octree_data.attributes["color"]:
			r = buffer.decode_u16(byte_pos+color_byte_offset) * color_scale
			g = buffer.decode_u16(byte_pos+color_byte_offset+2) * color_scale
			b = buffer.decode_u16(byte_pos+color_byte_offset+4) * color_scale
			node.colors[i] = Color(r,g,b).srgb_to_linear()
	
	return false
