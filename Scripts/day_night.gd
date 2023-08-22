@tool
extends WorldEnvironment

const START_TIME_DAY: float = 0
const END_TIME_DAY: float = 2400

@export var time_speed: float = 50
@export_range(START_TIME_DAY,END_TIME_DAY,0.01) var timeOfDay: float = 1200.0
@export_range(0.001,0.5,0.001) var sunSize: float = 0.05
@export_range(0.001,0.5,0.001) var moonSize: float = 0.02
var sky_shader_material: ShaderMaterial
var sun_position: float

# update sun moon rotation
func update_rotation():
	var hour: float = remap(timeOfDay, 0.0, 2400.0, 0.0, 1.0)
#	$SunMoon.rotation_degrees.y = skyRotation
	$SunMoon.rotation_degrees.x = hour * 360

func update_sky():
	# update sun and moon size param of the shader
	sky_shader_material.set_shader_parameter("sun_size", sunSize)
	sky_shader_material.set_shader_parameter("moon_size", moonSize)
	# since the sun position.y will vary between -1 and 1
	# this map the value to a range between 0 and 1
	sun_position = $SunMoon/Sun.global_position.y /2.0 +0.5
	sky_shader_material.set_shader_parameter("sun_pos", sun_position)
	# this is the direction of the light, it is used by the shader to render the sun
	var light_direction: Vector3 = $SunMoon.basis.y
	sky_shader_material.set_shader_parameter("sun_dir", light_direction)
	

# update timeOfDay using delta and time_speed, making the day cycle independent from fps
func update_time_of_day(delta:float):
	timeOfDay = fmod(timeOfDay+delta*time_speed, END_TIME_DAY)
#	print(timeOfDay)
	

# Called when the node enters the scene tree for the first time.
func _ready():
	sky_shader_material = self.environment.sky.get_material()
	update_rotation()
	update_sky()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	update_time_of_day(delta)
	update_rotation()
	update_sky()
