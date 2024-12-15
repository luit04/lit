#[compute]
#version 460

layout ( local_size_x = 2, local_size_y = 2, local_size_z = 1 ) in;

layout ( set = 0, binding = 0, rgba32f ) uniform image2D transmittance_image;

const int   MARCH_STEPS                     = 50;

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

struct Coefficients {
    vec3 rayleigh_scattering;
    vec3 mie_scattering;
    vec3 total;
};

float intersection_length( vec3 x, vec3 view, out bool is_earth ) {

    float b = - dot(x, view); // -1.0 multiplied
    float d = b * b - dot(x, x);

    float d_earth = d + EARTH_RADIUS * EARTH_RADIUS;
    float d_atmosphere = d + ATMOSPHERE_RADIUS * ATMOSPHERE_RADIUS;
    
    is_earth = ( d_earth > 0.0 && b - sqrt(d_earth) > 0.0 );

    return b + ( is_earth ? - sqrt(d_earth) : sqrt(d_atmosphere) );
}

void coefficients( vec3 x, out Coefficients coefficients ) {

    float h = (length(x) - EARTH_RADIUS) * 1000.0;

    float rayleigh_density = exp(-h / RAYLEIGH_ALTITUDE);
    float mie_density = exp(-h / MIE_ALTITUDE);
    float ozone_density =  max(1.0 - abs(h - 25.0) / 15.0, 0.0);

    coefficients.rayleigh_scattering = RAYLEIGH_SCATTERING_COEFFICIENT * rayleigh_density;
    coefficients.mie_scattering = MIE_SCATTERING_COEFFICIENT * mie_density;

    coefficients.total = 
        coefficients.rayleigh_scattering +
        coefficients.mie_scattering + MIE_ABSROPTION_COEFFICIENT * mie_density +
        OZONE_ABSORPTION_COEFFICIENT * ozone_density;
}


vec3 transmittance( vec3 x, vec3 sun ) {

    bool is_earth = false;
    float dt = intersection_length(x, sun, is_earth) / float(MARCH_STEPS);
    if (is_earth) return BLACK;
    vec3 dx = sun * dt;
    
    vec3 sum_total = BLACK;
    
    for ( int t = 0; t < MARCH_STEPS; t++ ) {
        Coefficients sample_coefficients;
        coefficients(x, sample_coefficients);
        sum_total += sample_coefficients.total;
        x += dx;
    }
    
    return exp(-sum_total * dt);

}

void main() {
    
    ivec2 coord = ivec2(gl_GlobalInvocationID.xy);

    vec2 uv = vec2(coord) / imageSize(transmittance_image).xy;
    uv.x = uv.x * 2.0 - 1.0;
    
    vec3 x = vec3(0.0, mix(EARTH_RADIUS, ATMOSPHERE_RADIUS, uv.y), 0.0);
    
    vec3 sun = vec3(0.0, uv.x, sqrt(1.0 - uv.x * uv.x));

    imageStore(transmittance_image, coord, vec4(transmittance(x, sun), 1.0));
}