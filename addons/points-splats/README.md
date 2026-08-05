# Godot Point Cloud Rendering

This project showcases an add-on to load single LAS point cloud files and hierarchical point clouds in the Potree format. The latter enables efficient rendering of millions of points using an octree data structure and Godot's LOD system (based on the visibility range property and a calculated projected size).

## How to Use
The project is prepared with a simple UI to tweak LOD settings. By default the lion_takanawa dataset from the Potree examples will be loaded from the project's resources. Use the tool buttons in the top left corner to open another point cloud or to hide the settings panel.

## Adjusting the Settings
For large-scale scenes a lower visiblity range (in meter) is beneficial while compact scenes of individual objects require a high range value to trigger loading of deeper octree nodes earlier. The projected size (in percent of screen coverage) should be increased for point clouds with a high octree depth. Adjust the point size (in mm) to your needs. Currently, point spacing is not detected automatically. Higher visiblity ranges can be compensated for by adjusting the point size to fill gaps.
Rendering of 3DGS scenes has not been integrated yet.
