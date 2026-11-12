# Points and Splats: Godot Point Cloud Rendering

This project was developed to extend the Godot engine with features for hierarchical point cloud and splat rendering. The provided add-on enables loading individual point cloud data files and hierarchical point cloud datasets in the Potree format. The latter enables efficient rendering of millions of points using an octree data structure and Godot's LOD system.

The add-on is compatible with Godot 4.5 and later.

## Supported File Formats (current state)
The following file formats are currently supported:
- Potree 2.x
- Potree legacy 1.7 / 1.8
- LAS 1.4 (all 10 standardized formats, with backward compatibility for LAS 1.2–1.3)
- PLY

The Potree 1.x format was added first to fulfill our personal demand to view and integrate legacy datasets without reconverting all of them to the Potree 2.x format.
The included PLY loader supports pure point/vertex data, meshes and common PLY-encoded 3D Gaussian Splatting (3DGS) datasets.

## How to Use the Add-on
Create an instance of the octree class. In the node properties, select the dataset type from the dropdown menu and select the file to load. This can be a single point cloud file (PLY, LAS) or the metadata of a Potree dataset (cloud.js or metadata.json).

A preview will be spawned and visible in the 3D editor. For hierarchical datasets, such as Potree, only the root octree node will be loaded and displayed to provide a preview of the general appearance and extents.
Please note that large-scale PLY or LAS files might significantly slow down the editor as they are not divided into octree nodes yet. Consider file path assignment and loading during runtime in that case.

## How to Use the Example App
The project is prepared with a simple UI to tweak LOD settings. By default the lion_takanawa dataset from the Potree examples will be loaded from the project's resources. Use the tool buttons in the top-left corner to open another point cloud or to hide the settings panel.

## Adjusting the Settings
Progressive loading and LOD are based on visibility ranges (in meters) and a projected-size threshold (percentage of screen coverage).
By default, the visibility range will be divided by 2 at every level for the next deeper octree nodes. The octree nodes at depth 1 (children of the root) start with the initial visiblity range setting.
For large-scale scenes with high octree depth, a higher initial visibility range may be needed, while compact scenes of individual objects could benefit from a lower visibility range to render very dense nodes only at close range.
A suitable projected size depends on the octree's depth and the AABB's extent. If you set the threshold too low in the case of large-scale scenes, deeper nodes could become visible too early as their projected AABB fills a lot of the user's view. In most cases 15 to 40 percent is a good setting.
Currently, point spacing is not detected automatically. Very sparse areas can be compensated by adjusting the point size to fill gaps. The adaptive point size setting will increase the point size if the camera is far away.

## Limitations
Currently, all supported file formats will be rendered as points (circles) only. Correct rendering and blending of Gaussian splats has not yet been integrated.
