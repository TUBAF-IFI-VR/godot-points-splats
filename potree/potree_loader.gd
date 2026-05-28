extends OctreeLoader

## Load potree projects into the [OctreeNode] and [OctreeData] classes
class_name PotreeLoader

## Load a main file describing the hierarchical point cloud.
func load_metadata(filename:String) -> OctreeData:
	var octree_data = OctreeData.new()
	
	# The user should provide the path to a cloud.js, if not we try to fix it
	if filename.get_extension() == "js":
		octree_data.base_path = filename.get_base_dir()
	else:
		octree_data.base_path = filename
		filename += "/cloud.js"
	
	# Load metadata
	var file = FileAccess.open(filename, FileAccess.READ)
	
	if not file:
		push_error("Failed to open metadata file: "+filename)
		return null
	
	var metadata = JSON.parse_string(file.get_as_text())
	file.close()
	
	# Apply relevant values to provided properties
	octree_data.version = float(metadata["version"])
	octree_data.data_dir = octree_data.base_path+"/"+metadata["octreeDir"]+"/r/"
	octree_data.spacing = metadata["spacing"]
	octree_data.scale = metadata["scale"]
	octree_data.step_size = metadata["hierarchyStepSize"] 
	#scale = Vector3(octree_scale, octree_scale, octree_scale)
	
	# We have to calculate the correct number of bytes per point
	# Position is always expected, start with 3 floats per point
	octree_data.point_bytes = 3*4
	
	# Walk through the available point attributes and calculate byte count
	for a in metadata["pointAttributes"]:
		#attributes[a] = true
		if a == "COLOR_PACKED":
			octree_data.attributes["color"] = true
			octree_data.point_bytes += 4
		if a == "INTENSITY":
			octree_data.attributes["intensity"] = true
			octree_data.point_bytes += 4
		elif a == "NORMAL_SPHEREMAPPED":
			octree_data.attributes["normal"] = true
			octree_data.point_bytes += 2
			
	# For debugging
	print(octree_data.point_bytes, octree_data.attributes)
	
	# Convert the bounding boxes into Godot AABBs (swap y and z coordinates)
	var bb_min = Vector3(metadata["boundingBox"]["lx"],metadata["boundingBox"]["lz"],metadata["boundingBox"]["ly"])
	var bb_max = Vector3(metadata["boundingBox"]["ux"],metadata["boundingBox"]["uz"],metadata["boundingBox"]["uy"])
	octree_data.aabb = AABB(bb_min, bb_max-bb_min)
	
	bb_min = Vector3(metadata["tightBoundingBox"]["lx"],metadata["tightBoundingBox"]["lz"],metadata["tightBoundingBox"]["ly"])
	bb_max = Vector3(metadata["tightBoundingBox"]["ux"],metadata["tightBoundingBox"]["uz"],metadata["tightBoundingBox"]["uy"])
	octree_data.aabb_tight = AABB(bb_min, bb_max-bb_min)
	
	# TODO: check for errors
	
	# DEBUG:
	var hrc_file = octree_data.base_path + "/data/r/r.hrc"
	var hrc_data = PotreeLoader.analyze_hrc(hrc_file)
	print("Analyzing hierarchy file '%s'" % hrc_file)
	print("--------------------")
	for n in hrc_data:
		var output = "%5s | %8d | " % [n["name"], n["points"]]
		for i in range(8):
			output += "1" if n["mask"] & (1<<i) else "0"
		print(output)
	
	#root = _load_hierarchy(base_path + metadata["octreeDir"])
	return octree_data

## Load a subfile that describes the hierarchy of a new branch (or the root).
func load_hierarchy(node:OctreeNode) -> bool:
	var filename = node.path+".hrc"
	var file = FileAccess.open(filename, FileAccess.READ)
	if not file:
		push_error("Failed to open hierarchy file: "+filename)
		return false
	
	# We are the root node of the new branch
	var next_nodes = [node]

	# Walk through the hrc file and push necessary subnodes into the queue
	while !file.eof_reached() and len(next_nodes) > 0:
		var current : OctreeNode = next_nodes.pop_front()
		var node_mask = file.get_8()
		var point_count = file.get_32()
		var base_aabb = current.aabb
		base_aabb.size *= 0.5
		
		# Check the node mask and spawn necessary subnodes as children
		for i in range(8):
			if node_mask & (1<<i):
				var child_index = current.id+str(i)
				if len(child_index) <= node.octree_data.step_size:
					var child_aabb = base_aabb
					
					# Determine the correct octant
					var y = 1 if i&1 else -1
					var z = 1 if i&2 else -1
					var x = 1 if i&4 else -1
					
					# Spawn the new child node and adjust its position
					child_aabb.position = Vector3(0,0,0)#+= base_aabb.size*Vector3(x,y,z)
					var child:OctreeNode = OctreeNode.new(child_index, child_aabb, node.octree_data)
					child.position = base_aabb.size*Vector3(x,y,z)*0.5
					current.children[i] = child
					current.loading_queue.push_back(child)
					current.add_child(child)
					next_nodes.push_back(child)
	
	file.close()
	return true
	
## Convert the 2 byte integer representation into a correct normal vector.
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

## Load the actual point cloud data and store in a single node.
func load_pointdata(node:OctreeNode) -> bool:
	var filename = node.path
	if not filename.get_extension() == "bin":
		filename += ".bin"
	
	var file = FileAccess.open(filename, FileAccess.READ)
	if not file:
		push_error("Failed to open point cloud data file: "+filename)
		return false
	
	# For the following line, integer division is desired
	@warning_ignore("integer_division")
	var point_count = file.get_length()/node.octree_data.point_bytes
	
	# Create and resize the necessary data arrays
	node.points = PackedVector3Array()
	node.points.resize(point_count)
	if node.octree_data.attributes["color"]:
		node.colors = PackedColorArray()
		node.colors.resize(point_count)
	if node.octree_data.attributes["normal"]:
		node.normals = PackedVector3Array()
		node.normals.resize(point_count)
	
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
		if node.octree_data.version > 1.3:
			x = file.get_32() * node.octree_data.scale
			z = file.get_32() * node.octree_data.scale
			y = file.get_32() * node.octree_data.scale
		else:
			x = file.get_float()
			z = file.get_float()
			y = file.get_float()
		
		# Arrange the points around the AABB's center
		node.points[i] = Vector3(x,y,z) - node.aabb.size*0.5
		
		# Read color values if they exist in the bin file
		if node.octree_data.attributes["color"]:
			node.colors[i] = Color(
				file.get_8()/255.0,
				file.get_8()/255.0,
				file.get_8()/255.0,
				1.0
				#file.get_8()/255.0
			)
			file.get_8()
		# Read the normal vector if present
		if node.octree_data.attributes["normal"]:
			node.normals[i] = _decode_normal(file.get_8(), file.get_8())
	
	# Check if all bytes have been read to validate the data
	# There usually is a single 0 byte at the end
	var extra_bytes = 0
	var last_byte = -1
	while !file.eof_reached():
		last_byte = file.get_8()
		extra_bytes += 1
	
	# DEBUG: print validation result
	print("Loaded %d points!" % node.points.size())
	if extra_bytes == 1 and last_byte == 0:
		print("Binary file is valid.")
	else:
		print("Invalid binary file size?")
	
	file.close()
	return true

## Read a single hrc file and return the content
## For debugging.
static func analyze_hrc(hrc_path:String) -> Array:
	var file = FileAccess.open(hrc_path,FileAccess.READ)
	if not file:
		push_error("Failed to open hierarchy file: "+hrc_path)
		return []
	
	var next_nodes = ["r"]
	var results = []
	
	if file.is_open():
		while len(next_nodes) > 0:
			if file.eof_reached():
				print("Error: reached end of hrc file before all nodes have been read!")
				break
			var current = next_nodes.pop_front() 	# FIFO queue
				
			# Read node data: 1 byte mask and 4 byte point count
			var mask = file.get_8()
			var num_points = file.get_32()
			
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
	file.close()
					
	return results
