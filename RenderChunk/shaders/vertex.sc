$input a_color0, a_position, a_texcoord0, a_texcoord1
#ifdef INSTANCING__ON
    $input i_data0, i_data1, i_data2
#endif
$output v_color0, v_texcoord0, v_lightmapUV
$output v_ambient_occlusion, v_time, v_ev, v_position, v_world_position, v_sun_direction
$output v_sun_radiance, v_sun_ambient, v_moon_radiance, v_moon_ambient

#include <bgfx_shader.sh>
#include <constants.sh>
#include <functions.sh>

SAMPLER2D_AUTOREG(s_MatTexture);

uniform vec4 RenderChunkFogAlpha;
uniform vec4 FogAndDistanceControl;
uniform vec4 ViewPositionAndTime;
uniform vec4 FogColor;

highp vec3 transmittance( highp vec3 light_direction, highp vec3 position ) {
    highp ivec2 offset = textureSize(s_MatTexture, 0) - ivec2(ATLAS_SIZE);

    highp float t = (light_direction.y * 0.5 + 0.5) * LUT_TEXTURE_SIZE.x;
    highp float y = linearstep(EARTH_RADIUS, ATMOSPHERE_RADIUS, length(position)) * LUT_TEXTURE_SIZE.y;

    highp float x_a = floor(t);
    highp float x_b = min(x_a + 1.0, LUT_TEXTURE_SIZE.x);

    highp float f = fract(t);
    
    highp vec3 transmittance_a = 
        + texelFetch(s_MatTexture, ivec2(3072, 1024) + ivec2(x_a, y) + offset, 0).rgb
        + texelFetch(s_MatTexture, ivec2(3072, 1536) + ivec2(x_a, y) + offset, 0).rgb / 255.0;

    highp vec3 transmittance_b = 
        + texelFetch(s_MatTexture, ivec2(3072, 1024) + ivec2(x_b, y) + offset, 0).rgb
        + texelFetch(s_MatTexture, ivec2(3072, 1536) + ivec2(x_b, y) + offset, 0).rgb / 255.0;

    return mix(transmittance_a, transmittance_b, f);
}

highp vec3 multiple_scattering( highp vec3 light_direction, highp vec3 position ) {
    highp ivec2 offset = textureSize(s_MatTexture, 0) - ivec2(ATLAS_SIZE);

    highp float t = (light_direction.y * 0.5 + 0.5) * LUT_TEXTURE_SIZE.x;
    highp float y = linearstep(EARTH_RADIUS, ATMOSPHERE_RADIUS, length(position)) * LUT_TEXTURE_SIZE.y;

    highp float x_a = floor(t);
    highp float x_b = min(x_a + 1.0, LUT_TEXTURE_SIZE.x);

    highp float f = fract(t);
    
    highp vec3 multiple_scattering_a = 
        + texelFetch(s_MatTexture, ivec2(3584, 1024) + ivec2(x_a, y) + offset, 0).rgb
        + texelFetch(s_MatTexture, ivec2(3584, 1536) + ivec2(x_a, y) + offset, 0).rgb / 255.0;

    highp vec3 multiple_scattering_b = 
        + texelFetch(s_MatTexture, ivec2(3584, 1024) + ivec2(x_b, y) + offset, 0).rgb
        + texelFetch(s_MatTexture, ivec2(3584, 1536) + ivec2(x_b, y) + offset, 0).rgb / 255.0;

    return mix(multiple_scattering_a, multiple_scattering_b, f);
}

vec4 ambient_occlusion( vec4 color0 ) {

    if ( all(lessThan(color0.rgb - color0.gbr, vec3(0.01, 0.01, 0.01))) ) return vec4(1.0, 1.0, 1.0, color0.r);

    vec3 p0 = vec3(128.0, 180.0, 150.0);
    vec3 p1 = vec3(190.0, 182.0, 84.0);
    vec3 p2 = vec3(71.0, 208.0, 51.0);

    highp vec3 N = cross(p1 - p0, p2 - p0);

    highp float t = dot(N, p0) / dot(N, color0.rgb) / 255.0;

    return vec4( color0.rgb * t, 1.0 / t );
}

void main() {

    mat4 model;

    #ifdef INSTANCING__ON
        model = mtxFromCols(i_data0, i_data1, i_data2, vec4(0.0, 0.0, 0.0, 1.0));
    #else
        model = u_model[0];
    #endif

    vec3 world_position = mul(model, vec4(a_position, 1.0)).xyz;

    #ifdef RENDER_AS_BILLBOARDS__ON

        world_position += 0.5;
        vec3 board_view = normalize(world_position);
        vec3 board_plane = normalize(vec3(board_view.z, 0.0, -board_view.x));

        world_position -= cross(board_view, board_plane) * (a_color0.z - 0.5) + board_plane * (a_color0.x - 0.5);

        v_color0 = vec4(1.0, 1.0, 1.0, 1.0);
        v_ambient_occlusion = 1.0;

    #else
        #if defined(SEASONS__ON) && (defined(OPAQUE_PASS) || defined(ALPHA_TEST_PASS))

            v_color0 = a_color0;
            v_ambient_occlusion = mix(a_color0.w, 1.0, 0.5);

        #else

            vec4 color_ao = ambient_occlusion(a_color0);

            v_color0 = vec4(color_ao.rgb, a_color0.a);
            v_ambient_occlusion = mix(color_ao.w, 1.0, 0.5);

        #endif
    #endif

    v_texcoord0 = a_texcoord0;
    v_lightmapUV = a_texcoord1;

    v_position = a_position;
    v_world_position = world_position;

    v_time = ViewPositionAndTime.w;

    highp float t = fog_time(FogColor);
    v_ev = mix(25.0, 1.0, smoothstep(-0.15, 0.15, sin(t)));

    v_sun_direction = vec3(cos(t), sin(t) * 0.8, sin(t) * 0.6);

    v_sun_radiance = SUN_ILLUMINANCE * transmittance(v_sun_direction, CAMERA_POSITION);
    v_sun_ambient = SUN_ILLUMINANCE * multiple_scattering(v_sun_direction, CAMERA_POSITION);

    v_moon_radiance = MOON_ILLUMINANCE * transmittance(-v_sun_direction, CAMERA_POSITION);
    v_moon_ambient = MOON_ILLUMINANCE * multiple_scattering(-v_sun_direction, CAMERA_POSITION);

    gl_Position = mul(u_viewProj, vec4(world_position, 1.0));
}
