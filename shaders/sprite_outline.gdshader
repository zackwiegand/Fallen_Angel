// Pixel post for a character's render texture (sprite-poc's pixelize()): hard alpha and a 1px
// dark outer outline on the 8 neighbours. Drawn 1:1 in the low-res game viewport.
shader_type canvas_item;

uniform vec4 outline_color : source_color = vec4(0.03, 0.015, 0.03, 1.0);
// hit flash: 0 = off, 1 = solid flash_color (outline stays dark)
uniform vec4 flash_color : source_color = vec4(1.0, 0.25, 0.2, 1.0);
uniform float flash : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE;
	vec2 uv = (floor(UV / px) + 0.5) * px;   // sample texel centres only
	vec4 c = texture(TEXTURE, uv);
	if (c.a > 0.5) {
		COLOR = vec4(mix(c.rgb, flash_color.rgb, flash), 1.0);
	} else {
		float n = 0.0;
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				n = max(n, texture(TEXTURE, uv + vec2(float(x), float(y)) * px).a);
			}
		}
		COLOR = n > 0.5 ? outline_color : vec4(0.0);
	}
}
