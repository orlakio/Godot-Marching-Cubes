extends MeshInstance3D

# Settings, references and constants
@export var noise_scale : float = 2.0
@export var noise_offset : Vector3
# define the interpolation between vertices instead of using the avg
@export var iso_level : float = 1
@export var chunk_scale : float = 1000
@export var player : Node3D

const DIRECTIONS : PackedVector3Array = [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]

const resolution : int = 8
const num_waitframes_gpusync : int = 12
const num_waitframes_meshthread : int = 90

const work_group_size : int = 8
const num_voxels_per_axis : int = work_group_size * resolution
const buffer_set_index : int = 0
const triangle_bind_index : int = 0
const params_bind_index : int = 1
const counter_bind_index : int = 2
const lut_bind_index : int = 3
const noise_bind_index : int = 4

# Compute stuff
var rendering_device: RenderingDevice
var shader : RID
var pipeline : RID

var buffer_set : RID
var triangle_buffer : RID
var params_buffer : RID
var counter_buffer : RID
var lut_buffer : RID
var noise_buffer : RID

# Data received from compute shader
var triangle_data_bytes
var counter_data_bytes
var noise_data_bytes
var num_triangles
var noise

var array_mesh : ArrayMesh
var verts = PackedVector3Array()
var normals = PackedVector3Array()

# State
var time : float
var frame : int
var last_compute_dispatch_frame : int
var last_meshthread_start_frame : int
var waiting_for_compute : bool
var waiting_for_meshthread : bool
var thread

func _ready():
	array_mesh = ArrayMesh.new()
	mesh = array_mesh
	
	init_compute()
	run_compute()
	fetch_and_process_compute_data()
	create_mesh()
	print(array_mesh.get_aabb())
	var chunk_bounding_box: AABB = array_mesh.get_aabb()
#	var flooded: PackedVector3Array = _flood_fill(chunk_bounding_box.position, 1, chunk_bounding_box) 
	remove_floating_rocks()
#	print(flooded)

#func _process(delta):
#	if (waiting_for_compute && frame - last_compute_dispatch_frame >= num_waitframes_gpusync):
#		fetch_and_process_compute_data()
#	elif (waiting_for_meshthread && frame - last_meshthread_start_frame >= num_waitframes_meshthread):
#		create_mesh()
#	elif (!waiting_for_compute && !waiting_for_meshthread):
#		run_compute()
#
#	frame += 1
#	time += delta
	
func init_compute():
	rendering_device= RenderingServer.create_local_rendering_device()
	# Load compute shader
	var shader_file : RDShaderFile = load("res://Compute/MarchingCubes.glsl")
	var shader_spirv : RDShaderSPIRV = shader_file.get_spirv()
	shader = rendering_device.shader_create_from_spirv(shader_spirv)
	
	# Create triangles buffer
	const max_tris_per_voxel : int = 5
	const max_triangles : int = max_tris_per_voxel * int(pow(num_voxels_per_axis, 3))
	const bytes_per_float : int = 4
	const floats_per_triangle : int = 4 * 3
	const bytes_per_triangle : int = floats_per_triangle * bytes_per_float
	const max_bytes : int = bytes_per_triangle * max_triangles
	
	triangle_buffer = rendering_device.storage_buffer_create(max_bytes)
	var triangle_uniform = RDUniform.new()
	triangle_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	triangle_uniform.binding = triangle_bind_index
	triangle_uniform.add_id(triangle_buffer)
	
	# Create params buffer
	var params_bytes = PackedFloat32Array(get_params_array()).to_byte_array()
	params_buffer = rendering_device.storage_buffer_create(params_bytes.size(), params_bytes)
	var params_uniform = RDUniform.new()
	params_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	params_uniform.binding = params_bind_index
	params_uniform.add_id(params_buffer)
	
	# Create counter buffer
	var counter = [0]
	var counter_bytes = PackedFloat32Array(counter).to_byte_array()
	counter_buffer = rendering_device.storage_buffer_create(counter_bytes.size(), counter_bytes)
	var counter_uniform = RDUniform.new()
	counter_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	counter_uniform.binding = counter_bind_index
	counter_uniform.add_id(counter_buffer)
	
	# Create lut buffer
	var lut = load_lut("res://Compute/MarchingCubesLUT.txt")
	var lut_bytes = PackedInt32Array(lut).to_byte_array()
	lut_buffer = rendering_device.storage_buffer_create(lut_bytes.size(), lut_bytes)
	var lut_uniform = RDUniform.new()
	lut_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	lut_uniform.binding = lut_bind_index
	lut_uniform.add_id(lut_buffer)
	
	# Create noises buffer
	var noise_tmp = [0.0,0.0,0.0]
	var noise_bytes = PackedFloat32Array(noise_tmp).to_byte_array()
	noise_buffer = rendering_device.storage_buffer_create(noise_bytes.size(), noise_bytes)
	var noise_uniform = RDUniform.new()
	noise_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	noise_uniform.binding = noise_bind_index
	noise_uniform.add_id(noise_buffer)
	
	# Create buffer setter and pipeline
	var buffers = [triangle_uniform, params_uniform, counter_uniform, lut_uniform, noise_uniform]
	buffer_set = rendering_device.uniform_set_create(buffers, shader, buffer_set_index)
	pipeline = rendering_device.compute_pipeline_create(shader)
	
func run_compute():
	# Update params buffer
	var params_bytes = PackedFloat32Array(get_params_array()).to_byte_array()
	rendering_device.buffer_update(params_buffer, 0, params_bytes.size(), params_bytes)
	# Reset counter
	var counter = [0]
	var counter_bytes = PackedFloat32Array(counter).to_byte_array()
	rendering_device.buffer_update(counter_buffer,0,counter_bytes.size(), counter_bytes)

	# Prepare compute list
	var compute_list = rendering_device.compute_list_begin()
	rendering_device.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rendering_device.compute_list_bind_uniform_set(compute_list, buffer_set, buffer_set_index)
	rendering_device.compute_list_dispatch(compute_list, resolution, resolution, resolution)
	rendering_device.compute_list_end()
	
	# Run
	rendering_device.submit()
	last_compute_dispatch_frame = frame
	waiting_for_compute = true

func fetch_and_process_compute_data():
	rendering_device.sync()
	waiting_for_compute = false
	# Get output
	triangle_data_bytes = rendering_device.buffer_get_data(triangle_buffer)
	counter_data_bytes =  rendering_device.buffer_get_data(counter_buffer)
	noise_data_bytes = rendering_device.buffer_get_data(noise_buffer)
	noise = noise_data_bytes.to_float32_array()
	thread = Thread.new()
	thread.start(process_mesh_data)
	waiting_for_meshthread = true
	last_meshthread_start_frame = frame

func process_mesh_data():
	var triangle_data = triangle_data_bytes.to_float32_array()
	num_triangles = counter_data_bytes.to_int32_array()[0]
	var num_verts : int = num_triangles * 3
	verts.resize(num_verts)
	normals.resize(num_verts)
	
	for tri_index in range(num_triangles):
		var i = tri_index * 16
		var posA = Vector3(triangle_data[i + 0], triangle_data[i + 1], triangle_data[i + 2])
		var posB = Vector3(triangle_data[i + 4], triangle_data[i + 5], triangle_data[i + 6])
		var posC = Vector3(triangle_data[i + 8], triangle_data[i + 9], triangle_data[i + 10])
		var norm = Vector3(triangle_data[i + 12], triangle_data[i + 13], triangle_data[i + 14])
		verts[tri_index * 3 + 0] = posA
		verts[tri_index * 3 + 1] = posB
		verts[tri_index * 3 + 2] = posC
		normals[tri_index * 3 + 0] = norm
		normals[tri_index * 3 + 1] = norm
		normals[tri_index * 3 + 2] = norm
	
func create_mesh():
	thread.wait_to_finish()
	waiting_for_meshthread = false
	print("Num tris: ", num_triangles, " FPS: ", Engine.get_frames_per_second())
	
	if len(verts) > 0:
		var mesh_data = []
		mesh_data.resize(Mesh.ARRAY_MAX)
		mesh_data[Mesh.ARRAY_VERTEX] = verts
		mesh_data[Mesh.ARRAY_NORMAL] = normals
		array_mesh.clear_surfaces()
		array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh_data)
	# here assign collision shape
	$StaticBody3D/CollisionShape3D.shape = array_mesh.create_trimesh_shape()

# -----# TODO instead of keeping just the verts, save somewhere the edge (connection between 2 verts) #----- #
func remove_floating_rocks():
	var faces: PackedVector3Array = verts
	# array that contains a dictionary for each subset 
	# of vertices that are not connected
	var vertex_groups: Array[Dictionary] = []
#	var edges_count: Dictionary = {}
	print('starting')
	# iterate over all the vertices
	# there are 3 cases:
	var found_in_groups: PackedInt32Array = []
	var current_index_group: int = -1
	for i in range(0, len(faces), 3):
		found_in_groups = []
		current_index_group = -1
		# save every group index where one of the 3 verts appears
		for j in range(i, i+3):
			current_index_group = get_belonging_vertex_group_index(vertex_groups, faces[j])
			if current_index_group!=-1 and not found_in_groups.has(current_index_group):
				found_in_groups.append(current_index_group)
				
		# case 1. (new group)
		if len(found_in_groups)==0:
			vertex_groups.append({
				faces[i]:null,
				faces[i+1]:null,
				faces[i+2]:null
			})
#			num_groups+=1
		# case 3. (merge existing groups)
		elif len(found_in_groups)>1:
			found_in_groups.sort()
			# iterate from the end to the beginning to prevent problems 
			# caused by removing groups and translating the remaining ones
			for k in range(len(found_in_groups)-1,0,-1): # -1 instead of 0?
				# merge and remove the merged group
				vertex_groups[found_in_groups[k-1]].merge(vertex_groups[found_in_groups[k]]) # si rompe qui!
				vertex_groups.remove_at(found_in_groups[k])
		# case 2. (at least one vertex in existing group)
		elif len(found_in_groups)==1:
			for j in range(i, i+3):
				if not vertex_groups[found_in_groups[0]].has(faces[j]):
					vertex_groups[found_in_groups[0]][faces[j]] = null
		# counts edges appereances
#		for ed in get_edges(faces[i],faces[i+1],faces[i+2]):
#			edges_count[ed] = edges_count[ed]+1 if edges_count.has(ed) else 1
	
	# get the index of the biggest group (the one we want to keep)
	var maxg_index: int = 0
	for gi in len(vertex_groups):
		if len(vertex_groups[gi]) > len(vertex_groups[maxg_index]):
			maxg_index = gi
	print('size: ', len(vertex_groups[maxg_index]))
	print('sizeVerts: ', len(verts))
	
	for v in range(len(verts)-1,-1,-1):
		for vgi in range(len(vertex_groups)):
			# if the index is not of the biggest group and if the group contains the verts, remove it
			if vgi != maxg_index and vertex_groups[vgi].has(verts[v]):
				verts.remove_at(v)
				normals.remove_at(v)
				break
	
	if len(verts) > 0:
		var mesh_data = []
		mesh_data.resize(Mesh.ARRAY_MAX)
		mesh_data[Mesh.ARRAY_VERTEX] = verts
		mesh_data[Mesh.ARRAY_NORMAL] = normals
		array_mesh.clear_surfaces()
		array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh_data)

	


#	# iterate over the edges_count, for every edge count != 2,
#	# check to which group the edge belongs.
#	# at the end, all the groups that didn't have any of those edges, are the group that should be removed
#	var not_closed_groups:Dictionary = {}
#	for e in edges_count:
#		if edges_count[e]!=2:
#			# check if any group contains one of the verts
#			for ind in range(len(vertex_groups)):
#				if (vertex_groups[ind].has(e[0]) or vertex_groups[ind].has(e[1])):
#					if not not_closed_groups.has(ind):
#						# add the index to the dictionary
#						not_closed_groups[ind]=null
#
#	var groups_to_remove: PackedInt32Array=[]
#	for ind in range(len(vertex_groups)):
#		if not not_closed_groups.has(ind):
#			groups_to_remove.append(ind)
#	#così ho gli indici dei gruppi da rimuovere, ma per renderlo nuovamente mesh, devo andare a rimuovere gli elmeenti 
#	# da verts e normals e rifare come fa in create_mesh
##	for i in range(len(vertex_groups)):
##		print('group ', i, ' size: ', len(vertex_groups[i]))
#
#	# do not consider groups that do not contain multiple of 3 verts
#	for tor in range(len(groups_to_remove)-1,-1,-1):
#		if len(vertex_groups[tor])%3!=0:
#			groups_to_remove.remove_at(tor)
#
#	var countRem = 0
#	# remove every closed group
#	for v in range(len(verts)-1,-1,-1):
#		for tor in groups_to_remove:
#			if vertex_groups[tor].has(verts[v]):
#				countRem+=1
#				verts.remove_at(v)
#				normals.remove_at(v)
#	print('toRem: ', countRem)
#	print('len', len(verts))
#	print(len(verts)%3==0)
#	print('ending')
#	if len(verts) > 0:
#		var mesh_data = []
#		mesh_data.resize(Mesh.ARRAY_MAX)
#		mesh_data[Mesh.ARRAY_VERTEX] = verts
#		mesh_data[Mesh.ARRAY_NORMAL] = normals
#		array_mesh.clear_surfaces()
#		array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh_data)
#	# here assign collision shape
##	$StaticBody3D/CollisionShape3D.shape = array_mesh.create_trimesh_shape()
#	print('maybe?')
		
		
func get_edges(vert1: Vector3, vert2: Vector3, vert3: Vector3):
	return [
		vector3_min_max_edge(true, vert1, vert2),
		vector3_min_max_edge(true, vert2, vert3), 
		vector3_min_max_edge(true, vert3, vert1)
	]


#func is_occupied(cell: Vector3) -> bool:
#	return true if _units.has(cell) else false


### ----- TODO fix because at the moment it grows indefinitely ----- ###
### ----- TODO fix because at the moment it grows indefinitely ----- ###
### ----- TODO fix because at the moment it grows indefinitely ----- ###
### ----- TODO fix because at the moment it grows indefinitely ----- ###
### ----- TODO fix because at the moment it grows indefinitely ----- ###
### ----- TODO fix because at the moment it grows indefinitely ----- ###
# Returns an array with all the coordinates of walkable cells based on the `max_distance`.
func _flood_fill(cell: Vector3, max_distance: int, grid: AABB) -> Array:
	# This is the array of connected cells the algorithm outputs.
	# try to use a Dictionary to prevent duplicates and exploit the fact that it keeps element ordered by insertion.
	var res_array: PackedVector3Array = []
#	var res_array: Dictionary = {}
	# The way we implemented the flood fill here is by using a stack. In that stack, we store every
	# cell we want to apply the flood fill algorithm to.
	var stack: Array[Vector3] = [cell]
	# keep track of the cells we already checked
	var stack_check: Dictionary = {cell:null}
	# We loop over cells in the stack, popping one cell on every loop iteration.
	while len(stack)>0:
		var current: Vector3 = stack.pop_back()

		# For each cell, we ensure that we can fill further.
		#
		# The conditions are:
		# 1. We didn't go past the grid's limits.
		# 2. We haven't already visited and filled this cell
		# 3. We are within the `max_distance`, a number of cells.
		if not grid.has_point(current):
			continue
		if stack_check.has(current):
			continue
		if res_array.has(current):
			continue

		# This is where we check for the distance between the starting `cell` and the `current` one.
		var difference: Vector3 = (current - cell).abs()
		var distance := int(difference.x + difference.y + difference.z)
#		if distance > max_distance: 
#			continue

		# add current cell to check stack
		stack_check[current] = null
		# If we meet all the conditions, we "fill" the `current` cell. To be more accurate, we store
		# it in our output `res_array`.
		res_array.append(current)
		# We then look at the `current` cell's neighbors and, if they're not occupied and we haven't
		# visited them already, we add them to the stack for the next iteration.
		# This mechanism keeps the loop running until we found all cells the unit can walk.
		for direction in DIRECTIONS:
			var coordinates: Vector3 = current + direction
			# This is an "optimization". It does the same thing as our `if current in res_array:` above
			# but repeating it here with the neighbors skips some instructions.
#			if is_occupied(coordinates):
#				continue
			if coordinates in res_array:
				continue

			# This is where we extend the stack.
			stack.append(coordinates)
		print(len(stack))
	return res_array
	

func is_closed_group(group:Dictionary):
	for elem in group.values():
		if elem!=2:
			return false
	return true

# return the index of the group that contains the vertex, otherwise -1
func get_belonging_vertex_group_index(groups:Array[Dictionary], vert:Vector3):
	for i in range(len(groups)):
		if groups[i].has(vert):
			return i
	return -1


func process_mesh_data_withouth_removing_triangles():
	var triangle_data = triangle_data_bytes.to_float32_array()
	num_triangles = counter_data_bytes.to_int32_array()[0]
	var num_verts : int = num_triangles * 3
	verts.resize(num_verts)
	normals.resize(num_verts)
	
	for tri_index in range(num_triangles):
		var i = tri_index * 16
		var posA = Vector3(triangle_data[i + 0], triangle_data[i + 1], triangle_data[i + 2])
		var posB = Vector3(triangle_data[i + 4], triangle_data[i + 5], triangle_data[i + 6])
		var posC = Vector3(triangle_data[i + 8], triangle_data[i + 9], triangle_data[i + 10])
		var norm = Vector3(triangle_data[i + 12], triangle_data[i + 13], triangle_data[i + 14])
		verts[tri_index * 3 + 0] = posA
		verts[tri_index * 3 + 1] = posB
		verts[tri_index * 3 + 2] = posC
		normals[tri_index * 3 + 0] = norm
		normals[tri_index * 3 + 1] = norm
		normals[tri_index * 3 + 2] = norm
		
# used for sorting vertices, compares vec3.x, if they are equals go on 
# and compare y, else return as min the vec3 with min x
# same behavior with y and z
func vector3_min_max(is_min:bool, v1:Vector3, v2:Vector3):
	var v_diff:Vector3 = v1-v2
	# if we need to check the max, invert v_diff
	if is_min:
		v_diff = v_diff*-1
	
	if v_diff.x>0:
		return v1
	elif v_diff.x<0:
		return v2
	# if none of the above
	if v_diff.y>0:
		return v1
	elif v_diff.y<0:
		return v2
	# if none of the above
	if v_diff.z>0:
		return v1
	return v2

func vector3_min_max_edge(is_min:bool, v1:Vector3, v2:Vector3) -> Array:
	var v_diff:Vector3 = v1-v2
	# if we need to check the max, invert v_diff
	if is_min:
		v_diff = v_diff*-1
	
	if v_diff.x>0:
		return [v1, v2]
	elif v_diff.x<0:
		return [v2, v1]
	# if none of the above
	if v_diff.y>0:
		return [v1, v2]
	elif v_diff.y<0:
		return [v2, v1]
	# if none of the above
	if v_diff.z>0:
		return [v1, v2]
	return [v2, v1]

func get_params_array():
	var params = []
	params.append(time)
	params.append(noise_scale)
	params.append(iso_level)
	params.append(float(num_voxels_per_axis))
	params.append(chunk_scale)
	params.append(player.position.x)
	params.append(player.position.y)
	params.append(player.position.z)
#	params.append(noise_offset.x)
#	params.append(noise_offset.y)
#	params.append(noise_offset.z)
	params.append(0)
	params.append(0)
	params.append(0)
	# added the splines that controls the noise variations
	params.append($ContinentalnessSpline.curve.tessellate(4,4))
	params.append($ErosionSpline.curve.tessellate(4,4))
	params.append($PeakAndValleySpline.curve.tessellate(4,4))
	return params
	
func load_lut(file_path):
	var file = FileAccess.open(file_path, FileAccess.READ)
	var text = file.get_as_text()
	file.close()

	var index_strings = text.split(',')
	var indices = []
	for s in index_strings:
		indices.append(int(s))
		
	return indices
	
	
func _notification(type):
	if type == NOTIFICATION_PREDELETE:
		release()

func release():
	rendering_device.free_rid(pipeline)
	rendering_device.free_rid(triangle_buffer)
	rendering_device.free_rid(params_buffer)
	rendering_device.free_rid(counter_buffer);
	rendering_device.free_rid(lut_buffer);
	rendering_device.free_rid(noise_buffer);
	rendering_device.free_rid(shader)
	
	pipeline = RID()
	triangle_buffer = RID()
	params_buffer = RID()
	counter_buffer = RID()
	lut_buffer = RID()
	noise_buffer = RID()
	shader = RID()
		
	rendering_device.free()
	rendering_device= null
