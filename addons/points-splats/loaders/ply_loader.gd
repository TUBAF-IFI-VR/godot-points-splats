extends OctreeLoader

## Load potree projects into the [OctreeNode] and [OctreeData] classes.
class_name PLYLoader

## Binary or ASCII encoded.
var binary = false

## Little or big endian.
var big_endian = false

## Offset to point data from file start (always in bytes).
var point_data_offset: int = 0

## Array of contained elements.
## 
## Each element stores property information with datatypes, offsets and size in bytes.
var elements: Dictionary = {}

## If there are no property lists, we can simplify the loading process.
var has_property_lists = false

## Datatype cases for faster loading.
enum DatatypeCase {NONE=0, FLOAT, FLOAT_AND_UCHAR}
var datatype_case: DatatypeCase = DatatypeCase.NONE

## Are integer values used for colors?.
var integer_colors = false

## Degree of spherical harmonics (if used).
var sh_degree: int = -1

## Spherical harmonics coefficients (normalization factors).
const SH_C0 = 0.28209479177387814
const SH_C1 = 0.4886025119029199

## Line entry or byte offsets for the most common properties (position, normal, color).
var offsets: Dictionary = {
	"x": -1,
	"y": -1,
	"z": -1,
	"nx": -1,
	"ny": -1,
	"nz": -1,
	"r": -1,
	"g": -1,
	"b": -1,
}


## Scalar types in PLY files.
enum PropertyType { CHAR, UCHAR, SHORT, USHORT, INT, UINT, FLOAT, DOUBLE, LIST }

## Predifined list for integer properties.
const IntegerTypes: Array = [PropertyType.CHAR, PropertyType.UCHAR, PropertyType.SHORT,\
							PropertyType.USHORT, PropertyType.INT, PropertyType.UINT]

## Map a string encoded type to the enum.
const TypeMap: Dictionary = {
	"char": PropertyType.CHAR,
	"uchar": PropertyType.UCHAR,
	"short": PropertyType.SHORT,
	"ushort": PropertyType.USHORT,
	"int": PropertyType.INT,
	"uint": PropertyType.UINT,
	"float": PropertyType.FLOAT,
	"double": PropertyType.DOUBLE,
}


## Number of bytes for a specific type string.
const ByteSize = {
	PropertyType.CHAR: 1,
	PropertyType.UCHAR: 1,
	PropertyType.SHORT: 2,
	PropertyType.USHORT: 2,
	PropertyType.INT: 4,
	PropertyType.UINT: 4,
	PropertyType.FLOAT: 4,
	PropertyType.DOUBLE: 8,
}


## Helper function to check present data types.
# Are all specified properties floats?
func _all_of_type(properties: Dictionary, keys: Array[String], type: PropertyType) -> bool:
	for key in keys:
		if key in properties and properties[key]["type"] != type:
			return false
	return true
	
## Read the PLY header into an array of lines.
func _read_header(file: FileAccess) -> Array[String]:
	var header: Array[String]
	
	# File header should start with a 'ply' line
	if file.get_line().strip_edges().to_lower() != "ply":
		push_error("Invalid PLY header, expected 'ply' at file begin!")
		return header

	# Read ASCII header lines
	while not file.eof_reached():
		var line = file.get_line().strip_edges()
		if line == "end_header":
			break
		header.append( line )

	if file.eof_reached():
		push_error("Reached EOF before header end was found!")
		header.clear()

	return header


## Parse information about a single property in the PLY header.
func _parse_header_property(line: String, properties: Dictionary) -> void:
	# Use property name as key and store its datatype
	var p = line.split(" ", false)

	# Adapt property name for internal processing
	var name = p[2]

	# Found spherical harmonic value?
	if name in ["f_dc_0", "f_dc_1", "f_dc_2"]:
		sh_degree = 0

	if name == "red" or (name == "f_dc_0" and "r" not in properties):
		name = "r"
	elif name == "green" or (name == "f_dc_1" and "g" not in properties):
		name = "g"
	elif name == "blue" or (name == "f_dc_2" and "b" not in properties):
		name = "b"
	
	# Lists have to be parsed differently than scalar values
	if p.size() >= 5 and p[1] == "list":
		name = p[4]

	# Property already in dict
	if name in properties:
		push_warning("Property '%s' occurs multiple times in PLY file!" % name)

	# Is it a list?
	if p.size() >= 5 and p[1] == "list":
		var len_type = TypeMap.get(p[2], -1)
		var data_type = TypeMap.get(p[3], -1)
		if len_type < 0 or len_type not in IntegerTypes:
			push_error("Invalid length type for list property '%s'" % name)
			return
		if data_type < 0:
			push_error("Invalid data type for list property '%s'" % name)
			return
		
		properties[name] = {
			"type":PropertyType.LIST,
			"len_type":len_type,
			"data_type":data_type,
		}
	elif p[1] not in TypeMap:
		push_error("Unknown data type '%s' in PLY file!" % p[1])
	else:
		properties[name] = {"type":TypeMap[p[1]]}


## Check the header and prepare dictionary of properties.
func _parse_header(header: Array[String], octree_data: OctreeData) -> bool:
	# Analyze header
	var properties: Dictionary = {}
	var element_name: String = ""
	var format_read: bool = false

	for line in header:
		# Check binary/ascii format and version
		if line.begins_with("format"):
			var format = line.to_lower().split(" ", false)

			if format.size() < 2:
				push_error("Invalid ply format line in header!")
				return false

			# Check the encoding for endianess and binary/ASCII
			octree_data.format["encoding"] = format[1]
			if format[1] in ["binary_little_endian", "binary_big_endian"]:
				binary = true
			elif format[1] != "ascii":
				push_error("No valid file encoding found in header!")
				return false
			if format[1] == "binary_big_endian":
				big_endian = true

			if format.size() > 2:
				octree_data.format["ply_version"] = format[2]
			format_read = true

		# We only need the vertex element but may have to read the others as well
		elif line.begins_with("element"):
			# Store previously collected properties
			if not element_name.is_empty():
				elements[element_name] = properties
				properties = {}
			# Start new element section
			var element = line.split(" ", false)
			element_name = element[1]
			properties["__count__"] = element[2].to_int()

		# Check available properties
		elif line.begins_with("property"):
			_parse_header_property(line, properties)

	if not format_read:
		push_error("Failed to find file format in the PLY header!")
		return false
	if not element_name.is_empty():
		elements[element_name] = properties

	return true


## Skip all data before the first vertex elements and check if there are lists.
func _skip_non_vertex_properties(file: FileAccess) -> void:
	# Are there property lists to check during loading?
	# Where does the point data start?
	var keys = elements.keys()
	var e = keys.pop_front()
	while e:
		for name in elements[e]:
			if name == "__count__":
				continue
			var p = elements[e][name]
			# Lists in the vertex data make the loading process more complex!
			if e == "vertex" and p["type"] == PropertyType.LIST:
				has_property_lists = true
				break
		if e == "vertex":
			break

		# Advance the file cursor if necessary
		# We skip all elements before the vertex data
		if binary:
			for name in elements[e]:
				if name == "__count__":
					continue

				var p = elements[e][name]
				# List or scalar value?
				if p["type"] == PropertyType.LIST:
					var len = 0
					match p["len_type"]:
						PropertyType.CHAR,PropertyType.UCHAR:
							len = file.get_8()
						PropertyType.SHORT,PropertyType.USHORT:
							len = file.get_16()
						PropertyType.INT,PropertyType.UINT:
							len = file.get_32()
					file.get_buffer(len * ByteSize[p["len_type"]])
				else:
					file.get_buffer(ByteSize[p["type"]])
		else:
			for i in elements[e]["__count__"]:
				file.get_line()
		e = keys.pop_front()


## Check which properties are available and if we have a common case for faster parsing.
func _check_vertex_properties(properties: Dictionary, octree_data: OctreeData) -> bool:
	# We require at least a point position in 3D
	if not ("x" in properties and "y" in properties and "z" in properties):
		push_error("At least X, Y and Z values are required for each point!")
		return false

	# Precheck type of color values
	if "r" in properties and \
			properties["r"]["type"] in IntegerTypes:
		integer_colors = true

	# Normals will be ignored if a coordinate is missing
	if "nx" in properties and "ny" in properties and "nz" in properties:
		octree_data.attributes["normal"] = true

	# We will use r,g,b for colors
	if "r" in properties and "g" in properties and "b" in properties:
		octree_data.attributes["color"] = true

	# Common data type cases are only valid for little endian so far
	if big_endian:
		return true

	# Check common data type cases to reduce loading times
	if _all_of_type(properties, ["x", "y", "z", "nx", "ny", "nz"], PropertyType.FLOAT):
		if _all_of_type(properties, ["r", "g", "b"], PropertyType.FLOAT):
			datatype_case = DatatypeCase.FLOAT
		elif _all_of_type(properties, ["r", "g", "b"], PropertyType.UCHAR):
			datatype_case = DatatypeCase.FLOAT_AND_UCHAR

	return true

## As we assume vertex data without lists so far, we can expect a fixed number of bytes per point.
##
## With a fixed byte size per point, we can precalculate the offsets for all properties.
func _calculate_byte_offsets(properties: Dictionary, octree_data: OctreeData) -> int:
	var offset: int = 0
	
	# We will add the available property names to our metadata for later inspection
	if "properties" not in octree_data.format:
		octree_data.format["properties"] = []

	# Now check all vertex properties
	for name in properties:
		if name == "__count__":
			continue

		var p = properties[name]
		if p["type"] == PropertyType.LIST:
			continue
		octree_data.format["properties"].append(name)

		# We store the byte offset (can not be used directly if there are lists)
		p["offset"] = offset
		if name in offsets:
			offsets[name] = offset

		p["size"] = ByteSize.get(p["type"], -1)
		if p["size"] < 0:
			push_error("Found unknown datatype in PLY properties!")
			return -1
		
		# TODO for now we skip files with lists in their vertex data
		# Check data types used for list length and entries
		#if p["type"] == PropertyType.LIST:
			#p["len_size"] = ByteSize[p["len_type"]]
			#p["data_size"] = ByteSize[p["data_type"]]
			#if p["len_size"] < 1 or p["data_size"] < 1 \
					#or p["len_size"] > 4 or p["len_type"] == PropertyType.FLOAT:
				#push_error("Found invalid datatype in PLY property list!")
				#return false
		
		if binary:
			offset += p["size"]
		else:
			offset += 1

		p["unsigned"] = p["type"] in [PropertyType.UCHAR, PropertyType.USHORT, PropertyType.UINT]

	return offset


## Load a main file describing the hierarchical point cloud.
func load_metadata(filename: String) -> OctreeData:
	# PLY loading is complex due to many possible formats
	# Log the time for benchmarking
	var start = Time.get_unix_time_from_system()*1000.0

	# Create an empty metadata class
	var octree_data = OctreeData.new()

	print("Loading PLY file '%s'." % filename)

	if filename.get_extension() != "ply":
		return
	octree_data.base_path = filename

	# Start reading the file header
	var file = FileAccess.open(filename, FileAccess.READ)
	if not file:
		push_error("Failed to open PLY file '%s'." % filename)
		return null

	# Header complete?
	var header = _read_header(file)
	if header.is_empty():
		file.close()
		return null

	# Parse the header
	if not _parse_header(header, octree_data):
		return null
	file.big_endian = big_endian

	_skip_non_vertex_properties(file)
	point_data_offset = file.get_position()

	# Now concentrate on vertex properties only
	if "vertex" not in elements:
		push_error("There is no vertex data in the PLY file!")
		return null
	var properties = elements["vertex"]
	octree_data.point_count = properties["__count__"]
	if not _check_vertex_properties(properties, octree_data):
		return null

	# Check datatypes and offsets
	# Byte offsets for binary version, line offsets for ascii version
	var offset = _calculate_byte_offsets(properties, octree_data)
	if offset < 0:
		return null
	octree_data.point_bytes = offset

	# Retrieve bounding box
	var ext_start = Time.get_unix_time_from_system()*1000.0
	var aabb = _scan_extent(file, octree_data, properties)
	var ext_end = Time.get_unix_time_from_system()*1000.0
	file.close()

	# Scale and offset are usually not used in PLY
	# We use the AABB center as offset to align the point cloud to the origin
	octree_data.scale = Vector3(1,1,1)
	octree_data.offset = -aabb.get_center()

	# TODO: Check point cloud extends
	octree_data.aabb = aabb
	octree_data.aabb_tight = octree_data.aabb
	
	var end = Time.get_unix_time_from_system()*1000.0
	print("Preparing PLY took %f ms, %f ms for checking the extent." % [(end-start),ext_end-ext_start])
	return octree_data


## Load a subfile that describes the hierarchy of a new branch (or the root).
func load_hierarchy(node: OctreeNode) -> bool:
	#var sum_points = 0
	var current = node
	var base_aabb = current.aabb
	base_aabb.size *= 0.5

	current.path = current.octree_data.base_path

	# We prepare one full set of octree nodes (although they are not used so far)
	#for i in range(8):
	#var child_index = current.id+str(i)
	#
	## Determine the correct octant
	#var y = 1 if i&1 else -1
	#var z = 1 if i&2 else -1
	#var x = 1 if i&4 else -1
	#
	## Spawn the new child node and adjust its position
	#var child:OctreeNode = OctreeNode.new(child_index, base_aabb, node.octree_data)
	#
	#child.position = base_aabb.size*Vector3(x,y,z)*0.5
	#current.children[i] = child
	##current.loading_queue.push_back(child)
	#current.add_child(child)
	return true

## Decode a single attribute based on its datatype.
func _decode_property(t: PropertyType, buffer: PackedByteArray, buffer_offset: int = 0) -> Variant:
	match t:
		PropertyType.CHAR:
			return buffer.decode_s8(buffer_offset)
		PropertyType.UCHAR:
			return buffer.decode_u8(buffer_offset)
		PropertyType.SHORT:
			return buffer.decode_s16(buffer_offset)
		PropertyType.USHORT:
			return buffer.decode_u16(buffer_offset)
		PropertyType.INT:
			return buffer.decode_s32(buffer_offset)
		PropertyType.UINT:
			return buffer.decode_u32(buffer_offset)
		PropertyType.FLOAT:
			return buffer.decode_float(buffer_offset)
		PropertyType.DOUBLE:
			return buffer.decode_double(buffer_offset)
	push_error("Property has an invalid datatype '%s'!" % str(t))
	return null


## Decode a single attribute based on its datatype in big endian byte order.
func _decode_property_bigendian(t: PropertyType, buffer: PackedByteArray, \
								buffer_offset: int = 0) -> Variant:
	var slice: PackedByteArray = buffer.slice(buffer_offset, buffer_offset + ByteSize[t])
	slice.reverse()
	match t:
		PropertyType.CHAR:
			return slice.decode_s8(0)
		PropertyType.UCHAR:
			return slice.decode_u8(0)
		PropertyType.SHORT:
			return slice.decode_s16(0)
		PropertyType.USHORT:
			return slice.decode_u16(0)
		PropertyType.INT:
			return slice.decode_s32(0)
		PropertyType.UINT:
			return slice.decode_u32(0)
		PropertyType.FLOAT:
			return slice.decode_float(0)
		PropertyType.DOUBLE:
			return slice.decode_double(0)
	push_error("Property has an invalid datatype '%s'!" % str(t))
	return null


## Scan the PLY file to get the point cloud extent.
func _scan_extent(file:FileAccess, octree_data:OctreeData, properties:Dictionary) -> AABB:
	var minx:float = INF
	var miny:float = INF
	var minz:float = INF
	var maxx:float = -INF
	var maxy:float = -INF
	var maxz:float = -INF
	var p:Vector3
	var buffer:PackedByteArray
	var buffer_offset:int = 0
	
	# Reduce dictionary access during loop
	var tx = properties["x"]["type"]
	var ty = properties["y"]["type"]
	var tz = properties["z"]["type"]
	var ox = properties["x"]["offset"]
	var oy = properties["y"]["offset"]
	var oz = properties["z"]["offset"]

	if binary and has_property_lists:
		push_error("Binary files with lists in the vertex data are not supported yet!")
		return AABB()

	# Prepare variables for binary reading
	var point_count = octree_data.point_count
	var points_read = 0
	var point_bytes = octree_data.point_bytes
	var chunk_points = min(50000, point_count)
	var chunk_size = chunk_points * point_bytes
	var expected_bytes = point_count * point_bytes
	if binary:
		if file.get_length() - file.get_position() < expected_bytes:
			push_error("Failed to read %d bytes from PLY file!" % expected_bytes)
			return AABB()
		buffer = file.get_buffer(chunk_size)
		if buffer.size() != chunk_size:
			push_error("Failed to read PLY chunk at point %d!" % points_read)
			return AABB()

	# Checking data types for each property is expensive!!!
	# Using a predefined fast lane for common cases is about 10x faster!
	if binary and datatype_case in [DatatypeCase.FLOAT, DatatypeCase.FLOAT_AND_UCHAR]:
		while points_read < point_count:
			for i in range(chunk_points):
				p.x = buffer.decode_float(buffer_offset+ox)
				p.z = buffer.decode_float(buffer_offset+oy)
				p.y = buffer.decode_float(buffer_offset+oz)
				buffer_offset += point_bytes

				if p.x < minx: minx = p.x
				if p.x > maxx: maxx = p.x
				if p.y < miny: miny = p.y
				if p.y > maxy: maxy = p.y
				if p.z < minz: minz = p.z
				if p.z > maxz: maxz = p.z

			points_read += chunk_points
			if points_read >= point_count:
				break

			chunk_points = min(chunk_points, point_count - points_read)
			chunk_size = chunk_points * point_bytes
			buffer = file.get_buffer(chunk_size)
			if buffer.size() != chunk_size:
				push_error("Failed to read PLY chunk at point %d!" % points_read)
				return AABB()
			buffer_offset = 0
	# Arbitrary property types (slow)
	elif binary:
		while points_read < point_count:
			for i in range(chunk_points):
				p.x = _decode_property(tx, buffer, buffer_offset+ox)
				p.z = _decode_property(ty, buffer, buffer_offset+oy)
				p.y = _decode_property(tz, buffer, buffer_offset+oz)
				buffer_offset += point_bytes

				if p.x < minx: minx = p.x
				if p.x > maxx: maxx = p.x
				if p.y < miny: miny = p.y
				if p.y > maxy: maxy = p.y
				if p.z < minz: minz = p.z
				if p.z > maxz: maxz = p.z

			points_read += chunk_points
			if points_read >= point_count:
				break

			chunk_points = min(chunk_points, point_count - points_read)
			chunk_size = chunk_points * point_bytes
			buffer = file.get_buffer(chunk_size)
			if buffer.size() != chunk_size:
				push_error("Failed to read PLY chunk at point %d!" % points_read)
				return AABB()
			buffer_offset = 0
	# ASCII
	else:
		for i in range(point_count):
			var line = file.get_line()
			if not line or line.is_empty():
				push_error("Failed to read line %d from PLY file!" % i)
				return AABB()
			var values = line.split(" ", false)

			# Position
			p.x = values[ox].to_float()
			p.z = values[oy].to_float()
			p.y = values[oz].to_float()

			if p.x < minx: minx = p.x
			if p.x > maxx: maxx = p.x
			if p.y < miny: miny = p.y
			if p.y > maxy: maxy = p.y
			if p.z < minz: minz = p.z
			if p.z > maxz: maxz = p.z

	return AABB(Vector3(minx, miny, minz), Vector3(maxx-minx, maxy-miny, maxz-minz))

## Read a binary PLY file (without property lists).
func _load_binary_simple(node: OctreeNode, file: FileAccess, properties: Dictionary) -> bool:
	var buffer: PackedByteArray
	var buffer_offset: int = 0
	var p: Vector3
	var c: Color
	
	# Reduce dictionary access during loop
	var position_offset = node.octree_data.offset
	var has_normal: bool = node.octree_data.attributes["normal"]
	var has_color: bool = node.octree_data.attributes["color"]
	var tx = properties["x"]["type"]
	var ty = properties["y"]["type"]
	var tz = properties["z"]["type"]
	var ox = properties["x"]["offset"]
	var oy = properties["y"]["offset"]
	var oz = properties["z"]["offset"]
	var tnx; var tny; var tnz;
	var onx; var ony; var onz;
	if has_normal:
		tnx = properties["nx"]["type"]
		tny = properties["ny"]["type"]
		tnz = properties["nz"]["type"]
		onx = properties["nx"]["offset"]
		ony = properties["ny"]["offset"]
		onz = properties["nz"]["offset"]
	var tred; var tgreen; var tblue;
	var ored; var ogreen; var oblue;
	var color_max = 0
	var color_offset = Color(0.5,0.5,0.5)
	if has_color:
		tred = properties["r"]["type"]
		tgreen = properties["g"]["type"]
		tblue = properties["b"]["type"]
		ored = properties["r"]["offset"]
		ogreen = properties["g"]["offset"]
		oblue = properties["b"]["offset"]
		color_max = pow(2, 8*properties["r"]["size"])-1.0
		
	# Prepare variables for binary reading
	var point_count = node.octree_data.point_count
	var points_read = 0
	var point_bytes = node.octree_data.point_bytes
	var chunk_points = min(50000, point_count)
	var chunk_size = chunk_points * point_bytes
	var expected_bytes = point_count * point_bytes

	if file.get_length() - file.get_position() < expected_bytes:
		push_error("Failed to read %d bytes from PLY file!" % expected_bytes)
		return false
	buffer = file.get_buffer(chunk_size)
	if buffer.size() != chunk_size:
		push_error("Failed to read PLY chunk at point %d!" % points_read)
		return false
		
	# Checking data types for each property is expensive!!!
	# Using a predefined fast lane for common cases is about 10x faster!

	# All properties are floats
	while points_read < point_count:
		# All floats
		if datatype_case == DatatypeCase.FLOAT:
			for i in range(chunk_points):
				# Position
				p.x = buffer.decode_float(buffer_offset+ox)
				p.z = buffer.decode_float(buffer_offset+oy)
				p.y = buffer.decode_float(buffer_offset+oz)

				node.points[points_read] = p + position_offset

				# Point normal, if available
				if has_normal:
					p.x = buffer.decode_float(buffer_offset+onx)
					p.z = buffer.decode_float(buffer_offset+ony)
					p.y = buffer.decode_float(buffer_offset+onz)
					node.normals[points_read] = p

				# Color (or spherical harmonics) if available
				if has_color:
					c.r = buffer.decode_float(buffer_offset+ored)
					c.g = buffer.decode_float(buffer_offset+ogreen)
					c.b = buffer.decode_float(buffer_offset+oblue)
					# Convert SH degree 0 to RGB colors if present
					if sh_degree >= 0:
						c = c*SH_C0 + color_offset
					node.colors[points_read] = c.srgb_to_linear()

				points_read += 1
				buffer_offset += point_bytes
		# Float for position (and normal), uchar for color
		elif datatype_case == DatatypeCase.FLOAT_AND_UCHAR:
			for i in range(chunk_points):
				# Position
				p.x = buffer.decode_float(buffer_offset+ox)
				p.z = buffer.decode_float(buffer_offset+oy)
				p.y = buffer.decode_float(buffer_offset+oz)

				node.points[points_read] = p + position_offset

				# Point normal, if available
				if has_normal:
					p.x = buffer.decode_float(buffer_offset+onx)
					p.z = buffer.decode_float(buffer_offset+ony)
					p.y = buffer.decode_float(buffer_offset+onz)
					node.normals[points_read] = p

				c.r = buffer.decode_u8(buffer_offset+ored)
				c.g = buffer.decode_u8(buffer_offset+ogreen)
				c.b = buffer.decode_u8(buffer_offset+oblue)
				# Convert integer color values to float
				if integer_colors:
					c /= color_max
				node.colors[points_read] = c.srgb_to_linear()

				points_read += 1
				buffer_offset += point_bytes
		# Arbitrary property types (slow)
		elif not big_endian:
			for i in range(chunk_points):
				# Position
				p.x = _decode_property(tx, buffer, buffer_offset+ox)
				p.z = _decode_property(ty, buffer, buffer_offset+oy)
				p.y = _decode_property(tz, buffer, buffer_offset+oz)

				node.points[points_read] = p + position_offset

				# Point normal, if available
				if has_normal:
					p.x = _decode_property(tnx, buffer, buffer_offset+onx)
					p.z = _decode_property(tny, buffer, buffer_offset+ony)
					p.y = _decode_property(tnz, buffer, buffer_offset+onz)
					node.normals[points_read] = p

				# Color (or spherical harmonics) if available
				if has_color:
					c.r = _decode_property(tred, buffer, buffer_offset+ored)
					c.g = _decode_property(tgreen, buffer, buffer_offset+ogreen)
					c.b = _decode_property(tblue, buffer, buffer_offset+oblue)
					# Convert integer color values to float
					if integer_colors:
						c /= color_max
					# Convert SH degree 0 to RGB colors if present
					if sh_degree >= 0:
						c = c*SH_C0 + color_offset
					node.colors[points_read] = c.srgb_to_linear()

				points_read += 1
				buffer_offset += point_bytes
		# Arbitrary property types and big endian (even slower)
		else:
			for i in range(chunk_points):
				# Position
				p.x = _decode_property_bigendian(tx, buffer, buffer_offset+ox)
				p.z = _decode_property_bigendian(ty, buffer, buffer_offset+oy)
				p.y = _decode_property_bigendian(tz, buffer, buffer_offset+oz)

				node.points[points_read] = p + position_offset

				# Point normal, if available
				if has_normal:
					p.x = _decode_property_bigendian(tnx, buffer, buffer_offset+onx)
					p.z = _decode_property_bigendian(tny, buffer, buffer_offset+ony)
					p.y = _decode_property_bigendian(tnz, buffer, buffer_offset+onz)
					node.normals[points_read] = p

				# Color (or spherical harmonics) if available
				if has_color:
					c.r = _decode_property_bigendian(tred, buffer, buffer_offset+ored)
					c.g = _decode_property_bigendian(tgreen, buffer, buffer_offset+ogreen)
					c.b = _decode_property_bigendian(tblue, buffer, buffer_offset+oblue)
					# Convert integer color values to float
					if integer_colors:
						c /= color_max
					# Convert SH degree 0 to RGB colors if present
					if sh_degree >= 0:
						c = c*SH_C0 + color_offset
					node.colors[points_read] = c.srgb_to_linear()

				points_read += 1
				buffer_offset += point_bytes

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

	return true

## Read an ASCII PLY file (without property lists).
func _load_ascii(node: OctreeNode, file: FileAccess, properties: Dictionary) -> bool:
	var p: Vector3
	var c: Color
	
	# Reduce dictionary access during loop
	var position_offset = node.octree_data.offset
	var has_normal: bool = node.octree_data.attributes["normal"]
	var has_color: bool = node.octree_data.attributes["color"]
	var ox = properties["x"]["offset"]
	var oy = properties["y"]["offset"]
	var oz = properties["z"]["offset"]
	var onx; var ony; var onz;
	if has_normal:
		onx = properties["nx"]["offset"]
		ony = properties["ny"]["offset"]
		onz = properties["nz"]["offset"]
	var ored; var ogreen; var oblue;
	var color_max = 0
	var color_offset = Color(0.5,0.5,0.5)
	if has_color:
		ored = properties["r"]["offset"]
		ogreen = properties["g"]["offset"]
		oblue = properties["b"]["offset"]
		color_max = pow(2, 8*properties["r"]["size"])-1.0
	
	for i in range(node.octree_data.point_count):
		var line = file.get_line()
		if not line or line.is_empty():
			push_error("Failed to read line %d from PLY file!" % i)
			return false
		var values = line.split(" ", false)

		# Position
		p.x = values[ox].to_float()
		p.z = values[oy].to_float()
		p.y = values[oz].to_float()

		node.points[i] = p + position_offset

		# Point normal, if available
		if has_normal:
			p.x = values[onx].to_float()
			p.z = values[ony].to_float()
			p.y = values[onz].to_float()
			node.normals[i] = p

		# Color (or spherical harmonics) if available
		if has_color:
			c.r = values[ored].to_float()
			c.g = values[ogreen].to_float()
			c.b = values[oblue].to_float()
			# Convert integer color values to float
			if integer_colors:
				c /= color_max
			# Convert SH degree 0 to RGB colors if present
			if sh_degree >= 0:
				c = c*SH_C0 + color_offset
			node.colors[i] = c.srgb_to_linear()
	return true

## Load the actual point cloud data and store in a single node.
func load_pointdata(node: OctreeNode) -> bool:
	var filename = node.path

	var file = FileAccess.open(filename, FileAccess.READ)
	if not file:
		push_error("Failed to open point cloud data file: " + filename)
		return false

	# Lock the data mutex befopre resizing the arrays
	node._data_mutex.lock()
	node.points.resize(node.octree_data.point_count)
	if node.octree_data.attributes["normal"]:
		node.normals.resize(node.octree_data.point_count)
	if node.octree_data.attributes["color"]:
		node.colors.resize(node.octree_data.point_count)
	node._data_mutex.unlock()

	print("Expecting %d points in '%s'..." % [node.octree_data.point_count,filename])

	# Skip the header and start reading data
	var properties = elements["vertex"]
	file.seek(self.point_data_offset)
	if binary and big_endian:
		file.big_endian = true

	# Decide which loading function to call
	var result = false
	var load_start = Time.get_unix_time_from_system()*1000.0
	if binary and not has_property_lists:
		result = _load_binary_simple(node, file, properties)
	elif not binary:
		result = _load_ascii(node, file, properties)
	else:
		push_error("File format not supported yet!")
	
	var load_end = Time.get_unix_time_from_system()*1000.0
	print("Loading PLY took %f ms." % (load_end-load_start))

	node.octree_data.loaded_point_count = node.octree_data.point_count
	file.close()

	return result
