$input v_color0, v_texcoord0, v_lightmapUV
$input v_ambient_occlusion, v_time, v_ev, v_position, v_world_position, v_sun_direction
$input v_sun_radiance, v_sun_ambient, v_moon_radiance, v_moon_ambient

#include <bgfx_shader.sh>
#include <constants.sh>
#include <functions.sh>
#include <ACES.sh>
#include <BRDF.sh>

SAMPLER2D_AUTOREG(s_MatTexture);
SAMPLER2D_AUTOREG(s_SeasonsTexture);
SAMPLER2D_AUTOREG(s_LightMapTexture);

struct Light {
    vec3 direction;
    vec3 radiance;
    vec3 ambient;
    float illuminance;
    float cos_theta;
};

highp float noise_linear( highp vec2 p ) {

    p = fract(p) * NOISE_TEXTURE_SIZE;

    highp vec2 i = floor(p);
    highp vec2 f = fract(p);

    highp ivec2 offset = textureSize(s_MatTexture, 0) - ivec2(ATLAS_SIZE) + ivec2(3072, 0);
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
    return texelFetch(s_MatTexture, textureSize(s_MatTexture, 0) - ivec2(ATLAS_SIZE) + ivec2(3072, 0) + ivec2(fract(p) * NOISE_TEXTURE_SIZE), 0).x;
}

#include <cloud.sh>

highp vec3 sky( highp vec3 view, Light light[2], highp float time ) {

    bool is_ground = view.y < 0.0 && sqrt(1.0 - view.y * view.y) < EARTH_RADIUS / length(CAMERA_POSITION);

    highp vec3 cloud_transmittance = vec3(1.0, 1.0, 1.0);
    highp vec3 cloud_scattering = vec3(0.0, 0.0, 0.0);
    if ( !is_ground ) cloud(view, light, time, cloud_transmittance, cloud_scattering);

    highp vec3 cloud_transmittance_stylized = mix(vec3(1.0, 1.0, 1.0), cloud_transmittance, 0.5);

    highp ivec2 offset = textureSize(s_MatTexture, 0) - ivec2(ATLAS_SIZE);

    highp vec3 radiance = vec3(0.0, 0.0, 0.0);
    for ( int id = 0; id < 2; id++ ) {
        highp vec2 coord = vec2(light[id].direction.y, view.y) * 0.5 + 0.5;
        coord = coord * (SKY_TEXTURE_SIZE - 1.0) + 0.5;

        highp vec3 rayleigh_scattering_a = texelFetch(s_MatTexture, ivec2(SKY_TEXTURE_SIZE * vec2(0.0, 0.0) + coord) + offset, 0).rgb;
        highp vec3 rayleigh_scattering_b = texelFetch(s_MatTexture, ivec2(SKY_TEXTURE_SIZE * vec2(0.0, 1.0) + coord) + offset, 0).rgb;
        highp vec3 rayleigh_scattering = rayleigh_scattering_a + rayleigh_scattering_b / 255.0;

        highp vec3 mie_scattering_a = texelFetch(s_MatTexture, ivec2(SKY_TEXTURE_SIZE * vec2(1.0, 0.0) + coord) + offset, 0).rgb;
        highp vec3 mie_scattering_b = texelFetch(s_MatTexture, ivec2(SKY_TEXTURE_SIZE * vec2(1.0, 1.0) + coord) + offset, 0).rgb;
        highp vec3 mie_scattering = mie_scattering_a + mie_scattering_b / 255.0;

        highp vec3 multiple_scattering_a = texelFetch(s_MatTexture, ivec2(SKY_TEXTURE_SIZE * vec2(2.0, 0.0) + coord) + offset, 0).rgb;
        highp vec3 multiple_scattering_b = texelFetch(s_MatTexture, ivec2(SKY_TEXTURE_SIZE * vec2(2.0, 1.0) + coord) + offset, 0).rgb;
        highp vec3 multiple_scattering = multiple_scattering_a + multiple_scattering_b / 255.0;

        radiance += cloud_transmittance_stylized * light[id].illuminance * (rayleigh_scattering * rayleigh_phase(light[id].cos_theta) + mie_scattering * mie_phase(light[id].cos_theta, 0.8) + multiple_scattering);
        radiance += cloud_transmittance * float(!is_ground) * light[id].radiance * smoothstep(0.99995, 0.99998, light[id].cos_theta);
    }

    highp vec2 coord = starmap_uv(view, light[0].direction);
    coord = coord * (STARMAP_TEXTURE_SIZE - 1.0) + 0.5 + vec2(0.0, 0.5) * ATLAS_SIZE;
    radiance += cloud_transmittance * float(!is_ground) * STARMAP_ILLUMINANCE * pow(texelFetch(s_MatTexture, ivec2(coord) + offset, 0).rgb, vec3(2.2, 2.2, 2.2));
    radiance += cloud_scattering;

    return radiance;
}

highp vec3 BRDF( highp vec3 view, highp vec3 normal, Light light, highp vec3 diffuse, float roughness ) {

    highp vec3 H = normalize(view + light.direction);
    highp float NoL = max(dot(normal, light.direction), 0.0);
    highp float NoH = max(dot(normal, H), 0.0);
    highp float VoH = max(dot(view, H), 0.0);
    highp float NoV = max(dot(normal, view), 0.0);

    highp float D = DistributionGGX(NoH, roughness);
    highp float G = GeometrySmith(NoV, NoL, roughness);
    highp float F = FresnelSchlick(VoH, 0.04);

    highp float specular = D * G * F / (4.0 * NoV * NoL + 0.0001);

    return (diffuse * (1.0 - F) + specular) * light.radiance * NoL;
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

    #if defined(DEPTH_ONLY_OPAQUE_PASS) || defined(DEPTH_ONLY_PASS)
        gl_FragColor = vec4(0.0, 0.0, 0.0, 0.0);
        return;
    #endif

    vec3 albedo = pow(texture2D(s_MatTexture, v_texcoord0).rgb, vec3(2.2, 2.2, 2.2));
    float alpha = texture2D(s_MatTexture, v_texcoord0).a;

    #if defined(ALPHA_TEST_PASS)
        if (alpha < 0.5) discard;
    #endif

    #if defined(SEASONS__ON) && (defined(OPAQUE_PASS) || defined(ALPHA_TEST_PASS))
        albedo *= mix(vec3(1.0, 1.0, 1.0), texture2D(s_SeasonsTexture, v_color0.xy).rgb * 2.0, v_color0.b);
        albedo *= v_color0.aaa;
    #else
        albedo *= v_color0.rgb;
    #endif

    highp vec3 diffuse = albedo / PI;
    float roughness = 0.8;

    #if defined(TRANSPARENT_PASS)
        roughness = 0.02;
        if (v_color0.a > 0.05 && v_color0.a < 0.95) {
            albedo = vec3(1.0, 1.0, 1.0);
            diffuse = vec3(0.0, 0.0, 0.0);
        }
    #endif

    highp float darkness = linearstep(1.0 / 32.0, 15.0 / 16.0, max(v_lightmapUV.y, 1.0 / 32.0));
    highp float shadow = exp2(8.0 * darkness - 8.0) * darkness;

    highp vec3 view = normalize(v_world_position);

    highp vec3 normal = normalize(cross(dFdx(v_position), dFdy(v_position)));

    #if defined(TRANSPARENT_PASS)
        if ( v_color0.a > 0.05 && v_color0.a < 0.95 ) {
            highp vec3 position = v_position;

            position.y += 0.04 * noise_linear((position.xz + v_time * 0.5) / 16.0);
            position.y += 0.02 * noise_linear((position.xz + v_time * 1.3) / 16.0);

            normal = normalize(cross(dFdx(position), dFdy(position)));
        }
    #endif

    Light light[2];

    light[0].direction = v_sun_direction;
    light[0].radiance = v_sun_radiance;
    light[0].ambient = v_sun_ambient;
    light[0].illuminance = SUN_ILLUMINANCE;
    light[0].cos_theta = dot(v_sun_direction, view);

    light[1].direction = -v_sun_direction;
    light[1].radiance = v_moon_radiance;
    light[1].ambient = v_moon_ambient;
    light[1].illuminance = MOON_ILLUMINANCE;
    light[1].cos_theta = dot(-v_sun_direction, view);

    highp vec3 radiance = vec3(0.0, 0.0, 0.0);

    for ( int id = 0; id < 2; id++ ) 
    radiance += BRDF(-view, normal, light[id], diffuse, roughness);

    #if defined(TRANSPARENT_PASS)
        highp vec3 ambient = sky(reflect(view, normal), light, v_time);
    #else
        highp vec3 ambient = vec3(0.0, 0.0, 0.0);
        for ( int id = 0; id < 2; id++ ) ambient += light[id].ambient;
    #endif

    ambient = mix(vec3(0.18, 0.18, 0.18) / PI / v_ev, shadow * ambient, darkness);

    radiance *= shadow;
    radiance += albedo * (ambient * v_ambient_occlusion + exp2(12.0 * v_lightmapUV.x * 16.0 / 15.0 - 12.0) * vec3(1.0, 0.3, 0.04));

    highp vec3 color = ACESFitted(radiance * v_ev);
    
    #if defined(TRANSPARENT_PASS)
        if (v_color0.a > 0.05 && v_color0.a < 0.95) alpha = mix(dot(color, vec3(0.2126, 0.7152, 0.0722)), pow5(1.0 - max(dot(normal, -view), 0.0)), 0.8);
    #endif

    color = pow(color, vec3(0.454545, 0.454545, 0.454545));
    color = dither(color, gl_FragCoord.xy);

    gl_FragColor = vec4(color, alpha);
}