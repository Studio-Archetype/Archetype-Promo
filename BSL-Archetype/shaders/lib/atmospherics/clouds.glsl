float CloudNoise(vec2 coord, vec2 wind) {
	float noise = texture2D(noisetex, coord * 0.5      + wind * 0.55).x;
		  noise+= texture2D(noisetex, coord * 0.25     + wind * 0.45).x * 2.0;
		  noise+= texture2D(noisetex, coord * 0.125    + wind * 0.35).x * 3.0;
		  noise+= texture2D(noisetex, coord * 0.0625   + wind * 0.25).x * 4.0;
		  noise+= texture2D(noisetex, coord * 0.03125  + wind * 0.15).x * 5.0;
		  noise+= texture2D(noisetex, coord * 0.016125 + wind * 0.05).x * 6.0;
	return noise;
}

float CloudCoverage(float noise, float VoU, float coverage) {
	float noiseMix = mix(noise, 21.0, 0.33 * rainStrength);
	float noiseFade = clamp(sqrt(VoU * 10.0), 0.0, 1.0);
	float noiseCoverage = ((coverage * coverage) + CLOUD_AMOUNT);
	float multiplier = 1.0 - 0.5 * rainStrength;

	return max(noiseMix * noiseFade - noiseCoverage, 0.0) * multiplier;
}

vec4 DrawCloud(vec3 viewPos, float dither, vec3 lightCol, vec3 ambientCol) {
	#if AA == 2
	dither = fract(16.0 * frameTimeCounter + dither);
	#endif

	int samples = 6;
	
	float cloud = 0.0, cloudGradient = 0.0;

	float sampleStep = 1.0 / samples;
	float gradientMix = dither * sampleStep;
	
	float VoU = dot(normalize(viewPos), upVec);
	float VoL = dot(normalize(viewPos), sunVec);
	
	float noiseMultiplier = CLOUD_THICKNESS * 0.2 * 6.0 / samples;

	vec2 wind = vec2(
		frametime * CLOUD_SPEED * 0.001,
		sin(frametime * CLOUD_SPEED * 0.05) * 0.002
	) * CLOUD_HEIGHT / 15.0;

	vec3 cloudColor = vec3(0.0);

	if (VoU > 0.1) {
		vec3 wpos = normalize((gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz);
		for(int i = 0; i < samples; i++) {
			if (cloud > 0.99) break;
			float sampleHeight = (i + dither) * 4.5 / samples;
			vec3 planeCoord = wpos * ((CLOUD_HEIGHT + sampleHeight) / wpos.y) * 0.004;
			vec2 coord = cameraPosition.xz * 0.00025 + planeCoord.xz;
			float coverage = float(i - samples / 2.0 + dither) * 4.0 / samples;

			float noise = CloudNoise(coord, wind);
				  noise = CloudCoverage(noise, VoU, coverage) * noiseMultiplier;
				  noise = noise / pow(pow(noise, 2.5) + 1.0, 0.4);

			cloudGradient = mix(
				cloudGradient,
				mix(gradientMix * gradientMix, 1.0 - noise, 0.25),
				noise * (1.0 - cloud * cloud)
			);
			cloud = mix(cloud, 1.0, noise);
			gradientMix += sampleStep;
		}	
		float scattering = pow(VoL * 0.5 * (2.0 * sunVisibility - 1.0) + 0.5, 6.0);
		cloudColor = mix(
			ambientCol * (0.5 * sunVisibility + 0.5),
			lightCol * (1.0 + scattering),
			cloudGradient * cloud
		);
		cloudColor *= 1.0 - 0.6 * rainStrength;
		cloud *= sqrt(sqrt(clamp(VoU * 10.0 - 1.0, 0.0, 1.0))) * (1.0 - 0.6 * rainStrength);
	}
	cloudColor *= CLOUD_BRIGHTNESS * (0.5 - 0.25 * (1.0 - sunVisibility) * (1.0 - rainStrength));

	return vec4(cloudColor, cloud * cloud * CLOUD_OPACITY);
}

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

float AuroraNoise(vec2 coord, vec2 wind) {
	float noise = texture2D(noisetex, coord * 0.175   + wind * 0.25).x;
		  noise+= texture2D(noisetex, coord * 0.04375 + wind * 0.15).x * 5.0;

	return noise;
}

vec3 DrawAurora(vec3 viewPos, float dither, int samples) {
	#if AA == 2
	dither = fract(16.0 * frameTimeCounter + dither);
	#endif
	
	float gradientMix = dither / samples;
	float VoU = dot(normalize(viewPos), upVec);
	float visibility = moonVisibility * (1.0 - rainStrength) * (1.0 - rainStrength);

	#ifdef WEATHER_PERBIOME
	visibility *= isCold * isCold;
	#endif

	vec2 wind = vec2(
		frametime * CLOUD_SPEED * 0.000125,
		sin(frametime * CLOUD_SPEED * 0.05) * 0.00025
	);

	vec3 aurora = vec3(0.0);

	if (VoU > 0.0 && visibility > 0.0) {
		vec3 wpos = normalize((gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz);
		for(int i = 0; i < samples; i++) {
			vec3 planeCoord = wpos * ((8.0 + (i + dither) * 7.0 / samples) / wpos.y) * 0.004;
			vec2 coord = cameraPosition.xz * 0.00005 + planeCoord.xz;

			float noise = AuroraNoise(coord, wind);
				  noise = max(1.0 - 1.5 / (1.0 - VoU * 0.8) * abs(noise - 3.0), 0.0);
			
			if(noise > 0.0) {
				noise *= texture2D(noisetex, coord * 0.25 + wind * 0.25).x;
				noise *= 0.5 * texture2D(noisetex, coord + wind * 16.0).x + 0.75;
				noise = noise * noise * 3.0 / samples;
				noise *= max(sqrt(1.0 - length(planeCoord.xz) * 3.75), 0.0);

				vec3 cloudColor = mix(
					vec3(0.1, 1.0, 0.5),
					vec3(0.1, 0.1, 1.0),
					pow(gradientMix, 0.4)
				);
				aurora += noise * cloudColor * exp2(-6.0 * i / samples);
			}
			gradientMix += 1.0 / samples;
		}
	}

	return aurora * visibility;
}