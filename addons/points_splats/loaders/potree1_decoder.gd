extends RefCounted
## This is a helper class used by the actual [PotreeLoader] to load legacy Potree 1.7 and 1.8 datasets.


## Run an optional function to analyze the octree hierarchy and generate text output.
var _debug_analyze_hrc = false

## Enable additional output during point loading for debugging.
var _debug_print = false


## Read a single hrc file and return the content
## For debugging.
static func analyze_hrc(hrc_path: String) -> Array:
	var file = FileAccess.open(hrc_path, FileAccess.READ)
	if not file:
		push_error("Failed to open hierarchy file: " + hrc_path)
		return []

	var next_nodes = ["r"]
	var results = []

	if file.is_open():
		while len(next_nodes) > 0:
			if file.eof_reached():
				print("Error: reached end of hrc file before all nodes have been read!")
				break
			var current = next_nodes.pop_front() # FIFO queue

			# Read node data: 1 byte mask and 4 byte point count
			var mask = file.get_8()
			var num_points = file.get_32()

			results.append({ 'name': current, 'points': num_points, 'mask': mask })

			# Check node mask for existing children
			for i in range(8):
				# Check individual bytes
				if mask & (1 << i):
					# Construct the childs name with 'r'+parent_id+i
					var child_name = current + str(i)
					if len(child_name) <= 6:
						next_nodes.push_back(child_name)

	var extra_bytes = 0
	var _last_byte = -1
	while !file.eof_reached():
		_last_byte = file.get_8()
		extra_bytes += 1

	# Validate the binary file
	if extra_bytes != 1:
		print("Invalid binary file size in '%s', %d bytes left to read!" % [hrc_path, extra_bytes])

	if len(next_nodes) > 0:
		print("Still %d unread nodes left for file '%s'!" % [len(next_nodes), hrc_path])

	file.close()

	return results


## Initialize the decoder with optional debugging options.
func _init(debug_analyze_hrc: bool = false, debug_print: bool = false) -> void:
	_debug_analyze_hrc = debug_analyze_hrc
	_debug_print = debug_print
	
	
## Load details from the metadata json that are specific to legacy Potree datasets.
func load_attributes(metadata: Dictionary, octree_data: OctreeData) -> bool:
	
	# Potree the 1.7 format is organized in different sub directories depending on step_size
	octree_data.data_dir = octree_data.base_path + "/" + metadata["octreeDir"] + "/r/"
	octree_data.format["step_size"] = metadata["hierarchyStepSize"]

	# We have to calculate the correct number of bytes per point
	# Position is always expected, we start with 0 anyway and check available attributes
	var byte_offset = 0
	
	if not "POSITION_CARTESIAN" in metadata["pointAttributes"]:
		push_error("No point position attribute could be found in the Potree metadata!")
		return false

	# Walk through the available point attributes and calculate byte count
	var attr_data
	var name = ""
	var type = ""
	var num_elements = 0
	var element_size = 0
	for a in metadata["pointAttributes"]:
		name = a
		
		match a:
			"POSITION_CARTESIAN":
				# We expect 3 floats per point (3*4 bytes)
				octree_data.has_attribute["position"] = true
				name = "position"
				type = "float"
				num_elements = 3
				element_size = 4
			"COLOR_PACKED":
				octree_data.has_attribute["color"] = true
				name = "color"
				type = "uint32"
				num_elements = 1
				element_size = 4
			"INTENSITY":
				octree_data.has_attribute["intensity"] = true
				name = "intensity"
				type = "uint16"
				num_elements = 1
				element_size = 2
			"NORMAL_SPHEREMAPPED":
				octree_data.has_attribute["normal"] = true
				octree_data.format["normal_encoding"] = a
				if not "normal" in octree_data.attributes:
					name = "normal"
				type = "uint8"
				num_elements = 2
				element_size = 1
			"NORMAL_OCT16":
				octree_data.has_attribute["normal"] = true
				octree_data.format["normal_encoding"] = a
				if not "normal" in octree_data.attributes:
					name = "normal"
				type = "uint8"
				num_elements = 2
				element_size = 1
			"CLASSIFICATION":
				octree_data.has_attribute["class"] = true
				type = "uint8"
				num_elements = 1
				element_size = 1

		attr_data = OctreeData.Attribute.new(name, type, num_elements, element_size)
		attr_data.byte_offset = byte_offset
		byte_offset += num_elements*element_size
		octree_data.attributes[name] = attr_data

	# Store the calculated total nymber of used bytes per point
	octree_data.point_bytes = byte_offset
	
	# Apply additional attribute values
	octree_data.attributes["position"].offset[0] = octree_data.offset.x
	octree_data.attributes["position"].offset[1] = octree_data.offset.y
	octree_data.attributes["position"].offset[2] = octree_data.offset.z
	octree_data.attributes["position"].scale[0] = octree_data.scale.x
	octree_data.attributes["position"].scale[1] = octree_data.scale.y
	octree_data.attributes["position"].scale[2] = octree_data.scale.z

	# DEBUG:
	#print(octree_data.point_bytes, octree_data.attributes)

	# Convert the bounding boxes into Godot AABBs (swap y and z coordinates)
	var bb_min = Vector3(
		metadata["boundingBox"]["lx"],
		metadata["boundingBox"]["lz"],
		metadata["boundingBox"]["ly"],
	)
	var bb_max = Vector3(
		metadata["boundingBox"]["ux"],
		metadata["boundingBox"]["uz"],
		metadata["boundingBox"]["uy"],
	)
	octree_data.aabb = OctreeLoader.get_valid_aabb(bb_min, bb_max)

	bb_min = Vector3(
		metadata["tightBoundingBox"]["lx"],
		metadata["tightBoundingBox"]["lz"],
		metadata["tightBoundingBox"]["ly"],
	)
	bb_max = Vector3(
		metadata["tightBoundingBox"]["ux"],
		metadata["tightBoundingBox"]["uz"],
		metadata["tightBoundingBox"]["uy"],
	)
	octree_data.aabb_tight = OctreeLoader.get_valid_aabb(bb_min, bb_max)

	# TODO: check for errors

	# DEBUG:
	if _debug_analyze_hrc:
		var hrc_file = octree_data.base_path + "/data/r/r.hrc"
		var hrc_data = self.analyze_hrc(hrc_file)
		var hrc_output = FileAccess.open("hrc_analysis.txt", FileAccess.WRITE)
		print("Analyzing hierarchy file '%s'" % hrc_file)
		print("--------------------")
		for n in hrc_data:
			var output = "%5s | %8d | " % [n["name"], n["points"]]
			for i in range(8):
				output += "1" if n["mask"] & (1 << i) else "0"
			hrc_output.store_line(output)
		hrc_output.close()

	return true


## Load a subfile that describes the hierarchy of a new branch (or the root).
func load_hierarchy(node: OctreeNode) -> bool:
	# We start with the main hrc file and may have to traverse the tree for
	# additional ones
	var hrc_files = [[node, 1]]
	var hrc_count = 0
	var sum_points = 0
	var hrc_nodes = 1

	# We may have to repeat hrc parsing for deeper branches
	while len(hrc_files) > 0:
		var hrc = hrc_files.pop_front()
		var root = hrc[0]
		var step = hrc[1]

		var filename = root.path + ".hrc"
		var file = FileAccess.open(filename, FileAccess.READ)
		if not file:
			push_error("Failed to open hierarchy file: "+filename)
			return false

		# We start with the root node of the new branch
		var next_nodes = [root]
		var hrc_points = 0
		var step_size = node.octree_data.format["step_size"]

		# HRC files are small, we read it all at once
		var buffer: PackedByteArray = file.get_buffer(file.get_length())
		var buffer_size: int = buffer.size()
		var buffer_offset: int = 0
		file.close()

		# Walk through the hrc file and push necessary subnodes into the queue
		while len(next_nodes) > 0:
			if buffer_offset >= buffer_size:
				print("Error: reached end of hrc file before all nodes have been read!")
				break
			var current: OctreeNode = next_nodes.pop_front()

			var node_mask = buffer.decode_u8(buffer_offset)
			var point_count = buffer.decode_u32(buffer_offset+1)
			buffer_offset += 5

			var base_aabb = current.aabb
			base_aabb.size *= 0.5
			hrc_points += point_count

			# Check the node mask and spawn necessary subnodes as children
			for i in range(8):
				if node_mask & (1 << i):
					var child_index = current.id + str(i)

					var child_aabb = base_aabb

					# Determine the correct octant
					var y = 1 if i & 1 else -1
					var z = 1 if i & 2 else -1
					var x = 1 if i & 4 else -1

					# Spawn the new child node and adjust its position
					child_aabb.position = Vector3(0, 0, 0) #+= base_aabb.size*Vector3(x,y,z)
					var child: OctreeNode = OctreeNode.new(
						child_index,
						child_aabb,
						node.octree_data,
					)
					#child.depth = current.depth+1
					child.path = current.path.get_base_dir().path_join(child_index)

					if current.depth + 1 == step_size * step:
						var folder_start: int = 1 + ((step - 1) * step_size)
						var folder_name: String = child.id.substr(folder_start, step_size)

						child.path = current.path.get_base_dir() \
								.path_join(folder_name) \
								.path_join(child_index)

						hrc_files.push_back([child, step + 1])

					if current.depth < step_size * step:
						next_nodes.push_back(child)

					child.position = base_aabb.size * Vector3(x, y, z) * 0.5
					current._data_mutex.lock()
					current.children[i] = child
					current.loading_queue.push_back(child)
					current.add_child(child)
					current._data_mutex.unlock()
					hrc_nodes += 1

		var extra_bytes = 0
		var last_byte = -1
		while buffer_offset != buffer_size:
			last_byte = file.get_8()
			extra_bytes += 1

		# Validate the binary file
		if extra_bytes != 0:
			push_error(
				"Invalid binary file size in '%s', %d bytes left to read!"
				% [filename, extra_bytes]
			)

		if len(next_nodes) > 0:
			push_error("Still %d unread nodes left for file '%s'!" % [len(next_nodes), filename])

		#print("Parsed hierarchy file '%s' with %d points in total." % [filename,hrc_points])
		hrc_count += 1
		sum_points += hrc_points
		# End of single hrc file parsing
		
	if node.octree_data.format.get("missing_point_count", false):
		node.octree_data.point_count += sum_points
	node.octree_data.format["hierarchy_files"] = hrc_count
	node.octree_data.node_count = hrc_nodes

	return true


## Load the actual point cloud data and store in a single node.
func load_pointdata(node: OctreeNode) -> bool:
	var filename = node.path
	if not filename.get_extension() == "bin":
		filename += ".bin"

	var file = FileAccess.open(filename, FileAccess.READ)
	if not file:
		push_error("Failed to open point cloud data file: " + filename)
		return false

	# For the following line, integer division is desired
	@warning_ignore("integer_division") var point_count = file.get_length() / node \
			.octree_data \
			.point_bytes

	# Create and resize the necessary data arrays
	node._data_mutex.lock()
	node.points = PackedVector3Array()
	node.points.resize(point_count)
	if node.octree_data.has_attribute["color"]:
		node.colors = PackedColorArray()
		node.colors.resize(point_count)
	if node.octree_data.has_attribute["normal"]:
		node.normals = PackedVector3Array()
		node.normals.resize(point_count)
	node._data_mutex.unlock()

	# Prepare variables for binary reading
	var points_read = 0
	var point_bytes = node.octree_data.point_bytes
	var chunk_points = min(50000, point_count)
	var chunk_size = chunk_points * point_bytes
	var expected_bytes = point_count * point_bytes
	var version: float = node.octree_data.format["version"]

	# We use a lot of local variables to reduce dictionary calls in the loop
	var x := 0.0; var y := 0.0; var z := 0.0
	var scalex = node.octree_data.scale.x
	var scaley = node.octree_data.scale.y
	var scalez = node.octree_data.scale.z
	var aabb_size: Vector3 = node.aabb.size * 0.5
	var has_color: bool = node.octree_data.has_attribute["color"]
	var has_normals: bool = node.octree_data.has_attribute["normal"]
	var nx: int = 0; var ny: int = 0
	var normal_oct16: bool = false
	var position_byte_offset = node.octree_data.attributes["position"].byte_offset
	var color_byte_offset = 0
	var normal_byte_offset = 0
	if has_color:
		color_byte_offset = node.octree_data.attributes["color"].byte_offset
	if has_normals:
		normal_byte_offset = node.octree_data.attributes["normal"].byte_offset
		if node.octree_data.format["normal_encoding"] == "NORMAL_OCT16":
			normal_oct16 = true

	var buffer: PackedByteArray = file.get_buffer(chunk_size)
	var buffer_offset: int = 0
	var buffer_size: int = buffer.size()
	if buffer.size() != chunk_size:
		push_error("Failed to read first Potree data chunk!")
		return false

	# There should be exactly point_count*point_bytes bytes in the file
	# TODO: check with the point count read from the hrc file to validate
	while points_read < point_count:
		# Read the next chunk
		for i in range(chunk_points):
			buffer_offset = i*point_bytes
			if buffer_offset >= buffer_size:
				push_error("Failed to read point: reached end of file!")

			# TODO: not sure about the correct interpretation for specific versions
			if version  > 1.3:
				x = buffer.decode_s32(buffer_offset+position_byte_offset) * scalex
				z = buffer.decode_s32(buffer_offset+position_byte_offset+4) * scaley
				y = buffer.decode_s32(buffer_offset+position_byte_offset+8) * scalez
			else:
				x = buffer.decode_float(buffer_offset+position_byte_offset)
				z = buffer.decode_float(buffer_offset+position_byte_offset+4)
				y = buffer.decode_float(buffer_offset+position_byte_offset+8)

			# Arrange the points around the AABB's center
			node.points[points_read] = Vector3(x, y, z) - aabb_size

			# Read color values if they exist in the bin file
			if has_color:
				node.colors[points_read] = Color(
					buffer.decode_u8(buffer_offset+color_byte_offset) / 255.0,
					buffer.decode_u8(buffer_offset+color_byte_offset+1) / 255.0,
					buffer.decode_u8(buffer_offset+color_byte_offset+2) / 255.0,
					1.0, #file.get_8()/255.0
				).srgb_to_linear()
			# Read the normal vector if present
			if has_normals:
				nx = buffer.decode_u8(buffer_offset+normal_byte_offset)
				ny = buffer.decode_u8(buffer_offset+normal_byte_offset+1)
				
				# We support different normal vector encodings
				if normal_oct16:
					node.normals[points_read] = _decode_normal_oct16(nx, ny)
				else:
					node.normals[points_read] = _decode_normal_sphere(nx, ny)

			points_read += 1

		# Prepare next chunk
		if points_read >= point_count:
			break

		chunk_points = min(chunk_points, point_count - points_read)
		chunk_size = chunk_points * point_bytes
		buffer = file.get_buffer(chunk_size)
		if buffer.size() != chunk_size:
			push_error("Failed to read PLY chunk at point %d!" % points_read)
			return false
		buffer_offset = 0

	# Check if all bytes have been read to validate the data
	# There usually is a single 0 byte at the end
	var extra_bytes = 0
	var last_byte = -1
	while !file.eof_reached():
		last_byte = file.get_8()
		extra_bytes += 1
	file.close()

	node.octree_data.loaded_point_count += point_count

	# Validate the binary file
	if extra_bytes != 1 or last_byte != 0:
		push_error(
			"Invalid binary file size in '%s', %d bytes left to read!"
			% [filename, extra_bytes - 1]
		)

	return true


## Convert the 2 byte integer representation into a correct normal vector.
func _decode_normal_sphere(x: int, y: int) -> Vector3:
	# Based on Potree BinaryDecoderWorker
	# https://github.com/potree/potree/blob/develop/src/workers/BinaryDecoderWorker.js
	var nx = (x / 255.0) * 2.0 - 1.0
	var ny = (y / 255.0) * 2.0 - 1.0
	var l = max(0.0, 1.0 - (nx * nx + ny * ny))
	var nz = l
	nz = l
	nx = nx * sqrt(l)
	ny = ny * sqrt(l)

	# Convert from 0/1 range to -1/+1
	nx = nx * 2.0
	ny = ny * 2.0
	nz = nz * 2.0 - 1.0

	return Vector3(nx, nz, ny).normalized()


func _decode_normal_oct16(bx: int, by: int) -> Vector3:
	var u = (bx / 255.0) * 2.0 - 1.0
	var v = (by / 255.0) * 2.0 - 1.0

	var z = 1.0 - abs(u) - abs(v)
	var x = 0.0
	var y = 0.0

	if z >= 0.0:
		x = u
		y = v
	else:
		x = -(v / sign(v) - 1.0) / sign(u)
		y = -(u / sign(u) - 1.0) / sign(v)

	return Vector3(x, z, y).normalized()
	
