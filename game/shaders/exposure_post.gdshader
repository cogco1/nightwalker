shader_type canvas_item;
// Full-screen pass driven by surveillance exposure: RGB split in native pixels, a cyan/red edge tint,
// and a vignette. exposure = 0 leaves the image untouched apart from the vignette.
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float exposure : hint_range(0.0, 1.0) = 0.0;
uniform float marked = 0.0;
uniform float vignette = 0.35;
uniform vec4 watch_tint : source_color = vec4(0.31, 0.94, 1.0, 1.0);
uniform vec4 marked_tint : source_color = vec4(1.0, 0.24, 0.43, 1.0);

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE;
	float shift = max(floor(exposure + 0.35), marked * step(0.5, fract(TIME * 3.0)));
	float row_jitter = marked * step(0.97, fract(sin(floor(SCREEN_UV.y / px.y) * 7.13 + floor(TIME * 20.0)) * 43758.5));
	vec2 uv = SCREEN_UV + vec2(row_jitter * 2.0 * px.x, 0.0);
	vec3 colour;
	colour.r = texture(screen_tex, uv + vec2(shift * px.x, 0.0)).r;
	colour.g = texture(screen_tex, uv).g;
	colour.b = texture(screen_tex, uv - vec2(shift * px.x, 0.0)).b;
	vec2 centred = SCREEN_UV - 0.5;
	float edge = smoothstep(0.45, 0.85, length(centred * vec2(1.0, 0.75)) * 1.4);
	vec3 tint = mix(watch_tint.rgb, marked_tint.rgb, marked);
	colour = mix(colour, colour * 0.35, edge * vignette);
	colour += tint * edge * exposure * 0.12;
	COLOR = vec4(colour, 1.0);
}
