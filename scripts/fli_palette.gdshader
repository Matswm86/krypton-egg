shader_type canvas_item;
// Maps an 8-bit palette index image (red channel) through a 256x1 palette texture.

uniform sampler2D palette : filter_nearest;

void fragment() {
	float idx = texture(TEXTURE, UV).r;
	COLOR = vec4(texture(palette, vec2((idx * 255.0 + 0.5) / 256.0, 0.5)).rgb, 1.0);
}
