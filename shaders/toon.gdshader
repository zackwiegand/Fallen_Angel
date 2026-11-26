// Cel shader ported from sprite-poc's toon_material(): diffuse (+ optional hard specular) ->
// luminance -> 3 flat colour bands, output unlit. Lights are computed here (not Godot lights),
// matching the Blender rig's Key + Back suns. The rig camera is fixed and the character rotates
// in front of it, so these act as camera-relative lights.
shader_type spatial;
render_mode unshaded, cull_back;

// Colours are linear values, same numbers as the Blender materials (Standard view transform).
uniform vec3 dark = vec3(0.0);
uniform vec3 mid = vec3(0.5);
uniform vec3 lite = vec3(1.0);
uniform vec2 bands = vec2(0.3, 0.75);
uniform bool spec = false;
uniform bool emissive = false;
uniform vec3 emit_color = vec3(1.0, 0.05, 0.0);

// Blender suns converted to Godot axes (x, z, -y), pointing toward the light.
const vec3 KEY_DIR = vec3(-0.406, 0.707, 0.579);
const vec3 BACK_DIR = vec3(-0.453, 0.423, 0.785);
const float KEY_E = 3.0;
const float BACK_E = 1.5;
const float ALBEDO_GREY = 0.8;      // Blender's default diffuse colour (Lambert: albedo / PI)
const float GLOSS_ALPHA = 0.0625;   // roughness 0.25 squared (GGX)

float ggx(vec3 n, vec3 l, vec3 v) {
	vec3 h = normalize(l + v);
	float nh = max(dot(n, h), 0.0);
	float a2 = GLOSS_ALPHA * GLOSS_ALPHA;
	float d = a2 / (PI * pow(nh * nh * (a2 - 1.0) + 1.0, 2.0));
	return d * max(dot(n, l), 0.0) / max(4.0 * max(dot(n, v), 0.05), 1e-3);
}

void fragment() {
	if (emissive) {
		ALBEDO = emit_color;
	} else {
		vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		vec3 v = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
		vec3 lk = normalize(KEY_DIR);
		vec3 lb = normalize(BACK_DIR);
		float val = ALBEDO_GREY / PI * (KEY_E * max(dot(n, lk), 0.0) + BACK_E * max(dot(n, lb), 0.0));
		if (spec) {
			val += 0.6 * ALBEDO_GREY * (KEY_E * ggx(n, lk, v) + BACK_E * ggx(n, lb, v));
		}
		ALBEDO = val < bands.x ? dark : (val < bands.y ? mid : lite);
	}
}
