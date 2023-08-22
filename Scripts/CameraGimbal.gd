extends Node3D


@export var sensitivity:float = 0.005
@export var invert_x:bool = false
@export var invert_y:bool = false
@export var do_pixelate: bool = true
@export var target: NodePath

# Called when the node enters the scene tree for the first time.
func _ready():
	# this way the pointer is not visible
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _process(delta):
	if target:
		global_transform.origin = get_node(target).global_transform.origin
	if do_pixelate:
		if !$InnerGimbal/Camera3D/pixelate.visible:
			$InnerGimbal/Camera3D/pixelate.visible=true
	else:
		if $InnerGimbal/Camera3D/pixelate.visible:
			$InnerGimbal/Camera3D/pixelate.visible=false

# character rotation
func _input(event):
	if event is InputEventMouseMotion:
		if event.relative.x != 0:
			var dir = 1 if invert_x else -1
			rotate_y(dir * event.relative.x * sensitivity)
			
		if event.relative.y != 0:
			var dir = 1 if invert_y else -1
			var y_rotation = clamp(event.relative.y, -30, 30)
			$InnerGimbal.rotate_x(dir * y_rotation * sensitivity)
#			$InnerGimbal.rotation.x = clamp($InnerGimbal.rotation.x, -1, -0.01)
			$InnerGimbal.rotation.z = 0
			
