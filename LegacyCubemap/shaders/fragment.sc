$input v_texcoord0, v_position, v_title, v_time, v_ev, v_sun_direction, v_sun_radiance, v_moon_radiance

#include <bgfx_shader.sh>
#include <constants.sh>
#include <functions.sh>
#include <ACES.sh>

SAMPLER2D_AUTOREG(s_MatTexture);

struct Light {
    vec3 direction;
    vec3 radiance;
    float illuminance;
    float cos_theta;
};

highp float noise_linear( highp vec2 p ) {

    p = fract(p) * NOISE_TEXTURE_SIZE;

    highp vec2 i = floor(p);
    highp vec2 f = fract(p);

    highp ivec2 offset = ivec2(3072, 0);
    highp ivec2 texel00 = offset + ivec2(i);
    highp ivec2 texel01 = offset + ivec2(mod(i + vec2(0, 1), NOISE_TEXTURE_SIZE));
    highp ivec2 texel10 = offset + ivec2(mod(i + vec2(1, 0), NOISE_TEXTURE_SIZE));
    highp ivec2 texel11 = offset + ivec2(mod(i + vec2(1, 1), NOISE_TEXTURE_SIZE));

    return mix(
        mix(texelFetch(s_MatTexture, texel00, 0).x, texelFetch(s_MatTexture, texel10, 0).x, f.x), 
        mix(texelFetch(s_MatTexture, texel01, 0).x, texelFetch(s_MatTexture, texel11, 0).x, f.x), 
        f.y
    );
}

highp float noise_nearest( highp vec2 p ) {
    return texelFetch(s_MatTexture, ivec2(3072, 0) + ivec2(fract(p) * NOISE_TEXTURE_SIZE), 0).x;
}

#include <cloud.sh>

highp vec3 sky( highp vec3 view, Light light[2], highp float time ) {

    bool is_ground = view.y < 0.0 && sqrt(1.0 - view.y * view.y) < EARTH_RADIUS / length(CAMERA_POSITION);

    highp vec3 cloud_transmittance = vec3(1.0, 1.0, 1.0);
    highp vec3 cloud_scattering = vec3(0.0, 0.0, 0.0);
    if ( !is_ground ) cloud(view, light, time, cloud_transmittance, cloud_scattering);

    highp vec3 cloud_transmittance_stylized = mix(vec3(1.0, 1.0, 1.0), cloud_transmittance, 0.5);

    highp vec3 radiance = vec3(0.0, 0.0, 0.0);
    for ( int id = 0; id < 2; id++ ) {
        highp vec2 uv = vec2(light[id].direction.y, view.y) * 0.5 + 0.5;
        uv = uv * (SKY_TEXTURE_SIZE - 1.0) / SKY_TEXTURE_SIZE + 0.5 / SKY_TEXTURE_SIZE;

        highp vec3 rayleigh_scattering_a = texture2D(s_MatTexture, SKY_TEXTURE_SIZE * (vec2(0.0, 0.0) + uv) / ATLAS_SIZE).rgb;
        highp vec3 rayleigh_scattering_b = texture2D(s_MatTexture, SKY_TEXTURE_SIZE * (vec2(0.0, 1.0) + uv) / ATLAS_SIZE).rgb;
        highp vec3 rayleigh_scattering = rayleigh_scattering_a + rayleigh_scattering_b / 255.0;

        highp vec3 mie_scattering_a = texture2D(s_MatTexture, SKY_TEXTURE_SIZE * (vec2(1.0, 0.0) + uv) / ATLAS_SIZE).rgb;
        highp vec3 mie_scattering_b = texture2D(s_MatTexture, SKY_TEXTURE_SIZE * (vec2(1.0, 1.0) + uv) / ATLAS_SIZE).rgb;
        highp vec3 mie_scattering = mie_scattering_a + mie_scattering_b / 255.0;

        highp vec3 multiple_scattering_a = texture2D(s_MatTexture, SKY_TEXTURE_SIZE * (vec2(2.0, 0.0) + uv) / ATLAS_SIZE).rgb;
        highp vec3 multiple_scattering_b = texture2D(s_MatTexture, SKY_TEXTURE_SIZE * (vec2(2.0, 1.0) + uv) / ATLAS_SIZE).rgb;
        highp vec3 multiple_scattering = multiple_scattering_a + multiple_scattering_b / 255.0;

        radiance += cloud_transmittance_stylized * light[id].illuminance * (rayleigh_scattering * rayleigh_phase(light[id].cos_theta) + mie_scattering * mie_phase(light[id].cos_theta, 0.8) + multiple_scattering);
        radiance += cloud_transmittance * float(!is_ground) * light[id].radiance * smoothstep(0.99995, 0.99998, light[id].cos_theta);
    }

    highp vec2 uv = starmap_uv(view, light[0].direction);
    uv = uv * (STARMAP_TEXTURE_SIZE - 1.0) / STARMAP_TEXTURE_SIZE + 0.5 / STARMAP_TEXTURE_SIZE + vec2(0.0, 0.5);
    radiance += cloud_transmittance * float(!is_ground) * STARMAP_ILLUMINANCE * pow(texture2D(s_MatTexture, uv).rgb, vec3(2.2, 2.2, 2.2));
    radiance += cloud_scattering;

    return radiance;
}

highp vec3 dither( highp vec3 color, highp vec2 coord ) {
    ARRAY_BEGIN(float, bayer_matrix, 16)
         0.0,  8.0,  2.0, 10.0,
        12.0,  4.0, 14.0,  6.0,
         3.0, 11.0,  1.0,  9.0,
        15.0,  7.0, 13.0,  5.0
    ARRAY_END();
    
    highp ivec2 icoord = ivec2(mod(coord, 4.0));
    return floor(color * 255.0 + bayer_matrix[icoord.x + icoord.y * 4] / 16.0) / 255.0;
}

void main() {

    if ( v_title > 0.5 ) {
        gl_FragColor = texture2D(s_MatTexture, v_texcoord0);
        return;
    }

    highp vec3 view = normalize(v_position);

    Light light[2];

    light[0].direction = v_sun_direction;
    light[0].radiance = v_sun_radiance;
    light[0].illuminance = SUN_ILLUMINANCE;
    light[0].cos_theta = dot(v_sun_direction, view);

    light[1].direction = -v_sun_direction;
    light[1].radiance = v_moon_radiance;
    light[1].illuminance = MOON_ILLUMINANCE;
    light[1].cos_theta = dot(-v_sun_direction, view);

    highp vec3 color = ACESFitted(sky(view, light, v_time) * v_ev);

    color = pow(color, vec3(0.454545, 0.454545, 0.454545));
    color = dither(color, gl_FragCoord.xy);

    gl_FragColor = vec4(color, 1.0);
}
