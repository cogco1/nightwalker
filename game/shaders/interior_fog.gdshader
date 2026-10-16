shader_type canvas_item;
render_mode unshaded;

// Local UV is measured in world-native pixels, independent of window resolution
// and the CANVAS_ITEMS mode that keeps the dialogue glyphs crisp.
uniform vec2 native_size = vec2(320.0, 180.0);
uniform vec2 native_origin = vec2(0.0);
uniform float band_top = 96.0;
uniform float band_bottom = 152.0;
uniform float density = 0.05;
uniform vec4 fog_color : source_color = vec4(0.32, 0.48, 0.57, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 pixel = floor(UV * native_size + native_origin);
	// The noise advances in whole native pixels, so it never becomes screen-pixel
	// grain or slides through the character's original pixel grid.
	vec2 cell = floor((pixel + vec2(floor(TIME * 2.0), 0.0)) / vec2(12.0, 5.0));
	float n = 0.3 + hash(cell) * 0.7;
	float height = clamp((pixel.y - band_top) / max(1.0, band_bottom - band_top), 0.0, 1.0);
	float alpha = floor(n * sin(height * 3.14159265) * density * 64.0) / 64.0;
	COLOR = vec4(fog_color.rgb, alpha);
}
