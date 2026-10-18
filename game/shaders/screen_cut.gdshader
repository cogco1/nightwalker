shader_type canvas_item;
// The hit-impact prototype's screen cut (scripts/core/impact_burst.gd): the image on each side of a line slides
// along it in opposite directions by `shift` native pixels, as if the frame had been sliced through. Whole native
// pixels only, so crisp window-resolution HUD text stays crisp; strength 0 leaves the screen untouched.
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
// A point on the cut in screen UV, the cut's direction in native pixels (normalised) and the base resolution.
uniform vec2 origin = vec2(0.5, 0.5);
uniform vec2 axis = vec2(1.0, 0.0);
uniform vec2 native_size = vec2(320.0, 180.0);
uniform float shift = 2.0;
uniform float strength = 0.0;

void fragment() {
	vec2 p = SCREEN_UV * native_size;
	vec2 normal = vec2(-axis.y, axis.x);
	float side = dot(p - origin * native_size, normal) >= 0.0 ? 1.0 : -1.0;
	vec2 offset = round(axis * shift * strength) * side;
	COLOR = texture(screen_tex, SCREEN_UV - offset / native_size);
}
