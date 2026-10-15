shader_type canvas_item;
// Hero look for every scene: palette swap from an 18 x 4 lookup, light-facing rim pixels,
// a dark edge on the unlit side, and a small halo around emissive colours (blade, eyepiece).
// The frames themselves are untouched; set look = 0 to see the original colours.

uniform sampler2D palette : filter_nearest, repeat_disable;
uniform float look : hint_range(0.0, 1.0) = 1.0;
// Screen-space directions from the hero towards each light (y down). Colour alpha = strength.
uniform vec2 rim_a_dir = vec2(0.0, -1.0);
uniform vec4 rim_a_color : source_color = vec4(0.31, 0.94, 1.0, 0.35);
uniform vec2 rim_b_dir = vec2(1.0, 0.0);
uniform vec4 rim_b_color : source_color = vec4(1.0, 0.24, 0.6, 0.0);
uniform vec4 shade_edge_color : source_color = vec4(0.03, 0.02, 0.06, 0.55);
uniform float glow_strength : hint_range(0.0, 2.0) = 0.8;
// Dark scenes: emission_lift = 1 / CanvasModulate colour keeps self-lit pixels (blade, eyepiece, rim, halo)
// at full brightness; emission_gain > 1 pushes them over 1.0 so WorldEnvironment glow picks them up.
uniform vec3 emission_lift = vec3(1.0);
uniform float emission_gain = 1.0;
uniform float body_lift = 1.0;
// Reflective tape (lookup row 3): dull silver in the dark, flares to the colour of the light that hits it.
uniform vec4 reflect_base : source_color = vec4(0.38, 0.36, 0.5, 1.0);
uniform vec4 reflect_color : source_color = vec4(0.85, 0.95, 1.0, 1.0);
uniform float reflect_strength : hint_range(0.0, 1.0) = 0.15;

const int PALETTE_SIZE = 18;
const int GLOW_RADIUS = 3;

varying vec4 modulate;

int palette_index(vec3 colour) {
	for (int i = 0; i < PALETTE_SIZE; i++) {
		vec3 source = texelFetch(palette, ivec2(i, 0), 0).rgb;
		if (distance(source, colour) < 0.012) {
			return i;
		}
	}
	return -1;
}

// rgb = halo colour, a = emission strength for an opaque texel colour.
vec4 emission_for(vec4 texel) {
	if (texel.a < 0.5 || max(texel.r, max(texel.g, texel.b)) < 0.5) {
		return vec4(0.0);
	}
	int index = palette_index(texel.rgb);
	return index < 0 ? vec4(0.0) : texelFetch(palette, ivec2(index, 2), 0);
}

float lit(vec2 normal, vec2 light_dir) {
	return clamp(dot(normal, normalize(light_dir + vec2(0.0001))), 0.0, 1.0);
}

// Rim terms for one neighbour direction; only transparent neighbours count as an edge.
void edge_term(float neighbour_alpha, vec2 normal, inout float edge, inout float rim_a, inout float rim_b) {
	if (neighbour_alpha < 0.5) {
		edge = 1.0;
		rim_a = max(rim_a, lit(normal, rim_a_dir));
		rim_b = max(rim_b, lit(normal, rim_b_dir));
	}
}

void vertex() {
	modulate = COLOR;
}

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	vec2 px = TEXTURE_PIXEL_SIZE;
	vec4 result = source;
	float self_emission = 0.0;

	if (source.a > 0.5) {
		int index = palette_index(source.rgb);
		vec3 colour = source.rgb;
		if (index >= 0) {
			colour = mix(source.rgb, texelFetch(palette, ivec2(index, 1), 0).rgb, look);
			self_emission = texelFetch(palette, ivec2(index, 2), 0).a * look;
		}
		colour *= self_emission > 0.1 ? emission_lift * mix(1.0, emission_gain, self_emission) : vec3(mix(1.0, body_lift, look));
		if (self_emission < 0.1 && look > 0.0) {
			float rim_a = 0.0;
			float rim_b = 0.0;
			float edge = 0.0;
			edge_term(texture(TEXTURE, UV + vec2(px.x, 0.0)).a, vec2(1.0, 0.0), edge, rim_a, rim_b);
			edge_term(texture(TEXTURE, UV - vec2(px.x, 0.0)).a, vec2(-1.0, 0.0), edge, rim_a, rim_b);
			edge_term(texture(TEXTURE, UV + vec2(0.0, px.y)).a, vec2(0.0, 1.0), edge, rim_a, rim_b);
			edge_term(texture(TEXTURE, UV - vec2(0.0, px.y)).a, vec2(0.0, -1.0), edge, rim_a, rim_b);
			float strength_a = step(0.45, rim_a) * rim_a_color.a * look;
			float strength_b = step(0.45, rim_b) * rim_b_color.a * look;
			float unlit = edge * (1.0 - step(0.2, max(rim_a * rim_a_color.a, rim_b * rim_b_color.a)));
			colour = mix(colour, shade_edge_color.rgb, unlit * shade_edge_color.a * look);
			colour = mix(colour, rim_a_color.rgb * emission_lift, strength_a);
			colour = mix(colour, rim_b_color.rgb * emission_lift, strength_b);
		}
		float reflective = index >= 0 ? texelFetch(palette, ivec2(index, 3), 0).a * look : 0.0;
		if (reflective > 0.1) {
			vec3 sheen = mix(reflect_base.rgb * body_lift, reflect_color.rgb * emission_lift * emission_gain, reflect_strength);
			colour = mix(colour, sheen, reflective);
		}
		result = vec4(colour, source.a);
	}

	if (look > 0.0 && glow_strength > 0.0 && self_emission < 0.1) {
		vec3 halo = vec3(0.0);
		float halo_alpha = 0.0;
		for (int y = -GLOW_RADIUS; y <= GLOW_RADIUS; y++) {
			for (int x = -GLOW_RADIUS; x <= GLOW_RADIUS; x++) {
				float distance_px = length(vec2(float(x), float(y)));
				if (distance_px < 0.5 || distance_px > float(GLOW_RADIUS) + 0.5) {
					continue;
				}
				vec4 emission = emission_for(texture(TEXTURE, UV + vec2(float(x), float(y)) * px));
				float falloff = pow(1.0 - distance_px / (float(GLOW_RADIUS) + 1.0), 2.0);
				float weight = emission.a * falloff;
				if (weight > halo_alpha) {
					halo_alpha = weight;
					halo = emission.rgb;
				}
			}
		}
		halo_alpha *= glow_strength * look;
		halo *= emission_lift * emission_gain;
		if (result.a < 0.5) {
			result = vec4(halo, halo_alpha * 0.85);
		} else {
			result.rgb = mix(result.rgb, halo, halo_alpha * 0.45);
		}
	}
	COLOR = result * modulate;
}
