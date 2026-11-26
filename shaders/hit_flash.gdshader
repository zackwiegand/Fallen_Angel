// Hit feedback for 2D sprites: a hard white flash (pixel-art style, outline stays dark) on impact,
// and a flickering ember tint while burning.
shader_type canvas_item;

uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform float burn : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec3 rgb = mix(c.rgb, c.rgb * vec3(1.5, 0.55, 0.25) + vec3(0.25, 0.06, 0.0), burn);
	bool outline = dot(c.rgb, vec3(0.333)) < 0.05;
	if (flash > 0.5 && !outline) {
		rgb = vec3(1.0);
	}
	COLOR = vec4(rgb, c.a);
}
