shader_type canvas_item;
// Self-lit pixels (neon, windows, beam, particles): ignores CanvasModulate and lights, adds on top,
// and goes above 1.0 by `gain` so WorldEnvironment glow blooms them.
render_mode unshaded, blend_add;

uniform float gain = 1.6;
uniform float flicker = 0.0;

void fragment() {
	vec4 texel = texture(TEXTURE, UV) * COLOR;
	float wobble = 1.0 - flicker * step(0.93, fract(sin(floor(TIME * 18.0) * 12.9898) * 43758.5453));
	COLOR = vec4(texel.rgb * gain * wobble, texel.a);
}
