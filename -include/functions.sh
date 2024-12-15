
highp float pow5( highp float x ) {
    highp float x2 = x * x;
    return x2 * x2 * x;
}

float linearstep( float a, float b, float x ) {
    return clamp((a-x)/(a-b), 0.0, 1.0);
}

float rayleigh_phase( float cos_theta ) {
    return 3.0 * (1.0 + cos_theta * cos_theta) / (16.0 * PI);
}

float mie_phase( float cos_theta, float g ) {
    float denominator = 1.0 + g * g - 2.0 * g * cos_theta;
    return
                        (1.0 - g * g) 
    / //-----------------------------------------------
        ( 4.0 * PI * denominator * sqrt(denominator) );
}

highp vec2 starmap_uv( highp vec3 view, highp vec3 sun_direction ) {
    highp vec3 forward  = sun_direction;
    highp vec3 up       = vec3(0.0, 0.6, -0.8);
    highp vec3 right    = cross(forward, up);

    highp vec3 celestial_view = mul(view, mtxFromCols(forward, up, right));
    return vec2(atan(celestial_view.z, celestial_view.x) + PI, asin(celestial_view.y)) * 0.5 / PI + vec2(0.0, 0.25);
}

// https://github.com/bWFuanVzYWth/OriginShader/tree/main
highp float fog_time( highp vec4 fog_color ) {
    return clamp(((349.305545 * fog_color.g - 159.858192) * fog_color.g + 30.557216) * fog_color.g - 1.628452, -1.0, 1.0);
}
