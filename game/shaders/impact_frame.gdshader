shader_type canvas_item;
// Frozen hit-stop frame. negative = 1 turns it into a manga-style ink frame for the heaviest blows: outlines
// (luma edges sampled one native pixel apart) and very bright pixels (blade glow, hit flash) become ink on a
// pale paper colour, so every figure reads as a black silhouette for one frame.

uniform float negative : hint_range(0.0, 1.0) = 0.0;
uniform vec4 paper : source_color = vec4(0.86, 0.96, 1.0, 1.0);
uniform vec4 ink : source_color = vec4(0.02, 0.03, 0.08, 1.0);
// One native (320 x 180) pixel in UV, whatever resolution the snapshot was taken at.
uniform vec2 native_step = vec2(0.003125, 0.0055556);

varying vec4 modulate;

void vertex() {
	modulate = COLOR;
}

const vec3 LUMA = vec3(0.299, 0.587, 0.114);

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	vec3 result = source.rgb;
	if (negative > 0.0) {
		// TEXTURE is only reachable from fragment() in this renderer, so the samples stay inline.
		float across = dot(texture(TEXTURE, UV + vec2(native_step.x, 0.0)).rgb, LUMA) - dot(texture(TEXTURE, UV - vec2(native_step.x, 0.0)).rgb, LUMA);
		float down = dot(texture(TEXTURE, UV + vec2(0.0, native_step.y)).rgb, LUMA) - dot(texture(TEXTURE, UV - vec2(0.0, native_step.y)).rgb, LUMA);
		float edge = clamp((length(vec2(across, down)) - 0.06) / 0.12, 0.0, 1.0);
		float amount = max(edge, step(0.72, dot(source.rgb, LUMA)));
		result = mix(source.rgb, mix(paper.rgb, ink.rgb, amount), negative);
	}
	COLOR = vec4(result, source.a) * modulate;
}
