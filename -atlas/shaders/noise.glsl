#[compute]
#version 460

layout (local_size_x = 2, local_size_y = 2, local_size_z = 1) in;

layout (set = 0, binding = 0, r32f) uniform image2D noise_image;

vec2 hash( vec2 p ) {
    p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
    return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
}

float noise( vec2 p, vec2 tile_size ) {
    vec2 i = floor(p);
    vec2 f = fract(p);

    vec2 u = f * f * (3.0 - 2.0 * f);

    return mix(
        mix(dot(hash(mod(i + vec2(0.0, 0.0), tile_size)), f - vec2(0.0, 0.0)),
            dot(hash(mod(i + vec2(1.0, 0.0), tile_size)), f - vec2(1.0, 0.0)), u.x),
        mix(dot(hash(mod(i + vec2(0.0, 1.0), tile_size)), f - vec2(0.0, 1.0)),
            dot(hash(mod(i + vec2(1.0, 1.0), tile_size)), f - vec2(1.0, 1.0)), u.x), u.y);
}

float fbm( vec2 p, vec2 tile_size, const int octaves ) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;

    for (int i = 0; i < octaves; i++) {
        value += amplitude * noise(p * frequency, tile_size * frequency);
        frequency *= 2.0;
        amplitude *= 0.5;
    }

    return value;
}

void main() {
    ivec2 coord = ivec2(gl_GlobalInvocationID.xy);

    vec2 tile_size = vec2(8.0, 8.0);
    vec2 p = vec2(coord) / 1024.0 * tile_size;

    imageStore(noise_image, coord, vec4(fbm(p, tile_size, 8) * 0.5 + 0.5, 0.0, 0.0, 0.0));
}