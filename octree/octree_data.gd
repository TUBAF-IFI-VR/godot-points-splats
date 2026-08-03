extends Resource

## Data structure to store global properties for an octree.
##
## The properties are based on the Potree data format so far.
##
class_name OctreeData

var loader : OctreeLoader = null
var version : float = 0.0	## Potree file format version
var base_path : String = ""
var data_dir : String = ""
var aabb : AABB
var aabb_tight : AABB
var spacing : float = 0.0
var scale : Vector3
var offset : Vector3
var step_size : int = 1			## Number of hierarchy levels to expect in next hierarchy file
var point_count : int = 0		## Total number of points in point cloud
var loaded_point_count : int = 0 ## Currently loaded number of points
var show_debug_objects : bool = false

var _initial_visibility_range: float 
var _projection_size_threshold : float

## Calculated number of bytes per data point
var point_bytes = 0

# Availability of point attributes, we always require the position
# TODO: do we have to incorporate more attributes to support a wider range of files?
var attributes = {
	"position" : true,
	"normal" : false,
	"color" : false,
	"intensity" : false,
	"class"  : false
}

## We support different normal vector encodings
var format : Dictionary = {}

# A basic point shaded and a quad based rendering for blending effects (just a prototype)
enum RenderMode {POINT=0, QUAD}

var render_mode : RenderMode = RenderMode.QUAD
var point_material = preload("res://octree/basic_point.tres")
var quad_material = preload("res://octree/basic_quad.tres").duplicate()

# Signals to trigger loading / unloading of new branches

## Add a subnode to the loading queue
@warning_ignore("unused_signal")
signal request_subnode(childnode:OctreeNode)
## Defer loading of a subnode by removing it from the queue
@warning_ignore("unused_signal")
signal defer_subnode(childnode:OctreeNode)
## Change the initial visibility range end
@warning_ignore("unused_signal")
signal visibility_range_changed(value: float)

@warning_ignore("unused_signal")
signal projection_size_threshold_changed(value: int)

var initial_visibility_range: float:
	get:
		return _initial_visibility_range
	set(value):
		_initial_visibility_range = value
		visibility_range_changed.emit(value)

var projection_size_threshold: float:
	get:
		return _projection_size_threshold
	set(value):
		_projection_size_threshold = value
		projection_size_threshold_changed.emit(value)
