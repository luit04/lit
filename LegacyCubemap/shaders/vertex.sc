$input a_position, a_texcoord0
$output v_texcoord0, v_position, v_title, v_time, v_ev, v_sun_direction, v_sun_radiance, v_moon_radiance

#include <bgfx_shader.sh>
#include <constants.sh>
#include <functions.sh>

SAMPLER2D_AUTOREG(s_MatTexture);

uniform mat4 CubemapRotation;
uniform vec4 FogColor;
uniform vec4 ViewPositionAndTime;

highp vec3 transmittance( highp vec3 light_direction, highp vec3 position ) {

    highp float t = (light_direction.y * 0.5 + 0.5) * LUT_TEXTURE_SIZE.x;
    highp float y = linearstep(EARTH_RADIUS, ATMOSPHERE_RADIUS, length(position)) * LUT_TEXTURE_SIZE.y;

    highp float x_a = floor(t);
    highp float x_b = min(x_a + 1.0, LUT_TEXTURE_SIZE.x);

    highp float f = fract(t);
    
    highp vec3 transmittance_a = 
        + texelFetch(s_MatTexture, ivec2(3072, 1024) + ivec2(x_a, y), 0).rgb
        + texelFetch(s_MatTexture, ivec2(3072, 1536) + ivec2(x_a, y), 0).rgb / 255.0;

    highp vec3 transmittance_b = 
        + texelFetch(s_MatTexture, ivec2(3072, 1024) + ivec2(x_b, y), 0).rgb
        + texelFetch(s_MatTexture, ivec2(3072, 1536) + ivec2(x_b, y), 0).rgb / 255.0;

    return mix(transmittance_a, transmittance_b, f);
}

void main() {

    v_texcoord0 = a_texcoord0;
    v_position  = vec3(a_position.x, 0.205 - a_position.y, -a_position.z);
    v_title = 0.0;
    v_time = ViewPositionAndTime.w;

    highp float t = fog_time(FogColor);
    v_ev = mix(25.0, 1.0, smoothstep(-0.15, 0.15, sin(t)));

    v_sun_direction = vec3(cos(t), sin(t) * 0.8, sin(t) * 0.6);

    v_sun_radiance = SUN_ILLUMINANCE * transmittance(v_sun_direction, CAMERA_POSITION);
    v_moon_radiance = MOON_ILLUMINANCE * transmittance(-v_sun_direction, CAMERA_POSITION);

    if ( CubemapRotation[0][0] < 0.999999 ) {
        v_title = 1.0;
        gl_Position = mul(u_modelViewProj, mul(CubemapRotation, vec4(a_position, 1.0)));
    }
    else gl_Position = mul(u_modelViewProj, vec4(a_position, 1.0));
}
