extends Object

## Base class for specific point cloud loaders.
##
## Inherit from this class to implement new data loaders for a specific file
## format.
##
class_name OctreeLoader

## Available loaders for specific file / hierarchy formats.
enum DataTypes {Potree, LAS}

## Dictionary of available file loaders.
const DataLoaders = {
	"Potree" : preload("../loaders/potree_loader.gd"),
	"LAS" : preload("../loaders/las_loader.gd")
}

## Returns an instance of a specific loader class.
static func get_loader(data_type:DataTypes) -> OctreeLoader:
	var loader_script = DataLoaders[DataTypes.keys()[data_type]]
	return loader_script.new()

## Load a main file describing the hierarchical point cloud.
func load_metadata(_filename:String) -> OctreeData:
	return null

## Load a subfile describe the hierarchy of a new branch (or the root).
func load_hierarchy(_node:OctreeNode) -> bool:
	return false
	
## Load the actual point cloud data and store in a single node.
func load_pointdata(_node:OctreeNode) -> bool:
	return false
	
## Prepare a valid AABB by switching axes if size is negative
func get_valid_aabb(a:Vector3, b:Vector3) -> AABB:
	var minv : Vector3 = a.min(b)
	var maxv : Vector3 = a.max(b)
		
	return AABB(minv, abs(maxv-minv))
