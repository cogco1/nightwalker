shader_type canvas_item;
// Low street fog: pixel-quantised value noise drifting sideways, densest just above the kerb.

uniform float scroll_x = 0.0;
uniform float band_top = 112.0;
uniform float band_peak = 152.0;
uniform float band_bottom = 172.0;
uniform float density = 0.28;
uniform vec4 fog_color : source_color = vec4(0.69, 0.48, 0.82, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(cell);
	float b = hash(cell + vec2(1.0, 0.0));
	float c = hash(cell + vec2(0.0, 1.0));
	float d = hash(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	vec2 pixel = floor(SCREEN_UV / SCREEN_PIXEL_SIZE);
	vec2 drift = vec2(pixel.x + scroll_x * 0.85 + TIME * 7.0, pixel.y * 2.2);
	float n = value_noise(drift / 26.0) * 0.65 + value_noise(drift / 9.0 + 4.0) * 0.35;
	float rise = smoothstep(band_top, band_peak, pixel.y);
	float fall = 1.0 - smoothstep(band_peak, band_bottom, pixel.y);
	float alpha = n * rise * fall * density;
	alpha = floor(alpha * 12.0) / 12.0;
	COLOR = vec4(fog_color.rgb, alpha);
}
