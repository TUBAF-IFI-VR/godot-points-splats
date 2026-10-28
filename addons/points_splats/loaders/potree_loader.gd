class_name PotreeLoader
extends OctreeLoader
## Load potree projects into the [OctreeNode] and [OctreeData] classes


## Run an optional function to analyze the octree hierarchy and generate text output.
const _debug_analyze_hrc = false

## Enable additional output during point loading for debugging.
const _debug_print = false

## Separate script file with loading functions for legacy Potree datasets.
const DecoderPotreeV1 = preload("potree1_decoder.gd")

## Separate script file with loading functions for current Potree 2.0 datasets.
const DecoderPotreeV2 = preload("potree2_decoder.gd")


## The decoder script used by this loader instance. It will be initialized when
## [method PotreeLoader.load_metadata] was called and a valid version was found.
var _decoder: RefCounted = null


## Load a main file describing the hierarchical point cloud.
func load_metadata(filename: String) -> OctreeData:
	var octree_data = OctreeData.new()

	# The user should provide the path to a cloud.js, if not we try to fix it
	if filename.get_extension() == "js" or filename.get_extension() == "json":
		octree_data.base_path = filename.get_base_dir()
	else:
		octree_data.base_path = filename
		if FileAccess.file_exists(filename+"/cloud.js"):
			filename += "/cloud.js"
		else:
			filename += "/metadata.json"

	# Load metadata
	var file = FileAccess.open(filename, FileAccess.READ)

	if not file:
		push_error("Failed to open metadata file: " + filename)
		return null

	var metadata = JSON.parse_string(file.get_as_text())
	file.close()

	# Check the dataset version and instantiate a decoder object with version specific functions
	var version = float(metadata.get("version", 0.0))
	if version < 1.0:
		push_error("Invalid or missing file version in Potree metadata!")
		return null
	if version < 2.0:
		if version < 1.7:
			push_warning("Version '%d' was detected for the Potree dataset. Versions <1.7 have "
				+"not been tested and are not guaranteed to work.")
		_decoder = DecoderPotreeV1.new(_debug_analyze_hrc, _debug_print)
	else:
		_decoder = DecoderPotreeV2.new(_debug_analyze_hrc, _debug_print)
	
	# Store general metadata if available
	octree_data.format["version"] = version
	octree_data.metadata["name"] = metadata.get("name", "")
	octree_data.metadata["description"] = metadata.get("description", "")
	octree_data.metadata["projection"] = metadata.get("projection", "")
	
	# Point count can be present (not always in the tested files)
	octree_data.point_count = metadata.get("points", 0)
	# Calculate point count while loading the hierarchy if it was not in the metadata
	if octree_data.point_count == 0:
		octree_data.format["missing_point_count"] = true
	
	# We continue loading properties that are common in all tested file versions
	octree_data.spacing = metadata["spacing"]
	octree_data.offset = Vector3(0,0,0)
	
	# Scale was a scalar value in older versions, should be an array now
	var scale = metadata.get("scale", [1.0,1.0,1.0])
	if scale is Array and len(scale) == 3:
		octree_data.scale = Vector3(scale[0], scale[1], scale[2])
	elif scale is float or scale is int:
		octree_data.scale = Vector3(scale, scale, scale)
	else:
		push_warning("Invalid scale value in Potree metadata.")
		octree_data.scale = Vector3(1,1,1)
	
	# All other properties might be different for the specific file version
	if !_decoder.load_attributes(metadata, octree_data):
		push_error("An error occured while loading metadata for Potree dataset '%s'!" % filename)

	return octree_data


## Load a subfile that describes the hierarchy of a new branch (or the root).
func load_hierarchy(node: OctreeNode) -> bool:
	# Benchmark loading times
	var hrc_start = Time.get_unix_time_from_system()*1000.0
	
	# Hierarchy files are different for Potree 1.x and 2.x
	if !_decoder.load_hierarchy(node):
		push_error("An error occured while parsing the Potree hierarchy!")
		return false

	# Print measured loading time
	var hrc_end = Time.get_unix_time_from_system()*1000.0
	print("Loading octree hierarchy took %f ms." % (hrc_end-hrc_start))

	print("Finished parsing %d hierarchy nodes with %d points in total." % 
		[node.octree_data.node_count,
		node.octree_data.point_count])

	return true


## Load the actual point cloud data and store in a single node.
func load_pointdata(node: OctreeNode) -> bool:
	# Print loaded node IDs only in debug mode if enabled
	if _debug_print:
		print("Loading Potree node: %s" % node.id)
		
	# Hierarchy files are different for Potree 1.x and 2.x
	if !_decoder.load_pointdata(node):
		push_error("An error occured while parsing Potree point data!")
		return false
		
	return true
