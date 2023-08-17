extends CharacterBody3D

@export var sensitivity:float = 0.3
@export var speed:float = 50
@export var acceleration:float = 5
@export var gravity: float = 0.5

# TODO mixamo to godot -> https://www.youtube.com/watch?v=a5X-M5iOmP8

# Called when the node enters the scene tree for the first time.
func _ready():
	# this way the pointer is not visible
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass

# character rotation
func _input(event):
	if event is InputEventMouseMotion:
		rotate_object_local(Vector3(0, 1, 0), deg_to_rad(-event.relative.x*sensitivity))
#		rotate_object_local(Vector3(1, 0, 0), deg_to_rad(-event.relative.y*sensitivity))
#		rotation.x=clamp(rotation.x,-0.9,0.9)

func _physics_process(delta):
	var head_basis=get_global_transform().basis
	var direction=Vector3()
	direction.y-=gravity
	if Input.is_action_pressed("Up"):
		direction -=head_basis.z 
	if Input.is_action_pressed("Down"):
		direction +=head_basis.z 
	if Input.is_action_pressed("Right"):
		direction +=head_basis.x
	if Input.is_action_pressed("Left"):
		direction -=head_basis.x
	if Input.is_action_pressed('jump'):
		direction += head_basis.y
#	elif Input.is_action_pressed('unjump'):
#		position -= head_basis.y
		
	direction=direction.normalized()
#	if Input.is_anything_pressed():
	velocity=velocity.lerp(direction*speed, acceleration*delta)
#	else:
#		velocity = Vector3.ZERO
		
	move_and_slide()
