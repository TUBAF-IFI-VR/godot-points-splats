extends RefCounted
## This is a helper class used by the actual [PotreeLoader] to load current Potree 2.x datasets.


## Run an optional function to analyze the octree hierarchy and generate text output.
var _debug_analyze_hrc = false

## Enable additional output during point loading for debugging.
var _debug_print = false


## Initialize the decoder with optional debugging options.
func _init(debug_analyze_hrc: bool = false, debug_print: bool = false) -> void:
	_debug_analyze_hrc = debug_analyze_hrc
	_debug_print = debug_print


## Load details from the metadata json that are specific to Potree 2.x datasets.
func load_attributes(metadata: Dictionary, octree_data: OctreeData) -> bool:
	
	# Check the dataset encoding
	# Hierarchy information was moved to a separate dictionary
	var hierarchy = metadata["hierarchy"]
	for h in hierarchy:
		octree_data.format[h] = hierarchy[h]
	if not "firstChunkSize" in hierarchy:
		push_error("There is no size specified for the first hierarchy chunk in the Potree metadata!")
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
	
	# TODO: aabb_tight was present in old Potree 1.x datasets, probably we can remove it...
	octree_data.aabb = OctreeLoader.get_valid_aabb(bb_min, bb_max)
	octree_data.aabb_tight = octree_data.aabb

	# We start with expected byte count of 0
	octree_data.point_bytes = 0

	# Walk through the available point attributes and calculate byte count
	var byte_offset: int = 0
	for a in metadata["attributes"]:
		var name = a["name"]
		octree_data.point_bytes += a["size"]

		# We use 'color' internally as property name instead of rgb
		# TODO: add replacement dictionary to be more flexible?
		if name == "rgb":
			name = "color"

		# Instantiate a new attribute object
		var attr_data = OctreeData.Attribute.new(name, a["type"], a["numElements"], a["elementSize"])

		# Add additional property information to the octree data
		if name == "position":
			if _debug_print:
				print("position uses " + a["type"] + " datatype")
		elif name == "color":
			if _debug_print:
				print("color uses " + a["type"] + " datatype")
			octree_data.has_attribute["color"] = true
			attr_data.byte_offset = byte_offset
		elif name == "intensity":
			octree_data.has_attribute["intensity"] = true
		elif name == "normal":
			octree_data.has_attribute["normal"] = true

		# Increment the byte offset
		octree_data.attributes[name] = attr_data
		byte_offset += a["size"]

	# DEBUG:
	if _debug_print:
		print("Point bytes:", octree_data.point_bytes)
		print("Found point attributes:", octree_data.attributes)

	return true


## Load the binary hierarchy description and extend the default root node.
func load_hierarchy(node: OctreeNode) -> bool:
	# Try to open the hierarchy file (a single binary file in Potree 2.x)
	var filename = node.octree_data.base_path + "/hierarchy.bin"
	var file = FileAccess.open(filename, FileAccess.READ)
	if not file:
		push_error("Failed to open hierarchy file: "+filename)
		return false
	
	# The information for each node is encoded within 22 bytes
	# 1. type: 1 byte (normal inner node, leaf node or proxy node for upcoming chunk data)
	# 2. child mask: 1 byte (bitmask similar to Potree 1.x)
	# 3. num points: 4 byte
	# 4. byte offset: 8  byte (offset in hierarchy.bin for proxy nodes or octree.bin for all other)
	# 5. byte size: 8 byte (size of the related data block in a .bin file)
	
	# For now we read the whole hierarchy immediately including all proxy nodes
	const bytes_per_node: int = 22
	var sum_points: int = 0
	var sum_nodes: int = 0
	var bytes_read: int = 0
	var chunk_size: int = node.octree_data.format["firstChunkSize"]
	var next_branches: Array[Dictionary] = [{
		"proxy": node,
		"offset": 0,
		"size": chunk_size,
	}]
	
	# Prepare variables
	var chunk_nodes: int = 0
	var next_nodes: Array[OctreeNode]
	var current: OctreeNode
	var buffer: PackedByteArray = file.get_buffer(chunk_size)
	var buffer_size: int = buffer.size()
	var buffer_offset: int = 0
	var chunk_pos: int
	var type: int
	var node_mask: int
	var child_aabb: AABB
	var child_index: String
	var x
	var y
	var z
	
	# Initialize root AABB center
	node.center_offset = node.aabb.size*0.5

	# Are there unprocessed proxy nodes?
	while len(next_branches) > 0:
		# Get information about the next chunk
		var branch = next_branches.pop_front()
		chunk_size = branch["size"]
		chunk_nodes = chunk_size / bytes_per_node
		file.seek(branch["offset"])
		buffer = file.get_buffer(chunk_size)
		buffer_size = buffer.size()
		buffer_offset = 0
		bytes_read += buffer_size

		# Was there enough data to read?
		if buffer_size != chunk_size:
			push_error("Failed to read hierarchy chunk of size '%d'!" % chunk_size)
			return false

		# Prepare the node array to avoid resizing during runtime
		next_nodes.resize(chunk_nodes)
		next_nodes[0] = branch["proxy"]
		chunk_pos = 1

		# Process all nodes in the current chunk
		for i in chunk_nodes:
			# Get next node form the queue
			current = next_nodes[i]
			
			# Read node data from buffer
			type = buffer.decode_u8(buffer_offset)
			node_mask = buffer.decode_u8(buffer_offset+1)
			current.point_count = buffer.decode_u32(buffer_offset+2)
			current.byte_offset = buffer.decode_u64(buffer_offset+6)
			current.byte_size = buffer.decode_u64(buffer_offset+14)
			buffer_offset += bytes_per_node
			
			# DEBUG
			if _debug_print:
				var textmask = "0x"
				for j in range(7,-1,-1):
					textmask += "1" if (node_mask & (1<<j)) else "0"
				print("id: %s, type: %d, mask: %s, point_count: %d" % 
						[current.id, type, textmask, current.point_count])
			
			# Additional check for faulty datasets
			if current.byte_size == 0:
				current.point_count = 0
			
			# We don't count proxy nodes for now
			if type != 2:
				sum_points += current.point_count

			# Process child nodes of inner octree nodes (type 0)
			if type == 0:
				child_aabb = current.aabb
				child_aabb.size *= 0.5
				
				# Check the node mask and spawn necessary subnodes as children
				for j in range(8):
					if node_mask & (1 << j):
						child_index = current.id + str(j)

						# Determine the correct octant
						y = 1 if j & 1 else -1
						z = 1 if j & 2 else -1
						x = 1 if j & 4 else -1

						# Create the new child node
						var child: OctreeNode = OctreeNode.new(
							child_index,
							child_aabb,
							node.octree_data,
						)
						
						child.path = current.path
						child.position = child_aabb.size * Vector3(x, y, z) * 0.5
						child.center_offset = current.center_offset + child.position
						child.spacing = current.spacing * 0.5

						# Lock the mutex before writing data to the queue
						current._data_mutex.lock()
						current.children[j] = child
						current.loading_queue.push_back(child)
						current.add_child(child)
						current._data_mutex.unlock()
						next_nodes[chunk_pos] = child
						chunk_pos += 1
			# Push proxy nodes to the queue of unprocessed branches
			elif type == 2:
				# Add proxy node to the queue
				next_branches.push_back({
					"proxy": current,
					"offset": current.byte_offset,
					"size": current.byte_size,
				})
			# Leaf nodes need no further processing

		sum_nodes += chunk_nodes
	
	# Check if all bytes have been read to validate the data
	if bytes_read != file.get_length():
		push_error(
			"Parsing of hierarchy '%s' is incomplete, %d bytes left to read!"
			% [filename, file.get_length() - bytes_read]
		)
	file.close()

	# Update the information in [OctreeData] if necessary
	if node.octree_data.format.get("missing_point_count", false):
		node.octree_data.point_count = sum_points
	elif node.octree_data.point_count != sum_points:
		push_warning("The point count reported by the Potree hierarchy differs from the point count"
					+" specified in the metadata!")
	node.octree_data.format["hierarchy_files"] = 1
	node.octree_data.node_count = sum_nodes
	
	return true


## Load the actual point cloud data for a single node.
func load_pointdata(node: OctreeNode) -> bool:
	# The data of all points is stored in the same binary file for Potree 2.x
	var filename = node.octree_data.base_path + "/octree.bin"

	var file = FileAccess.open(filename, FileAccess.READ)
	if not file:
		push_error("Failed to open point cloud data file: " + filename)
		return false

	# Go to the first byte of the requested chunk
	file.seek(node.byte_offset)
	var buffer: PackedByteArray = file.get_buffer(node.byte_size)
	# Was there enough data to read?
	if buffer.size() != node.byte_size:
		push_error("Failed to read point data chunk of size '%d'!" % node.byte_size)
		return false

	# Create and resize the necessary data arrays
	node._data_mutex.lock()
	node.points = PackedVector3Array()
	node.points.resize(node.point_count)
	if node.octree_data.has_attribute["color"]:
		node.colors = PackedColorArray()
		node.colors.resize(node.point_count)
	if node.octree_data.has_attribute["normal"]:
		node.normals = PackedVector3Array()
		node.normals.resize(node.point_count)
	node._data_mutex.unlock()

	# Prepare variables
	var point_bytes = node.octree_data.point_bytes
	var byte_pos: int
	var pos_scale: Vector3 = node.octree_data.scale
	var pos_offset: Vector3 = node.octree_data.offset - node.center_offset
	var x = 0.0
	var y = 0.0
	var z = 0.0
	var r = 0.0
	var g = 0.0
	var b = 0.0
	var color_byte_offset = node.octree_data.attributes["color"].byte_offset
	var color_scale: float = 1.0 / 0xFFFF

	# Decode position and color data for all points of the current chunk
	for i in node.point_count:
		byte_pos = i*point_bytes
		x = buffer.decode_s32(byte_pos)
		z = buffer.decode_s32(byte_pos+4)
		y = buffer.decode_s32(byte_pos+8)
		node.points[i] = Vector3(x,y,z) * pos_scale + pos_offset

		if node.octree_data.attributes["color"]:
			r = buffer.decode_u16(byte_pos+color_byte_offset) * color_scale
			g = buffer.decode_u16(byte_pos+color_byte_offset+2) * color_scale
			b = buffer.decode_u16(byte_pos+color_byte_offset+4) * color_scale
			node.colors[i] = Color(r,g,b).srgb_to_linear()
	
	file.close()
	
	node.octree_data.loaded_point_count += node.point_count
	
	return true
