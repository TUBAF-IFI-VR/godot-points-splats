# Points and Splats: Godot Point Cloud Rendering

This project was developed to extend the Godot engine with features for hierarchical point cloud and splat rendering. The provided add-on enables loading individual point cloud data files and hierarchical point cloud datasets in the Potree format. The latter enables efficient rendering of millions of points using an octree data structure and Godot's LOD system.

The add-on is compatible with Godot 4.5 and later.

## Supported File Formats (current state)
The following file formats are currently supported:
- Potree 1.7 / 1.8
- LAS 1.4 (all 10 standardized formats, with backward compatibility for LAS 1.2–1.3)
- PLY
- Work in progress: Potree 2.x

The Potree 1.x format was added first to fulfill our personal demand to view and integrate legacy datasets without reconverting all of them to the Potree 2.x format.
The included PLY loader supports pure point/vertex data, meshes and common PLY-encoded 3D Gaussian Splatting (3DGS) datasets.

## How to Use the Add-on
Create an instance of the octree class. In the node properties, select the dataset type from the dropdown menu and select the file to load. This can be a single point cloud file (PLY, LAS) or the metadata of a Potree dataset (cloud.js or metadata.json).

A preview will be spawned and visible in the 3D editor. For hierarchical datasets, such as Potree, only the root octree node will be loaded and displayed to provide a preview of the general appearance and extents.
Please note that large-scale PLY or LAS files might significantly slow down the editor as they are not divided into octree nodes yet. Consider file path assignment and loading during runtime in that case.

## How to Use the Example App
The project is prepared with a simple UI to tweak LOD settings. By default the lion_takanawa dataset from the Potree examples will be loaded from the project's resources. Use the tool buttons in the top-left corner to open another point cloud or to hide the settings panel.

## Adjusting the Settings
(based on visibility range and a projected size threshold)
For large-scale scenes, a lower visibility range (in meters) is beneficial, while compact scenes of individual objects could require a high range value to trigger loading of deeper octree nodes earlier.
A good projected size (in percent of screen coverage) depends on the octree's depth and the AABB's extent. Adjust the point size (in mm) to your needs. Currently, point spacing is not detected automatically. Higher visibility ranges can be compensated for by adjusting the point size to fill gaps.

## Limitations
Currently, all supported file formats will be rendered as points only. Correct rendering and blending of Gaussian splats has not yet been integrated.
