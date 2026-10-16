shader_type canvas_item;
// Wet asphalt: mirrors the screen above the kerb into the strip below it, stretched like rain-soaked
// streaks, broken by one-pixel ripples. Puddles (world-anchored) reflect more strongly.
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float floor_y = 156.0;
uniform float scroll_x = 0.0;
uniform float stretch = 1.7;
uniform float strength = 0.35;
uniform float puddle_strength = 0.85;
uniform vec4 tint : source_color = vec4(0.62, 0.55, 0.9, 1.0);

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE;
	vec2 pixel = floor(SCREEN_UV / px);
	float below = pixel.y - floor_y;
	vec3 base = texture(screen_tex, SCREEN_UV).rgb;
	if (below < 1.0) {
		COLOR = vec4(base, 1.0);
	} else {
		float world_x = pixel.x + floor(scroll_x);
		float ripple = floor(sin(pixel.y * 1.9 + TIME * 4.0 + world_x * 0.05) * 1.2 + 0.5);
		float source_y = floor_y - below * stretch;
		vec3 mirrored = texture(screen_tex, (vec2(pixel.x + ripple, source_y) + 0.5) * px).rgb;
		float puddle = step(0.35, sin(world_x * 0.043) * 0.6 + sin(world_x * 0.117 + 1.3) * 0.5);
		float fade = clamp(1.0 - below / 26.0, 0.0, 1.0);
		float amount = mix(strength, puddle_strength, puddle) * fade;
		COLOR = vec4(base + mirrored * tint.rgb * amount, 1.0);
	}
}
