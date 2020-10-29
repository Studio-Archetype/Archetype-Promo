vec4 waterColorSqrt = vec4(WATER_R, WATER_G, WATER_B, 255.0) * WATER_I / 255.0;
vec4 waterColor = waterColorSqrt * waterColorSqrt;

const float waterAlpha = WATER_A;
const float waterFog = WATER_F;