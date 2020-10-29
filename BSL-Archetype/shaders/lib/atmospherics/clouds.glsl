#if CLOUDS == 1
float CloudSample(vec2 coord, vec2 wind, float currentStep, float sampleStep, float sunCoverage) {
	float noiseA = texture2D(noisetex, coord * 0.25 + wind).r;
	float noiseB = texture2D(noisetex, coord * 0.45 - wind * 2.0).b;

	float noiseCoverage = abs(currentStep - 0.125) * (currentStep > 0.125 ? 1.14 : 8.0);
	noiseCoverage = noiseCoverage * noiseCoverage * 4.0;
	
	float noise = mix(noiseA * 20.0 + noiseB - noiseCoverage, 21.0, 0.33 * rainStrength);
	float multiplier = CLOUD_THICKNESS * sampleStep * (1.0 - 0.75 * rainStrength);

	noise = max(noise - (sunCoverage * 3.0 + CLOUD_AMOUNT), 0.0) * multiplier;
	noise = noise / pow(pow(noise, 2.5) + 1.0, 0.4);

	return noise;
}

vec4 DrawCloud(vec3 viewPos, float dither, vec3 lightCol, vec3 ambientCol) {
	#if AA == 2
	dither = fract(16.0 * frameTimeCounter + dither);
	#endif

	int samples = 8;
	
	float cloud = 0.0, cloudLighting = 0.0;

	float sampleStep = 1.0 / samples;
	float currentStep = dither * sampleStep;
	
	float VoU = dot(normalize(viewPos), upVec);
	float VoL = dot(normalize(viewPos), lightVec);
	
	float sunCoverage = pow(clamp(abs(VoL) * 2.0 - 1.0, 0.0, 1.0), 12.0) * (1.0 - rainStrength);

	vec2 wind = vec2(
		frametime * CLOUD_SPEED * 0.0005,
		sin(frametime * CLOUD_SPEED * 0.05) * 0.001
	) * CLOUD_HEIGHT / 15.0;

	vec3 cloudColor = vec3(0.0);

	if (VoU > 0.025) {
		vec3 wpos = normalize((gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz);
		for(int i = 0; i < samples; i++) {
			if (cloud > 0.99) break;
			vec3 planeCoord = wpos * ((CLOUD_HEIGHT + currentStep * 4.0) / wpos.y) * 0.004;
			vec2 coord = cameraPosition.xz * 0.00025 + planeCoord.xz;

			float noise = CloudSample(coord, wind, currentStep, sampleStep, sunCoverage);

			float halfVoL = VoL * shadowFade * 0.5 + 0.5;
			float halfVoLSqr = halfVoL * halfVoL;
			float noiseLightFactor = (2.0 - 1.5 * VoL * shadowFade) * CLOUD_THICKNESS / 2.0;
			float sampleLighting = pow(currentStep, 1.125 * halfVoLSqr + 0.875) * 0.8 + 0.2;
			sampleLighting *= 1.0 - pow(noise, noiseLightFactor);

			cloudLighting = mix(cloudLighting, sampleLighting, noise * (1.0 - cloud * cloud));
			cloud = mix(cloud, 1.0, noise);

			currentStep += sampleStep;
		}	
		float scattering = pow(VoL * shadowFade * 0.5 + 0.5, 6.0);
		cloudLighting = mix(cloudLighting, 1.0, (1.0 - cloud * cloud) * scattering * 0.5);
		cloudColor = mix(
			ambientCol * (0.35 * sunVisibility + 0.5),
			lightCol * (0.85 + 1.15 * scattering),
			cloudLighting
		);
		cloudColor *= 1.0 - 0.6 * rainStrength;
		cloud *= clamp(1.0 - exp(-20.0 * VoU + 0.5), 0.0, 1.0) * (1.0 - 0.6 * rainStrength);
	}
	cloudColor *= CLOUD_BRIGHTNESS * (0.5 - 0.25 * (1.0 - sunVisibility) * (1.0 - rainStrength));
	
	return vec4(cloudColor, cloud * cloud * CLOUD_OPACITY);
}
#elif CLOUDS == 2
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

float CloudSample(vec2 coord, vec2 wind, float sunCoverage) {
	float noiseA = SimplexNoise(coord * 0.5 + wind);
	float noiseB = SimplexNoise(coord * 0.25 + wind * 1.4);
	
	float noise = noiseA + noiseB * 2.0;
	float coverage = SimplexNoise(coord * 0.0625 + wind * 2.0) * 0.75 + 0.25;
	float multiplier = CLOUD_THICKNESS * 0.15;

	noise = (1.0 - max(sin(noise * 8.0 + frametime * 0.25), 0.0)) * coverage * multiplier;
	noise = noise / pow(pow(noise, 2.5) + 1.0, 0.4);

	return noise;
}

vec4 DrawCloud(vec3 viewPos, vec3 color) {
	int samples = 2;
	
	float cloud = 0.0, cloudLighting = 1.0;

	float sampleStep = 1.0 / samples;
	float currentStep = 0.0;
	
	float VoU = dot(normalize(viewPos), upVec);
	float VoL = dot(normalize(viewPos), lightVec);
	
	float sunCoverage = pow(clamp(abs(VoL) * 2.0 - 1.0, 0.0, 1.0), 12.0) * (1.0 - rainStrength);

	vec2 wind = vec2(
		frametime * CLOUD_SPEED * 0.0005,
		sin(frametime * CLOUD_SPEED * 0.05) * 0.001
	) * CLOUD_HEIGHT / 15.0;

	vec3 cloudColor = vec3(0.0);

	if (VoU > 0.025) {
		vec3 wpos = normalize((gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz);
		for(int i = 0; i < samples; i++) {
			if (cloud > 0.99) break;
			vec3 planeCoord = wpos * ((CLOUD_HEIGHT + currentStep * 4.0) / wpos.y) * 0.35;
			vec2 coord = cameraPosition.xz * 0.04 + planeCoord.xz + 17.0 * i;
			coord = vec2(coord.x * 0.7, coord.y + sin(coord.x * 0.125));

			float noise = CloudSample(coord, wind, sunCoverage);

			float sampleLighting = 0.35 * pow(4.0, i);
			sampleLighting *= sampleLighting;

			cloudLighting = mix(cloudLighting, sampleLighting, noise * (1.0 - cloud * cloud));
			cloud = mix(cloud, 1.0, noise);
			currentStep += sampleStep;
		}

		cloud *= clamp(1.0 - exp(-10.0 * VoU + 0.5), 0.0, 1.0) * (1.0 - 0.6 * rainStrength);
	}
	cloudLighting *= cloudLighting;
	
	return vec4(color * cloudLighting, cloud * CLOUD_OPACITY);
}
#endif

float GetNoise(vec2 pos) {
	return fract(sin(dot(pos, vec2(12.9898, 4.1414))) * 43758.5453);
}

void DrawStars(inout vec3 color, vec3 viewPos) {
	vec3 wpos = vec3(gbufferModelViewInverse * vec4(viewPos, 1.0));
	vec3 planeCoord = wpos / (wpos.y + length(wpos.xz));
	vec2 wind = vec2(frametime, 0.0);
	vec2 coord = planeCoord.xz * 0.4 + cameraPosition.xz * 0.0001 + wind * 0.00125;
	coord = floor(coord * 1024.0) / 1024.0;
	
	float VoU = clamp(dot(normalize(viewPos), normalize(upVec)), 0.0, 1.0);
	float multiplier = sqrt(sqrt(VoU)) * 5.0 * (1.0 - rainStrength) * moonVisibility;
	
	float star = 1.0;
	if (VoU > 0.0) {
		star *= GetNoise(coord.xy);
		star *= GetNoise(coord.xy + 0.10);
		star *= GetNoise(coord.xy + 0.23);
	}
	star = clamp(star - 0.8125, 0.0, 1.0) * multiplier;
		
	color += star * pow(lightNight, vec3(0.8));
}