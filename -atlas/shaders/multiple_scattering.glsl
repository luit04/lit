#[compute]
#version 460

layout ( local_size_x = 2, local_size_y = 2, local_size_z = 1 ) in;

layout ( set = 0, binding = 0 ) uniform sampler2D transmittance_sampler;
layout ( set = 0, binding = 1, rgba32f ) uniform image2D multiple_scattering_image;

const int   SPHERICAL_STEPS                 = 16;
const int   MARCH_STEPS                     = 24;

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

struct Coefficients {
    vec3 rayleigh_scattering;
    vec3 mie_scattering;
    vec3 total;
};

float linearstep( float a, float b, float x ) {
    return clamp((a-x)/(a-b), 0.0, 1.0);
}

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

vec2 uv( vec3 x, vec3 sun ) {
    return vec2(
        dot(normalize(x), sun) * 0.5 + 0.5,
        linearstep(EARTH_RADIUS, ATMOSPHERE_RADIUS, length(x))
    );
}

vec3 multiple_scattering( vec3 x_0, vec3 sun ) {
    
    float uniform_phase = 1.0 / FOUR_PI;
    
    vec3 L_2nd = BLACK;
    vec3 f_ms = BLACK;
    
    float dtheta = PI / float(SPHERICAL_STEPS);
    
    float dphi = dtheta;
    
    for ( float phi = dphi * 0.5; phi < PI; phi += dphi ) {
        
        vec3 omega = vec3(sin(phi), 0.0, cos(phi));
    
        for ( float theta = dtheta * 0.5; theta < PI; theta += dtheta) {
            
            omega.xz *= sin(theta);
            omega.y = cos(theta);
            
            bool is_earth = false;            
            float dt = intersection_length(x_0, omega, is_earth) / float(MARCH_STEPS);
            vec3 dx_1 = omega * dt;
            vec3 x_1 = x_0;
            
            vec3 transmittance = WHITE;
            
            for ( int t = 0; t < MARCH_STEPS; t++ ) {
                
                Coefficients sample_coefficients;
                coefficients(x_1, sample_coefficients);
                vec3 sample_transmittance = exp(-sample_coefficients.total * dt);
                
                vec3 sample_scattering = 
                    (sample_coefficients.rayleigh_scattering + sample_coefficients.mie_scattering) * transmittance 
                    * (1.0 - sample_transmittance) / sample_coefficients.total;
                
                L_2nd += sample_scattering * texture(transmittance_sampler, uv(x_1, sun)).rgb * uniform_phase;
                f_ms += sample_scattering;

                transmittance *= sample_transmittance;
                x_1 += dx_1;
            }
            
            if ( is_earth ) {
                L_2nd += 
                    0.3 / PI * max(dot(normalize(x_1), sun), 0.0) 
                    * texture(transmittance_sampler, uv(x_1, sun)).rgb * transmittance;
            }
        }
    }
    
    float domega = 1.0 / (SPHERICAL_STEPS * SPHERICAL_STEPS);
    
    L_2nd *= domega;
    f_ms  *= domega;
    
    return L_2nd / (1.0 - f_ms);
}

void main() {
    
    ivec2 coord = ivec2(gl_GlobalInvocationID.xy);

    vec2 uv = vec2(coord) / imageSize(multiple_scattering_image).xy;
    uv.x = uv.x * 2.0 - 1.0;
    
    vec3 x = vec3(0.0, mix(EARTH_RADIUS + 0.000001, ATMOSPHERE_RADIUS, uv.y), 0.0);
    
    vec3 sun = vec3(0.0, uv.x, sqrt(1.0 - uv.x * uv.x));

    imageStore(multiple_scattering_image, coord, vec4(max(multiple_scattering(x, sun), 0.0), 1.0));
}