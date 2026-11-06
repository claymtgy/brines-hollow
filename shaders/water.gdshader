shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, specular_schlick_ggx;

uniform vec3 shallow_color : source_color = vec3(0.50, 0.82, 0.76);
uniform vec3 deep_color : source_color = vec3(0.12, 0.40, 0.48);
uniform vec3 foam_color : source_color = vec3(0.96, 0.97, 0.94);
uniform float depth_fade = 2.6;
uniform float foam_width = 0.32;
uniform float light_mult = 1.0;
uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(wpos.x * 0.45 + TIME * 1.3) * 0.035 + cos(wpos.z * 0.33 + TIME * 1.0) * 0.035;
}

void fragment() {
	float depth = texture(depth_texture, SCREEN_UV).r;
	vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	v.xyz /= v.w;
	float water_depth = max(-v.z - (-VERTEX.z), 0.0);

	float n1 = texture(noise_tex, wpos.xz * 0.045 + vec2(TIME * 0.018, TIME * 0.012)).r;
	float n2 = texture(noise_tex, wpos.xz * 0.11 - vec2(TIME * 0.025, -TIME * 0.01)).r;

	float t = clamp(water_depth / depth_fade, 0.0, 1.0);
	t = smoothstep(0.0, 1.0, t);
	vec3 col = mix(shallow_color, deep_color, t);
	// Soft caustic-like banding in the shallows.
	col += vec3(0.05, 0.07, 0.06) * step(0.62, n1 * 0.6 + n2 * 0.5) * (1.0 - t);

	// Stylised foam line where water meets terrain, wobbling with noise.
	float fw = foam_width * (0.55 + n2 * 0.9);
	float foam = 1.0 - step(fw, water_depth);
	float foam2 = (1.0 - step(fw * 2.2, water_depth)) * step(0.55, n1);
	foam = max(foam, foam2 * 0.6);

	col = mix(col, foam_color, foam);
	ALBEDO = col * light_mult;
	ALPHA = clamp(mix(0.55, 0.93, t) + foam, 0.0, 1.0);
	ROUGHNESS = 0.18;
	SPECULAR = 0.35;
	vec3 nn = vec3(n1 - 0.5, 1.0, n2 - 0.5) * vec3(0.12, 1.0, 0.12);
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(nn), 0.0)).xyz);
}
