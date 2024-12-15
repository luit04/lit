// Not physically correct!

struct Cloud {
    vec3 scattering;
    vec3 extinction;
    float density;
};

void cloud_coefficient( highp vec3 x, highp float time, inout Cloud cloud ) {
    highp float h = min(abs(length(x) - EARTH_RADIUS - CLOUD_HEIGHT), CLOUD_THICKNESS) / CLOUD_THICKNESS;
    highp float move = time * 0.005;

    cloud.density = mix(noise_nearest(x.xz * 250.0 + move), noise_nearest(x.xz * 500.0 + move), 0.33);
    cloud.density = smoothstep(0.5, 1.0, cloud.density * sqrt(1.0 - h * h));
    cloud.scattering = CLOUD_SCATTERING_COEFFICIENT * cloud.density;
    cloud.extinction = (CLOUD_SCATTERING_COEFFICIENT + CLOUD_ABSROPTION_COEFFICIENT) * cloud.density;
}

void cloud( highp vec3 view, Light light[2], highp float time, out highp vec3 transmittance, out highp vec3 scattering ) {
    highp vec3 x = CAMERA_POSITION;

    highp float cloud_min_height = EARTH_RADIUS + CLOUD_HEIGHT - CLOUD_THICKNESS;
    highp float cloud_max_height = EARTH_RADIUS + CLOUD_HEIGHT + CLOUD_THICKNESS;

    highp float b = dot(x, view);
    highp float d = b * b - dot(x, x);

    highp float t_min = - b + sqrt(d + cloud_min_height * cloud_min_height);
    highp float t_max = - b + sqrt(d + cloud_max_height * cloud_max_height);

    highp float dt = (t_max - t_min) / float(CLOUD_STEPS);

    x += t_min * view;

    transmittance = vec3(1.0, 1.0, 1.0);
    scattering = vec3(0.0, 0.0, 0.0);

    for ( int v = 0; v < CLOUD_STEPS; v++, x += dt * view ) {
        Cloud cloud;
        cloud_coefficient(x, time, cloud);

        if ( cloud.density < 0.001 ) continue;
        
        transmittance *= exp(-cloud.extinction * dt);

        highp vec3 sample_scattering = 

        scattering += transmittance * cloud.scattering;
    }

    scattering *=
        + light[0].radiance * mix(0.25 / PI, mie_phase(light[0].cos_theta, 0.8), 0.4) 
        + light[1].radiance * mix(0.25 / PI, mie_phase(light[1].cos_theta, 0.8), 0.4);
    scattering *= dt;
}