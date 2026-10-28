@tool
class_name OctreeNode
extends Node3D
## This type represens single node in the octree hierarchy.
##
## The point date related to a single node will be processed here,
## including instancing the actual visual nodes. Each node checks
## periodically if additional nodes deeper in the hierarchy have to
## be loaded as children or if a child's visiblity has to be changed.
##


## Time to periodically check whether children should be loaded or not.
const seconds_next_check: float = 0.5

## Controls how visibility range will decrease with octree depth.
##
## The default value is 2.0 which translates to dividing the range by 2.0
## for each depth increase.
##
const visibility_range_scale: float = 2.0


## Shared shader material to use for the bounding boxes.
static var bbox_material = preload("../materials/octree_box.tres")

## All instances use the same default quad mesh as primitive.
static var quad_mesh: QuadMesh = null

## All instances use the same default bounding box mesh as visual geometry.
static var bbox_mesh: BoxMesh = null


## ID encoded as string (prefixed with IDs of higher order nodes).
var id: String = ""

## Depth in the point cloud hierarchy.
var depth: int = 0

## Point spacing in this octree cell.
var spacing: float = 0.0

## Number of points.
var num_points: int = 0

## Location in the related binary file.
var byte_offset: int = 0

## Data size in the related binary file in bytes. 
var byte_size: int = 0

# Point attribute storage
var points: PackedVector3Array ## Position data
var normals: PackedVector3Array ## Normal vectors
var colors: PackedColorArray ## Color values
var intensities: PackedFloat32Array ## Point intensity values (not used so far)

## Reference to the global properties of this octree (point cloud).
var octree_data: OctreeData = null

## Path in the octree folder hierarchy.
var path: String = ""

## Each node has its own AABB.
var aabb: AABB

## Visual point cloud representation.
var visual: GeometryInstance3D = null

## A helper node to test against the view frustum for culling.
var notifier: VisibleOnScreenNotifier3D = null

## Additional visual node to display the bounding box if requested.
var bbox: MeshInstance3D = null

## Margin used to blend different LOD levels.
var visibility_margin: float = 1.0

## @unused: TODO: quickly check if this node is currently loaded or not.
var is_loaded := false

## Protect the node's data while loading.
var _data_mutex: Mutex

## Seconds since last projection/visiblity check.
var _last_check: float = 0.0 

# The following containers manage all child nodes and child nodes queued for loading on demand.
# TODO: improve loading queue approach? (currently per node queue and global queue in [Octree])
# TODO: we should also cosider to free nodes that are not necessary anymore!

## Set of all child nodes (currently loaded and not loaded ones).
##
## They can be addressed by the ID of their octree cell.
## 
var children: Dictionary = { }

## Child nodes queued for loading on demand.
var loading_queue: Array = []


## Prepare shared resources.
static func _static_init() -> void:
	# Prepare the basic quad mesh used by all instances
	quad_mesh = QuadMesh.new()
	quad_mesh.size = Vector2(0.1, 0.1)

	# Also prepare a general bounding box mesh
	bbox_mesh = BoxMesh.new()
	bbox_mesh.size = Vector3(1, 1, 1)
	bbox_mesh.material = bbox_material
	

## Initialize node properties and load a new HRC file if necessary.
func _init(p_id: String, p_aabb: AABB, p_octree_data: OctreeData) -> void:
	self.octree_data = p_octree_data
	self.path = p_octree_data.data_dir + p_id

	self.id = p_id
	self.aabb = p_aabb
	self.depth = p_id.length() - 1
	
	self._data_mutex = Mutex.new()


## Setup the node when entering the scene tree.
func _ready() -> void:
	_create_bbox()

	octree_data.visibility_range_changed.connect(_on_visibility_range_value_changed)

	# TODO: load children in a breadth-first approach!
	if not notifier:
		notifier = VisibleOnScreenNotifier3D.new()
		add_child(notifier)
	notifier.aabb = self.aabb


## Periodically check for child nodes that should be loaded next.
func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	if octree_data.show_debug_objects != bbox.visible:
		bbox.visible = octree_data.show_debug_objects

	# Load only the visible children
	if loading_queue.size() > 0 and _last_check < seconds_next_check:
		var child = null
		var i = 0
		while i < loading_queue.size():
			child = loading_queue[i]
			if child._is_important_enough_to_load() and child.notifier.is_on_screen():
				_data_mutex.lock()
				loading_queue.remove_at(i)
				octree_data.request_subnode.emit(child)
				_data_mutex.unlock()
			else:
				i += 1
		_last_check = 0
	else:
		_last_check += delta


## Create the actual visual node, which is usually a [MultiMeshInstance3D].
func create_multimesh() -> void:
	# Existing geometry will be replaced
	if visual != null:
		remove_child(visual)
		visual.queue_free()

	# By default we render the points as quads to apply shaders
	if octree_data.render_mode == OctreeData.RenderMode.QUAD:
		visual = MultiMeshInstance3D.new()
		var multimesh = MultiMesh.new()

		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		if octree_data.has_attribute["color"]:
			multimesh.use_colors = true
		multimesh.instance_count = points.size()
		multimesh.mesh = quad_mesh

		# Use billboard mode if no normal vector is available
		if not octree_data.has_attribute["normal"]:
			octree_data.quad_material.set_shader_parameter("billboard", true)

		var b = Basis()
		for i in range(points.size()):
			# Orient the quad if a normal vector is available
			if octree_data.has_attribute["normal"]:
				var up = Vector3.UP
				if abs(normals[i].dot(up)) > 0.99:
					up = Vector3.FORWARD
				var axis_x = up.cross(normals[i]).normalized()
				var axis_y = normals[i].cross(axis_x).normalized()
				b = Basis(axis_x, axis_y, normals[i])

			var t = Transform3D(b, points[i])
			multimesh.set_instance_transform(i, t)

			# Add a color if available
			if octree_data.has_attribute["color"]:
				multimesh.set_instance_color(i, colors[i])

		visual.multimesh = multimesh
		visual.material_override = octree_data.quad_material
		visual.set_visibility_range_fade_mode( \
				GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF)

		# [method call_deferred] is necessary to 
		call_deferred("add_child", visual)
		call_deferred("_apply_visibility_range", visual, depth)

	# DEBUG: render just bare points
	else:
		# Render as pure points
		var mesh = ArrayMesh.new()
		var arrays = []

		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = points
		arrays[Mesh.ARRAY_COLOR] = colors

		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arrays)
		mesh.surface_set_material(0, octree_data.point_material)
		visual = MeshInstance3D.new()
		visual.mesh = mesh
		call_deferred("add_child", visual)
	
	# Currently, we don't need point data anymore as separate arrays
	# Free the arrays to reduce memory load
	_data_mutex.lock()
	points.clear()
	normals.clear()
	colors.clear()
	intensities.clear()
	_data_mutex.unlock()


## Create a new bounding box mesh and scale it to the current nodes AABB
func _create_bbox():
	bbox = MeshInstance3D.new()
	bbox.scale = aabb.size
	bbox.mesh = bbox_mesh
	bbox.visibility_range_end = 10.0
	add_child(bbox)


## Apply a new visibility range value to all visual representations of this node.
func _apply_visibility_range(instance: GeometryInstance3D, level: int) -> void:
	var visibility_range_end = _get_range_end_from_level(level)
	instance.visibility_range_end = visibility_range_end
	instance.visibility_range_end_margin = visibility_margin
	if not bbox:
		return
	bbox.visibility_range_end = visibility_range_end
	bbox.visibility_range_end_margin = visibility_margin


## Determine the visiblity range depending on the LOD level (octree depth)
func _get_range_end_from_level(level: int) -> float:
	if level == 0:
		return 0.0
	return octree_data.initial_visibility_range / \
			pow(visibility_range_scale, level - 1)


## Rect to changes of the visiblity range, for example by UI elements.
func _on_visibility_range_value_changed(_value: float) -> void:
	if visual != null:
		_apply_visibility_range(visual, depth)


## @unused Check if the node is within the defined visiblity range.
func _is_within_visibility_range() -> bool:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return false

	var range_end := _get_range_end_from_level(depth)

	if range_end <= 0.0:
		return true

	var node_center := aabb.get_center()
	var distance := camera.global_position.distance_to(node_center)

	return distance <= range_end + visibility_margin


## Calculate the convered screen area as a percentage value.
func _get_projected_size(camera: Camera3D) -> float:
	var distance := camera.global_position.distance_to(aabb.get_center())
	var radius := aabb.size.length() * 0.5
	var fov_rad := deg_to_rad(camera.fov)
	var slope = tan(fov_rad * 0.5)

	# Screen height is only necessary for absolute pixel values
	#var screen_height := get_viewport().get_visible_rect().size.y
	return radius / (slope * distance)


## Check if the calculated screen converage is above or equal to the defined threshold.
func _is_important_enough_to_load() -> bool:
	var viewport := get_viewport()
	if viewport == null:
		return false

	var camera := viewport.get_camera_3d()
	if camera == null:
		return false

	var projected_size := _get_projected_size(camera)

	return projected_size >= octree_data.projection_size_threshold
