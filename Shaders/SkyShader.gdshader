shader_type sky;

uniform sampler2D gradient: hint_default_black;
uniform float sun_pos = 0.5;
uniform vec3 sun_dir;
uniform float sun_size;
uniform float moon_size;

uniform vec3 sky_color: source_color;
uniform vec3 horizon_color: source_color;

void sky() {
	float col = clamp(EYEDIR.y/0.05, 0.0, 1.0);
	vec3 sampled_color = texture(gradient, vec2(sun_pos, 0.0)).rgb;
	vec3 final_color = mix(horizon_color, sampled_color, col);
	COLOR = final_color;

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
