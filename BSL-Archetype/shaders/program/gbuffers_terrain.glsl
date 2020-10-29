/* 
BSL Shaders v7.1.05 by Capt Tatsu 
https://bitslablab.com 
*/ 

//Settings//
#include "/lib/settings.glsl"

//Fragment Shader///////////////////////////////////////////////////////////////////////////////////
#ifdef FSH

//Extensions//

//Varyings//
varying float mat, recolor;

varying vec2 texCoord, lmCoord;

varying vec3 normal;
varying vec3 sunVec, upVec;

varying vec4 color;

#ifdef ADVANCED_MATERIALS
varying float dist;

varying vec3 binormal, tangent;
varying vec3 viewVector;

varying vec4 vTexCoord, vTexCoordAM;
#endif

//Uniforms//
uniform int blockEntityId;
uniform int frameCounter;
uniform int isEyeInWater;
uniform int worldTime;

uniform float frameTimeCounter;
uniform float nightVision;
uniform float rainStrength;
uniform float screenBrightness; 
uniform float shadowFade;
uniform float timeAngle, timeBrightness;
uniform float viewWidth, viewHeight;

uniform ivec2 eyeBrightnessSmooth;

uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform mat4 shadowProjection;
uniform mat4 shadowModelView;

uniform sampler2D texture;

#ifdef ADVANCED_MATERIALS
uniform sampler2D specular;
uniform sampler2D normals;

#ifdef REFLECTION_RAIN
uniform float wetness;

uniform vec3 cameraPosition;

uniform mat4 gbufferModelView;

uniform sampler2D noisetex;
#endif
#endif

//Common Variables//
float eBS = eyeBrightnessSmooth.y / 240.0;
float sunVisibility  = clamp(dot( sunVec,upVec) + 0.05, 0.0, 0.1) * 10.0;
float moonVisibility = clamp(dot(-sunVec,upVec) + 0.05, 0.0, 0.1) * 10.0;

#ifdef WORLD_TIME_ANIMATION
float frametime = float(worldTime) * 0.05 * ANIMATION_SPEED;
#else
float frametime = frameTimeCounter * ANIMATION_SPEED;
#endif

#ifdef ADVANCED_MATERIALS
vec2 dcdx = dFdx(texCoord.xy);
vec2 dcdy = dFdy(texCoord.xy);
#endif

vec3 lightVec = sunVec * ((timeAngle < 0.5325 || timeAngle > 0.9675) ? 1.0 : -1.0);

//Common Functions//
float GetLuminance(vec3 color){
	return dot(color,vec3(0.299, 0.587, 0.114));
}

float InterleavedGradientNoise(){
	float n = 52.9829189 * fract(0.06711056 * gl_FragCoord.x + 0.00583715 * gl_FragCoord.y);
	return fract(n + frameCounter / 8.0);
}

//Includes//
#include "/lib/color/blocklightColor.glsl"
#include "/lib/color/dimensionColor.glsl"
#include "/lib/util/spaceConversion.glsl"
#include "/lib/lighting/forwardLighting.glsl"

#if AA == 2
#include "/lib/util/jitter.glsl"
#endif

#ifdef ADVANCED_MATERIALS
#include "/lib/util/encode.glsl"
#include "/lib/surface/directionalLightmap.glsl"
#include "/lib/surface/ggx.glsl"
#include "/lib/surface/materialGbuffers.glsl"
#include "/lib/surface/parallax.glsl"

#ifdef REFLECTION_RAIN
#include "/lib/reflections/rainPuddles.glsl"
#endif
#endif

//Program//
void main(){
    vec4 albedo = texture2D(texture, texCoord) * vec4(color.rgb, 1.0);

	vec3 newNormal = normal;

	#ifdef ADVANCED_MATERIALS
	vec2 newCoord = vTexCoord.st * vTexCoordAM.pq + vTexCoordAM.st;
	float parallaxFade = clamp((dist - PARALLAX_DISTANCE) / 32.0, 0.0, 1.0);
	float skipParallax = float(blockEntityId == 63);
	
	#ifdef PARALLAX
	newCoord = GetParallaxCoord(parallaxFade);
	albedo = texture2DGradARB(texture, newCoord, dcdx, dcdy) * vec4(color.rgb, 1.0);
	#endif

	float smoothness = 0.0, metalData = 0.0, skymapMod = 0.0;
	vec3 rawAlbedo = vec3(0.0);
	#endif

	if (albedo.a > 0.1){
		#ifdef TOON_LIGHTMAP
		vec2 lightmap = clamp(floor(lmCoord * 14.999 * (0.75 + 0.25 * color.a)) / 14, 0.0, 1.0);
		#else
		vec2 lightmap = clamp(lmCoord, vec2(0.0), vec2(1.0));
		#endif
		
		float foliage  = float(mat > 0.98 && mat < 1.02);
		float emissive = float(mat > 1.98 && mat < 2.02);
		float lava     = float(mat > 2.98 && mat < 3.02);
		
		#ifndef SHADOW_SUBSURFACE
		foliage = 0.0;
		#endif

		vec3 screenPos = vec3(gl_FragCoord.xy / vec2(viewWidth, viewHeight), gl_FragCoord.z);
		#if AA == 2
		vec3 viewPos = ToNDC(vec3(TAAJitter(screenPos.xy,-0.5),screenPos.z));
		#else
		vec3 viewPos = ToNDC(screenPos);
		#endif
		vec3 worldPos = ToWorld(viewPos);

		#ifdef ADVANCED_MATERIALS
		float metalness = 0.0, f0 = 0.0, ao = 1.0;
		vec3 normalMap = vec3(0.0);
		GetMaterials(smoothness, metalness, f0, metalData, emissive, ao, normalMap,
					 newCoord, dcdx, dcdy);
		
		mat3 tbnMatrix = mat3(tangent.x, binormal.x, normal.x,
							  tangent.y, binormal.y, normal.y,
							  tangent.z, binormal.z, normal.z);

		if (normalMap.x > -0.999 && normalMap.y > -0.999)
			newNormal = clamp(normalize(normalMap * tbnMatrix), vec3(-1.0), vec3(1.0));
		#endif

		#ifdef EMISSIVE_RECOLOR
		float ec = length(albedo.rgb);
		if (recolor > 0.5){
			albedo.rgb = blocklightCol * (ec * 0.3 / BLOCKLIGHT_I) + ec * 0.3;
		}
		if (lava > 0.5){
			ec *= sqrt(ec);
			albedo.rgb = blocklightCol * (ec / BLOCKLIGHT_I) + ec * 0.025;
		}
		#else
		if (recolor > 0.5) albedo.rgb *=  0.7;
		#endif

    	albedo.rgb = pow(albedo.rgb, vec3(2.2));

		#ifdef WHITE_WORLD
		albedo.rgb = vec3(0.5);
		#endif

		float NdotL = clamp(dot(newNormal, lightVec) * 1.01 - 0.01, 0.0, 1.0);

		float quarterNdotU = clamp(0.25 * dot(newNormal, upVec) + 0.75, 0.5, 1.0);
			  quarterNdotU*= quarterNdotU * (foliage > 0.5 ? 1.8 : 1.0);

		float parallaxShadow = 1.0;
		#ifdef ADVANCED_MATERIALS
		rawAlbedo = albedo.rgb * 0.999 + 0.001;
		albedo.rgb *= ao;

		#ifdef REFLECTION_SPECULAR
		float roughnessSqr = (1.0 - smoothness) * sqrt(1.0 - smoothness);
		albedo.rgb *= (1.0 - metalness * (1.0 - roughnessSqr));
		#endif

		float doParallax = 0.0;
		#ifdef SELF_SHADOW
		#ifdef OVERWORLD
		doParallax = float(lightmap.y > 0.0 && NdotL > 0.0);
		#endif
		#ifdef END
		doParallax = float(NdotL > 0.0);
		#endif
		
		if (doParallax > 0.5){
			parallaxShadow = GetParallaxShadow(parallaxFade, newCoord, lightVec, tbnMatrix);
		}
		#endif

		#ifdef DIRECTIONAL_LIGHTMAP
		mat3 lightmapTBN = GetLightmapTBN(viewPos);
		lightmap.x = DirectionalLightmap(lightmap.x, lmCoord.x, newNormal, lightmapTBN);
		lightmap.y = DirectionalLightmap(lightmap.y, lmCoord.y, newNormal, lightmapTBN);
		#endif
		#endif
		
		vec3 shadow = vec3(0.0);
		GetLighting(albedo.rgb, shadow, viewPos, worldPos, lightmap, color.a, NdotL, quarterNdotU,
					parallaxShadow, emissive + lava, foliage);

		#ifdef ADVANCED_MATERIALS
		float puddles = 0.0;
		#if defined REFLECTION_RAIN && defined OVERWORLD
		float NdotU = clamp(dot(newNormal, upVec),0.0,1.0);

		#if REFLECTION_RAIN_TYPE == 0
		puddles = GetPuddles(worldPos) * NdotU * wetness;
		#else
		puddles = NdotU * wetness;
		#endif
		
		#ifdef WEATHER_PERBIOME
		float weatherweight = isCold + isDesert + isMesa + isSavanna;
		puddles *= 1.0 - weatherweight;
		#endif
		
		puddles *= clamp(lightmap.y * 32.0 - 31.0, 0.0, 1.0);
		
		smoothness = mix(smoothness, 1.0, puddles);
		f0 = max(f0, puddles * 0.02);

		albedo.rgb *= 1.0 - (puddles * 0.15);

		if (puddles > 0.001 && rainStrength > 0.001){
			mat3 tbnMatrix = mat3(tangent.x, binormal.x, normal.x,
							  tangent.y, binormal.y, normal.y,
							  tangent.z, binormal.z, normal.z);

			vec3 puddleNormal = GetPuddleNormal(worldPos, viewPos, tbnMatrix);
			newNormal = normalize(mix(newNormal, puddleNormal, puddles * rainStrength));
		}
		#endif

		skymapMod = lightmap.y * lightmap.y * (3.0 - 2.0 * lightmap.y);

		#if defined OVERWORLD || defined END
		#ifdef OVERWORLD
		vec3 lightME = mix(lightMorning, lightEvening, mefade);
		vec3 lightDayTint = lightDay * lightME * LIGHT_DI;
		vec3 lightDaySpec = mix(lightME, sqrt(lightDayTint), timeBrightness);
		vec3 specularColor = mix(sqrt(lightNight),
									lightDaySpec,
									sunVisibility);
		specularColor *= specularColor;
		#endif
		#ifdef END
		vec3 specularColor = endCol;
		#endif
		
		albedo.rgb += GetSpecularHighlight(smoothness, metalness, f0, specularColor, rawAlbedo,
							 			   shadow, normal, viewPos);
		#endif
		
		#if defined REFLECTION_SPECULAR && defined REFLECTION_ROUGH
		if (normalMap.x > -0.999 && normalMap.y > -0.999){
			normalMap = mix(vec3(0.0, 0.0, 1.0), normalMap, smoothness);
			newNormal = mix(normalMap * tbnMatrix, newNormal, 1.0 - pow(1.0 - puddles, 4.0));
			newNormal = clamp(normalize(newNormal), vec3(-1.0), vec3(1.0));
		}
		#endif
		#endif
	} else albedo.a = 0.0;

    /* DRAWBUFFERS:0 */
    gl_FragData[0] = albedo;

	#if defined ADVANCED_MATERIALS && defined REFLECTION_SPECULAR
	/* DRAWBUFFERS:0367 */
	gl_FragData[1] = vec4(smoothness, metalData, skymapMod, 1.0);
	gl_FragData[2] = vec4(EncodeNormal(newNormal), float(gl_FragCoord.z < 1.0), 1.0);
	gl_FragData[3] = vec4(rawAlbedo, 1.0);
	#endif
}

#endif

//Vertex Shader/////////////////////////////////////////////////////////////////////////////////////
#ifdef VSH

//Varyings//
varying float mat, recolor;

varying vec2 texCoord, lmCoord;

varying vec3 normal;
varying vec3 sunVec, upVec;

varying vec4 color;

#ifdef ADVANCED_MATERIALS
varying float dist;

varying vec3 binormal, tangent;
varying vec3 viewVector;

varying vec4 vTexCoord, vTexCoordAM;
#endif

//Uniforms//
uniform int worldTime;

uniform float frameTimeCounter;
uniform float timeAngle;

uniform vec3 cameraPosition;

uniform mat4 gbufferModelView, gbufferModelViewInverse;

#if AA == 2
uniform int frameCounter;

uniform float viewWidth, viewHeight;
#endif

//Attributes//
attribute vec4 mc_Entity;
attribute vec4 mc_midTexCoord;

#ifdef ADVANCED_MATERIALS
attribute vec4 at_tangent;
#endif

//Common Variables//
#ifdef WORLD_TIME_ANIMATION
float frametime = float(worldTime) * 0.05 * ANIMATION_SPEED;
#else
float frametime = frameTimeCounter * ANIMATION_SPEED;
#endif

//Includes//
#include "/lib/vertex/waving.glsl"

#if AA == 2
#include "/lib/util/jitter.glsl"
#endif

#ifdef WORLD_CURVATURE
#include "/lib/vertex/worldCurvature.glsl"
#endif

//Program//
void main(){
	texCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    
	lmCoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
	lmCoord = clamp((lmCoord - 0.03125) * 1.06667, 0.0, 1.0);

	normal = normalize(gl_NormalMatrix * gl_Normal);

	#ifdef ADVANCED_MATERIALS
	binormal = normalize(gl_NormalMatrix * cross(at_tangent.xyz, gl_Normal.xyz) * at_tangent.w);
	tangent  = normalize(gl_NormalMatrix * at_tangent.xyz);
	
	mat3 tbnMatrix = mat3(tangent.x, binormal.x, normal.x,
						  tangent.y, binormal.y, normal.y,
						  tangent.z, binormal.z, normal.z);
								  
	viewVector = tbnMatrix * (gl_ModelViewMatrix * gl_Vertex).xyz;
	
	dist = length(gl_ModelViewMatrix * gl_Vertex);

	vec2 midCoord = (gl_TextureMatrix[0] *  mc_midTexCoord).st;
	vec2 texMinMidCoord = texCoord - midCoord;

	vTexCoordAM.pq  = abs(texMinMidCoord) * 2;
	vTexCoordAM.st  = min(texCoord, midCoord - texMinMidCoord);
	
	vTexCoord.xy    = sign(texMinMidCoord) * 0.5 + 0.5;
	#endif
    
	color = gl_Color;
	
	mat = 0.0; recolor = 0.0;

	if (mc_Entity.x ==  31 || mc_Entity.x ==   6 || mc_Entity.x ==  59 || mc_Entity.x == 175 ||
	   mc_Entity.x == 176 || mc_Entity.x ==  18 || mc_Entity.x == 106 || mc_Entity.x == 111 ||
	   mc_Entity.x ==  83 || mc_Entity.x == 104)
		mat = 1.0;
	if (mc_Entity.x ==  55 || mc_Entity.x == 213 || mc_Entity.x ==  76 || mc_Entity.x ==  50 ||
	   mc_Entity.x ==  91 || mc_Entity.x ==  89 || mc_Entity.x ==  51)
		mat = 2.0;
	if (mc_Entity.x ==  10)
		mat = 3.0;

	if (mc_Entity.x == 213 || mc_Entity.x ==  89 || mc_Entity.x == 138)
		recolor = 1.0;

	if (mc_Entity.x ==  91 || mc_Entity.x ==  89 || mc_Entity.x ==  10 || mc_Entity.x ==  51)
		lmCoord.x = 1.0;
	if (mc_Entity.x ==  62)
		lmCoord.x -= 0.0667;

	if (mc_Entity.x == 300)
		color.a = 1;

	const vec2 sunRotationData = vec2(cos(sunPathRotation * 0.01745329251994), -sin(sunPathRotation * 0.01745329251994));
	float ang = fract(timeAngle - 0.25);
	ang = (ang + (cos(ang * 3.14159265358979) * -0.5 + 0.5 - ang) / 3.0) * 6.28318530717959;
	sunVec = normalize((gbufferModelView * vec4(vec3(-sin(ang), cos(ang) * sunRotationData) * 2000.0, 1.0)).xyz);

	upVec = normalize(gbufferModelView[1].xyz);

	vec4 position = gbufferModelViewInverse * gl_ModelViewMatrix * gl_Vertex;
	
	float istopv = gl_MultiTexCoord0.t < mc_midTexCoord.t ? 1.0 : 0.0;
	position.xyz += WavingBlocks(position.xyz, istopv);

    #ifdef WORLD_CURVATURE
	position.y -= WorldCurvature(position.xz);
    #endif

	gl_Position = gl_ProjectionMatrix * gbufferModelView * position;
	
	#if AA == 2
	gl_Position.xy = TAAJitter(gl_Position.xy, gl_Position.w);
	#endif
}

#endif