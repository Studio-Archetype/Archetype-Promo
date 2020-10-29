vec4 RoughReflection(vec3 viewPos, vec3 normal, float dither, float smoothness, sampler2D colortex){
    vec4 color = vec4(0.0);

    vec4 pos = Raytrace(depthtex0, viewPos, normal, dither, 4, 1.0, 0.1, 2.0);
	float border = clamp(1.0 - pow(cdist(pos.st), 50.0 * sqrt(smoothness)), 0.0, 1.0);
	
	if (pos.z < 1.0 - 1e-5){

		#ifdef REFLECTION_ROUGH
		float dist = 1.0 - exp(-0.125 * (1.0 - smoothness) * pos.a);
		float lod = log2(viewHeight / 8.0 * (1.0 - smoothness) * dist);
		#else
		float lod = 0.0;
		#endif

		if (lod < 1.0){
			color.a = texture2DLod(colortex6, pos.st, 1.0).b;
			if (color.a > 0.001) color.rgb = texture2DLod(colortex, pos.st, 1.0).rgb;
		}else{
			for(int i = -2; i <= 2; i++){
				for(int j = -2; j <= 2; j++){
					vec2 refOffset = vec2(i, j) * pow(2.0, lod - 1.0) / vec2(viewWidth, viewHeight);
					vec2 refCoord = pos.st + refOffset;
					float alpha = texture2DLod(colortex6, refCoord, lod).b;
					if (alpha > 0.001){
						color.rgb += texture2DLod(colortex, refCoord, max(lod - 1.0, 0.0)).rgb;
						color.a += alpha;
					}
				}
			}
			color /= 25.0;
		}
		
		color *= color.a;
		color.a *= border;
	}
	
    return color;
}