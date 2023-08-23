shader_type sky;

uniform sampler2D gradient: hint_default_black;
uniform sampler2D scattering_texture: hint_default_black;
uniform float sun_pos = 0.5;
uniform vec3 sun_dir;
uniform float sun_size;
uniform float moon_size;

uniform vec3 sky_color: source_color;
uniform vec3 horizon_color: source_color;

// setup light scattering
vec3 scatterLight(vec3 vertexColor, vec2 skyUV) {
	// clamp lower hemisphere vertex normal Y to have solid color
	float clampedColor = 0.0;
	if (vertexColor.y < 0.0) { clampedColor = 0.0001; }
	else { clampedColor = vertexColor.y; }

	float vertexSlope = pow((1.0 - vertexColor.y), 2);
	
	// sun
	float UVx = mix(vertexSlope, 1.0, 0.5);
	float UVy = clamp(LIGHT0_DIRECTION.y/ -2.0, -0.495,0.495) + 0.5;
	// moon
	float UVx2 = mix(vertexSlope, 1.0, 0.1);
	float UVy2 = clamp(LIGHT0_DIRECTION.y/ -2.0, -0.495,0.495) + 0.5;

	// tmp
	// vec3 scatterColor = vec3(38.0,38.0,38.0);
	// vec3 scatterColor2 = vec3(2.0,2.0,2.0);

	// sample texture and apply scatter color adjustments
	vec3 sunScatter = texture(scattering_texture, vec2(UVx, UVy)).rgb; // * scatterColor;
	vec3 moonScatter = texture(scattering_texture, vec2(UVx2, UVy2)).rgb; // * scatterColor2 + 0.15;
	vec3 lightScattered = sunScatter + moonScatter;
	// lightScattered = lightScattered * baseColor.rgb;
	return lightScattered;
}

void sky() {
	vec3 scatteringMul = scatterLight(EYEDIR, SKY_COORDS);
	float col = clamp(EYEDIR.y/0.05, 0.0, 1.0);
	// TODO do the same with another gradient for the albedo to make the sky darker or brighter
	vec3 sampled_color = texture(gradient, vec2(sun_pos, 0.0)).rgb;
	vec3 final_color = mix(horizon_color, sampled_color, col);
	COLOR = scatteringMul*final_color;

	// compare the sun direction (basis.y) and the EYEDIR
	// since they are normalized vector this is equivalent
	// to applying cosine similarity to them 
	float compareDirections = dot(sun_dir, EYEDIR);
	// when they are facing the same direction (compareDirections==1) render the sun
	if (compareDirections > (1.0 - sun_size) && 
		compareDirections < (1.0 + sun_size)
	)
	{
		COLOR = vec3(1,1,1);
	}
	// when they are facing opposing direction, render the moon 
	else if (
		compareDirections < (-1.0 + moon_size) && 
		compareDirections > (-1.0 - moon_size)
	)
	{
		COLOR = vec3(0,0,0);
	}
}
