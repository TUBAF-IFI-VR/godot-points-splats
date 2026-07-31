shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled;//, skip_vertex_transform;

uniform float point_size : hint_range(2.0,100.0) = 10.0;
uniform float blend : hint_range(0.0,1.0) = 1.0;
uniform bool billboard = false;

void vertex() {
	//VERTEX = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
    //NORMAL = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
    //BINORMAL = normalize((MODELVIEW_MATRIX * vec4(BINORMAL, 0.0)).xyz);
    //TANGENT = normalize((MODELVIEW_MATRIX * vec4(TANGENT, 0.0)).xyz);
	
	vec3 world_normal = normalize(mat3(MODEL_MATRIX)*NORMAL);
	//COLOR = vec4(vec3(0.4)+vec3(world_normal.x, world_normal.z, world_normal.y)*0.4, 1.0);
	
	float camera_dist = length(MODELVIEW_MATRIX[3].xyz);
	VERTEX *= point_size*0.01 * (1.0 + camera_dist);
	
	if (billboard) {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			MAIN_CAM_INV_VIEW_MATRIX[0],
			MAIN_CAM_INV_VIEW_MATRIX[1],
			MAIN_CAM_INV_VIEW_MATRIX[2],
			MODEL_MATRIX[3]);
		MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	}
}

void fragment() {
	/*float d = length(UV-vec2(0.5));
	
	if( d>0.5 )
		discard;*/
	
	ALBEDO = COLOR.rgb;
	//ALPHA = COLOR.a * smoothstep(1.0, 1.0-blend*0.5, d*2.0);
}

//void light() {
//	// Called for every pixel for every light affecting the material.
//	// Uncomment to replace the default light processing function with this one.
//}
