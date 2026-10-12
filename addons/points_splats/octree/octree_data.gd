## Data structure to store global properties for an octree.
##
## The properties are based on the Potree data format so far. 
## Use and members of this class might change in the future to account for new data formats
## or to separate parts into multiple data objects.
## All [OctreeNode] instances will have a reference to the associated [OctreeData]
##
class_name OctreeData
extends Resource


# Signals to trigger loading / unloading of new branches

## Add a subnode to the loading queue.
@warning_ignore("unused_signal")
signal request_subnode(childnode: OctreeNode)

## Defer loading of a subnode by removing it from the queue.
@warning_ignore("unused_signal")
signal defer_subnode(childnode: OctreeNode)

## Change the initial visibility range end.
@warning_ignore("unused_signal")
signal visibility_range_changed(value: float)

## Change the size threshold used to trigger loading of more detailed LODs.
@warning_ignore("unused_signal")
signal projection_size_threshold_changed(value: int)


## Scalar types in PLY files.
enum PropertyType { INT8, UINT8, INT16, UINT16, INT32, UINT32, FLOAT, DOUBLE, ARRAY }

## Available rendering modes.
##
## A basic point shader and a quad based rendering for adjustable rendering style are provided so far.
##
enum RenderMode {
	POINT = 0,
	QUAD,
}


## Predifined list for integer properties.
const IntegerTypes: Array = [
	PropertyType.INT8,
	PropertyType.UINT8,
	PropertyType.INT16,
	PropertyType.UINT16,
	PropertyType.INT32,
	PropertyType.UINT32,
]

## Number of bytes for a specific type string.
const ByteSize = {
	PropertyType.INT8: 1,
	PropertyType.UINT8: 1,
	PropertyType.INT16: 2,
	PropertyType.UINT16: 2,
	PropertyType.INT32: 4,
	PropertyType.UINT32: 4,
	PropertyType.FLOAT: 4,
	PropertyType.DOUBLE: 8,
	PropertyType.ARRAY: -1,
}


var loader: OctreeLoader = null ## Specific loader instance used for this point cloud.
var base_path: String = "" ## Path to the main (metadata) file of a dataset.
var data_dir: String = "" ## Directory where the point data is stored.
var aabb: AABB ## Bounding box of the point cloud.
var aabb_tight: AABB ## Optional tight bounding box, currently unused.
var spacing: float = 0.0 ## Spacing between the points of the root node.

## Global scale applied to position data values.
var scale: Vector3

## Global offset applied to position data values.
var offset: Vector3 

var point_count: int = 0 ## Total number of points in point cloud.
var loaded_point_count: int = 0 ## Currently loaded number of points.

## Calculated number of bytes per data point.
var point_bytes = 0

## Dynamic dictionary of all attributes, which are present in the file.
var attributes: Dictionary = {}

## Availability of the most important point attributes, we always require the position.
## TODO: do we have to incorporate more attributes to support a wider range of files?
## TODO intensity is not used so far
## TODO classification data is not processed by the current loaders
var has_attribute: Dictionary = {
	"position": false,
	"normal": false,
	"color": false,
	"intensity": false,
	"class": false,
}

## Store metdata for the dataset which could be used for in-game UI elements for example.
##
## While [member OctreeData.format] stores information to decode the file, all information relevant
## for the user should be added here. For example aquisition date, location, coordinates, details
## about the specimen and more. 
var metadata: Dictionary = {}

## Dynamic dictionary to store information about the file format.
##
## This dictionary is usually filled by the respective loader class. Common format attributes are:
## - File version
## - File encoding
## - Normal vector encoding
var format: Dictionary = { }

## Rendering method to use.
var render_mode: RenderMode = RenderMode.QUAD

## Preload the basic point shader material.
var point_material = preload("../materials/render_point.tres")

## Preload the advanced quad based shader material.
##
## A duplicate will be created for each point cloud to allow individual parameters.
var quad_material = preload("../materials/render_quad.tres").duplicate()

## Enable/Disable additional visual elements.
var show_debug_objects: bool = false

## Visibility range value for the top level nodes with a custom setter.
var _initial_visibility_range: float

## Threshold used for this point cloud to trigger progressive lading.
var _projection_size_threshold: float

## Assign a new initial visibility range and trigger the related signal.
var initial_visibility_range: float:
	get:
		return _initial_visibility_range
	set(value):
		_initial_visibility_range = value
		visibility_range_changed.emit(value)


## Assign a new projected size threshold and trigger the related signal.
var projection_size_threshold: float:
	get:
		return _projection_size_threshold
	set(value):
		_projection_size_threshold = value
		projection_size_threshold_changed.emit(value)


## General class to store properties of a single point attribute.
class Attribute:
	var name: String
	var description: String
	var type: String
	var size: int
	var num_elements: int
	var element_size: int
	var byte_offset: int
	var offset: Array
	var scale: Array
	var min: Array
	var max: Array
	
	## Initialize a new attribute with most important values.
	func _init(name: String, type: String, num_elements: int, element_size: int) -> void:
		self.name = name
		self.type = type
		self.num_elements = num_elements
		self.element_size = element_size
		self.size = num_elements * element_size
		
		offset.resize(num_elements)
		scale.resize(num_elements)
		min.resize(num_elements)
		max.resize(num_elements)
