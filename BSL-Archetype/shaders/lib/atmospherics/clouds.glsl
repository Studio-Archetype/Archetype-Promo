//Simplex Noise from https://thebookofshaders.com/11/
vec3 mod289(vec3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec2 mod289(vec2 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec3 permute(vec3 x) { return mod289(((x*34.0)+1.0)*x); }

float SimplexNoise(vec2 coord) {
    const vec4 C = vec4(0.211324865405187,  // (3.0-sqrt(3.0))/6.0
                        0.366025403784439,  // 0.5*(sqrt(3.0)-1.0)
                        -0.577350269189626,  // -1.0 + 2.0 * C.x
                        0.024390243902439); // 1.0 / 41.0
    vec2 i  = floor(coord + dot(coord, C.yy) );
    vec2 x0 = coord - i + dot(i, C.xx);
    vec2 i1;
    i1 = (x0.x > x0.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
    vec4 x12 = x0.xyxy + C.xxzz;
    x12.xy -= i1;
    i = mod289(i); // Avoid truncation effects in permutation
    vec3 p = permute( permute( i.y + vec3(0.0, i1.y, 1.0 ))
        + i.x + vec3(0.0, i1.x, 1.0 ));

    vec3 m = max(0.5 - vec3(dot(x0,x0), dot(x12.xy,x12.xy), dot(x12.zw,x12.zw)), 0.0);
    m = m*m ;
    m = m*m ;
    vec3 x = 2.0 * fract(p * C.www) - 1.0;
    vec3 h = abs(x) - 0.5;
    vec3 ox = floor(x + 0.5);
    vec3 a0 = x - ox;
    m *= 1.79284291400159 - 0.85373472095314 * ( a0*a0 + h*h );
    vec3 g;
    g.x  = a0.x  * x0.x  + h.x  * x0.y;
    g.yz = a0.yz * x12.xz + h.yz * x12.yw;
    return 130.0 * dot(m, g) * 0.5 + 0.5;
}

float CloudNoise(vec2 coord, vec2 wind){
	float noise = SimplexNoise(coord*0.5      + wind);
		  noise+= SimplexNoise(coord*0.25     + wind * 1.4) * 2.0;
	return noise;
}

float CloudCoverage(float noise, float coverage, float cosT){
	return (1.0 - max(sin(noise * 8.0 + frametime * 0.25), 0.0)) * coverage;
}

vec4 DrawCloud(vec3 viewPos, vec3 color){
	float cosT = dot(normalize(viewPos), upVec);
	float cosS = dot(normalize(viewPos), sunVec);
	
	float cloud = 0.0;
	float cloudGradient = 1.0;
	float gradientMix = 0.35;
	float colorMultiplier = CLOUD_BRIGHTNESS * (0.5 - 0.25 * (1.0 - sunVisibility) * (1.0 - rainStrength));
	float noiseMultiplier = CLOUD_THICKNESS * 0.2;

	vec2 wind = vec2(frametime * CLOUD_SPEED * 0.01,
				     sin(frametime * CLOUD_SPEED * 0.05) * 0.02) * CLOUD_HEIGHT / 15.0;

	if (cosT > 0.0){
		vec3 wpos = normalize((gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz);
		for(int i = 0; i < 2; i++) {
			vec3 planeCoord = wpos * ((CLOUD_HEIGHT + 4.0 * i) / wpos.y) * 0.35;
			vec2 coord = cameraPosition.xz * 0.04 + planeCoord.xz + 17.0 * i;
			coord = vec2(coord.x * 0.7, coord.y + sin(coord.x * 0.125));

			float noise = CloudNoise(coord, wind);
			float coverage = SimplexNoise(coord * 0.0625 + wind * 2.0) * 0.75 + 0.25;
				  noise = CloudCoverage(noise, coverage, cosT) * noiseMultiplier;

			cloudGradient = mix(cloudGradient, gradientMix * gradientMix, noise * (1.0 - cloud * cloud));
			cloud = mix(cloud, 1.0, noise);
			gradientMix *= 4.0;
		}
		cloud *= cosT * (1.0 - 0.6 * rainStrength);
	}
	cloudGradient *= cloudGradient;

	return vec4(color * cloudGradient, cloud * CLOUD_OPACITY);
}

float GetNoise(vec2 pos){
	return fract(sin(dot(pos, vec2(12.9898, 4.1414))) * 43758.5453);
}

void DrawStars(inout vec3 color, vec3 viewPos){
	vec3 wpos = vec3(gbufferModelViewInverse * vec4(viewPos, 1.0));
	vec3 planeCoord = wpos / (wpos.y + length(wpos.xz));
	vec2 wind = vec2(frametime, 0.0);
	vec2 coord = planeCoord.xz * 0.4 + cameraPosition.xz * 0.0001 + wind * 0.00125;
	coord = floor(coord*1024.0)/1024.0;
	
	float NdotU = max(dot(normalize(viewPos), normalize(upVec)), 0.0);
	float multiplier = sqrt(sqrt(NdotU)) * 5.0 * (1.0 - rainStrength) * moonVisibility;
	
	float star = 1.0;
	if (NdotU > 0.0){
		star *= GetNoise(coord.xy);
		star *= GetNoise(coord.xy+0.1);
		star *= GetNoise(coord.xy+0.23);
	}
	star = max(star - 0.825, 0.0) * multiplier;
		
	color += star * pow(lightNight, vec3(0.8));
}