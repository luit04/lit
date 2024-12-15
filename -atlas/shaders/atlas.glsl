#[compute]
#version 460

layout ( local_size_x = 4, local_size_y = 4, local_size_z = 1 ) in;

layout ( set = 0, binding = 0 ) uniform sampler2D transmittance_sampler;
layout ( set = 0, binding = 1 ) uniform sampler2D multiple_scattering_sampler;
layout ( set = 0, binding = 2 ) uniform sampler2D noise_sampler;
layout ( set = 0, binding = 3 ) uniform sampler2D starmap_sampler;
layout ( set = 0, binding = 4, rgba8 ) uniform image2D atlas_image;

const float PI                              = 3.141592653589793;
const float FOUR_PI                         = 12.566370614359173;

const vec3  BLACK                           = vec3(0.0, 0.0, 0.0);
const vec3  WHITE                           = vec3(1.0, 1.0, 1.0);

const float EARTH_RADIUS                    = 6.360; // megameter
const float ATMOSPHERE_RADIUS               = 6.400; // megameter
const vec3  CAMERA_POSITION                 = vec3(0.0, 6.361, 0.0); // megameter

const vec3  RAYLEIGH_SCATTERING_COEFFICIENT = vec3(5.802, 13.558, 33.1); // per megameter

const vec3  MIE_SCATTERING_COEFFICIENT      = vec3(3.996, 3.996, 3.996); // per megameter
const vec3  MIE_ABSROPTION_COEFFICIENT      = vec3(4.400, 4.400, 4.400); // per megameter

const vec3  OZONE_ABSORPTION_COEFFICIENT    = vec3(0.650, 1.881, 0.085); // per megameter

const float RAYLEIGH_ALTITUDE               = 8.0; // kilometer
const float MIE_ALTITUDE                    = 1.2; // kilometer

const int   VIEW_STEPS                      = 40;

struct Atmosphere {
    vec3 rayleigh_scattering;
    vec3 mie_scattering;
    vec3 multiple_scattering;
} atmosphere;

struct Coefficients {
    float cloud_density;
    vec3 rayleigh_scattering;
    vec3 mie_scattering;
    vec3 total;
};

float linearstep( float a, float b, float x ) {
    return clamp((a-x)/(a-b), 0.0, 1.0);
}

// float rayleigh_phase( float cos_theta ) {
//     return 3.0 * (1.0 + cos_theta * cos_theta) / (16.0 * PI);
// }

// float mie_phase( float cos_theta, float g ) {
//     float denominator = 1.0 + g * g - 2.0 * g * cos_theta;
//     return
//                         (1.0 - g * g) 
//     / //-----------------------------------------------
//         ( FOUR_PI * denominator * sqrt(denominator) );
// }

float intersection_length( vec3 x, vec3 view, out bool is_earth ) {

    float b = dot(x, view);
    float d = b * b - dot(x, x);

    float d_earth = d + EARTH_RADIUS * EARTH_RADIUS;
    float d_atmosphere = d + ATMOSPHERE_RADIUS * ATMOSPHERE_RADIUS;
    
    is_earth = ( d_earth > 0.0 && - b - sqrt(d_earth) > 0.0 );

    return - b + ( is_earth ? - sqrt(d_earth) : sqrt(d_atmosphere) );
}

void coefficients( vec3 x, out Coefficients coefficients ) {

    float h = (length(x) - EARTH_RADIUS) * 1000.0;

    float rayleigh_density = exp(-h / RAYLEIGH_ALTITUDE);
    float mie_density = exp(-h / MIE_ALTITUDE);
    float ozone_density = max(1.0 - abs(h - 25.0) / 15.0, 0.0);

    coefficients.rayleigh_scattering = RAYLEIGH_SCATTERING_COEFFICIENT * rayleigh_density;
    coefficients.mie_scattering = MIE_SCATTERING_COEFFICIENT * mie_density;

    coefficients.total = 
        coefficients.rayleigh_scattering +
        coefficients.mie_scattering + MIE_ABSROPTION_COEFFICIENT * mie_density +
        OZONE_ABSORPTION_COEFFICIENT * ozone_density;
}

vec2 lut_uv( vec3 x, vec3 sun ) {
    return vec2(
        dot(normalize(x), sun) * 0.5 + 0.5,
        linearstep(EARTH_RADIUS, ATMOSPHERE_RADIUS, length(x))
    );
}

void atmosphere_scattering( vec3 view, vec3 sun ) {

    atmosphere.rayleigh_scattering = BLACK;
    atmosphere.mie_scattering = BLACK;
    atmosphere.multiple_scattering = BLACK;

    bool is_earth;

    float dt = intersection_length(CAMERA_POSITION, view, is_earth) / float(VIEW_STEPS);
    vec3 dx = dt * view;
    vec3 x = CAMERA_POSITION + dx * 0.5;

    vec3 transmittance = WHITE;

    for ( int t = 0; t < VIEW_STEPS; t++ ) {

        Coefficients view_coefficients;
        coefficients(x, view_coefficients);
        vec3 sample_transmittance = exp(-view_coefficients.total * dt);
        vec3 transmittance_integral = transmittance * (1.0 - sample_transmittance) / view_coefficients.total;

        vec2 transmittance_uv = lut_uv(x, sun);

        atmosphere.multiple_scattering +=
            transmittance_integral * (view_coefficients.rayleigh_scattering + view_coefficients.mie_scattering)
            * texture(multiple_scattering_sampler, transmittance_uv).rgb;

        vec3 sample_transmittance_with_cloud = 
            transmittance_integral 
            * texture(transmittance_sampler, transmittance_uv).rgb;

        atmosphere.rayleigh_scattering += view_coefficients.rayleigh_scattering * sample_transmittance_with_cloud;
        atmosphere.mie_scattering += view_coefficients.mie_scattering * sample_transmittance_with_cloud;
        
        transmittance *= sample_transmittance;
        x += dx;
    }
}

void main() {
    
    ivec2 coord = ivec2(gl_GlobalInvocationID.xy);

    if ( coord.y >= 2048 ) {
        vec2 uv = vec2(coord.x, coord.y - 2048) / vec2(4096.0, 2048.0);

        vec4 starmap = texture(starmap_sampler, uv);
        starmap.rgb  = pow(starmap.rgb, vec3(1.0 / 2.2));

        imageStore(atlas_image, coord, starmap);
        return;
    }

    if ( coord.x >= 1024 || coord.y >= 1024 ) return;

    vec2 uv = vec2(coord) / 1024.0;
    vec2 p = uv * 2.0 - 1.0;

    vec3 view = vec3(0.0, p.y, sqrt(1.0 - p.y * p.y));
    vec3 sun  = vec3(0.0, p.x, sqrt(1.0 - p.x * p.x));

    atmosphere_scattering(view, sun);

    for ( int x = 0; x < 3; x++ ) 
    for ( int y = 0; y < 2; y++ ) {
        vec3 data;
        switch (x) {
            case 0: data = atmosphere.rayleigh_scattering; break;
            case 1: data = atmosphere.mie_scattering; break;
            case 2: data = atmosphere.multiple_scattering; break;
        }
        switch (y) {
            case 0: data = floor(data * 255.0) / 255.0; break;
            case 1: data = fract(data * 255.0); break;
        }
        imageStore(atlas_image, coord + ivec2(x, y) * 1024, vec4(data, 1.0));
    }

    imageStore(atlas_image, coord + ivec2(3, 0) * 1024, vec4(texture(noise_sampler, uv).xxx, 1.0));

    if ( coord.x >= 512 || coord.y >= 512 ) return;

    uv *= 2.0;

    for ( int x = 0; x < 2; x++ ) 
    for ( int y = 0; y < 2; y++ ) {
        vec3 data;
        switch (x) {
            case 0: data = texture(transmittance_sampler, uv).rgb; break;
            case 1: data = texture(multiple_scattering_sampler, uv).rgb; break;
        }
        switch (y) {
            case 0: data = floor(data * 255.0) / 255.0; break;
            case 1: data = fract(data * 255.0); break;
        }
        imageStore(atlas_image, coord + ivec2(3, 1) * 1024 + ivec2(x, y) * 512, vec4(data, 1.0));
    }
}