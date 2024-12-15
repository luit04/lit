vec4 a_color0 : COLOR0;
vec3 a_position : POSITION;
vec2 a_texcoord0 : TEXCOORD0;
vec2 a_texcoord1 : TEXCOORD1;

vec4 i_data0 : TEXCOORD7;
vec4 i_data1 : TEXCOORD6;
vec4 i_data2 : TEXCOORD5;

vec4 v_color0 : COLOR0;
centroid vec2 v_texcoord0 : TEXCOORD0;
vec2 v_lightmapUV : TEXCOORD1;

float v_ambient_occlusion : V_AMBIENT_OCCLUSION;
float v_time : V_TIME;
float v_ev : V_EV;
vec3 v_position : V_POSITION;
vec3 v_world_position : V_WORLD_POSITION;
vec3 v_sun_direction : V_SUN_DIRECTION;

vec3 v_sun_radiance : V_SUN_RADIANCE;
vec3 v_sun_ambient : V_SUN_AMBIENT;
vec3 v_moon_radiance : V_MOON_RADIANCE;
vec3 v_moon_ambient : V_MOON_AMBIENT;