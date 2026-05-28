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
var scale : float = 1.0
var step_size : int = 1		# Number of hierarchy levels to expect in next hrc file??

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

# A basic point shaded and a quad based rendering for blending effects (just a prototype)
enum RenderMode {POINT=0, QUAD}

var render_mode : RenderMode = RenderMode.QUAD
var point_material = preload("res://octree/basic_point.tres")
var quad_material = preload("res://octree/basic_quad.tres")

# Signals to trigger loading / unloading of new branches

## Add a subnode to the loading queue
@warning_ignore("unused_signal")
signal request_subnode(childnode:OctreeNode)
## Defer loading of a subnode by removing it from the queue
@warning_ignore("unused_signal")
signal defer_subnode(childnode:OctreeNode)
