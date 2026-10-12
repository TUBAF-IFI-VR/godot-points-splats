shader_type spatial;
render_mode unshaded, cull_disabled;

varying vec3 pos;

void vertex() {
	// Called for every vertex the material is visible on.
	pos = VERTEX;
}

void fragment() {
	int count = int(abs(pos.x)<0.495) + int(abs(pos.y)<0.495) + int(abs(pos.z)<0.495);
	if( count >= 2 )
		discard;
	ALBEDO = vec3(0.8, 0.7, 0.0);
	//ALPHA = 0.5;
}

//void light() {
//	// Called for every pixel for every light affecting the material.
//	// Uncomment to replace the default light processing function with this one.
//}
