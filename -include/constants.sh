#define PI                              3.141592653589793

#define SUN_ILLUMINANCE                 12.0
#define MOON_ILLUMINANCE                0.05
#define STARMAP_ILLUMINANCE             0.02

#define ATLAS_SIZE                      vec2(4096.0, 4096.0)
#define SKY_TEXTURE_SIZE                vec2(1024.0, 1024.0)
#define STARMAP_TEXTURE_SIZE            vec2(4096.0, 2048.0)
#define NOISE_TEXTURE_SIZE              vec2(1024.0, 1024.0)
#define LUT_TEXTURE_SIZE                vec2(512.0, 512.0)

#define EARTH_RADIUS                    6.360                                   // megameter
#define ATMOSPHERE_RADIUS               6.400                                   // megameter
#define CAMERA_POSITION                 vec3(0.0, 6.361, 0.0)                   // megameter

#define CLOUD_SCATTERING_COEFFICIENT    vec3(1000000.0, 1100000.0, 1200000.0)   // per megameter
#define CLOUD_ABSROPTION_COEFFICIENT    vec3(1000.0, 1000.0, 1000.0)            // per megameter

#define CLOUD_STEPS                     36
#define CLOUD_HEIGHT                    0.0012      // megameter
#define CLOUD_THICKNESS                 0.0001      // megameter