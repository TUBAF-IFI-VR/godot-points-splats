shader_type spatial;

render_mode unshaded, depth_draw_opaque, cull_disabled;

varying vec4 color;

void vertex() {
	color = COLOR;
	color.a = 1.0;
	POINT_SIZE = 0.5;
}

void fragment() {
	ALBEDO = color.rgb;
}