extends Node3D


# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	var noises = $Terrain.noise
	$Player/Camera3D/Label3D.text = '''
	\nx=%s\ny=%s\nz=%s
	\n
	continentalness=%s
	erosion=%s
	peakandvalley=%s''' % [$Player.position.x,$Player.position.y,$Player.position.z,
	noises[0],noises[1],noises[2]]
