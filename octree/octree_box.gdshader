shader_type spatial;
render_mode unshaded, cull_disabled;

varying vec3 pos;

void vertex() {
	// Called for every vertex the material is visible on.
	pos = VERTEX;
}

void fragment() {
	vec3 pos_abs = abs(pos);
	int count = int(pos_abs.x<0.485) + int(pos_abs.y<0.485) + int(pos_abs.z<0.485);
	if( count >= 2 )
		discard;
	ALBEDO = vec3(0.8, 0.7, 0.0);
}

//void light() {
//	// Called for every pixel for every light affecting the material.
//	// Uncomment to replace the default light processing function with this one.
//}
