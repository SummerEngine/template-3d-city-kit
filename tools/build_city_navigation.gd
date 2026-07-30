extends SceneTree

## Headless reference builder for a large static city environment.
## Copy to res://tools/build_city_navigation.gd in the consuming Godot project,
## then run: godot --headless --path . --script res://tools/build_city_navigation.gd

const VISUAL_CITY_SCENE := "res://assets/models/low_poly_city_pack.glb"
const NAVIGATION_PROXY_SCENE := "res://assets/models/low_poly_city_nav_proxy.glb"
const OUTPUT_SCENE := "res://scenes/city_environment.tscn"
const NAVIGATION_BAKE_GROUP: StringName = &"city_navigation_bake_source"
const BAKE_TIMEOUT_MSEC := 300_000

# Verified bounds for the referenced city export. Adjust when the source model
# has a different origin or extent. Size is measured from the position corner.
const NAVIGATION_BAKE_BOUNDS := AABB(
	Vector3(-250.0, -2.0, -270.0),
	Vector3(305.0, 7.0, 330.0)
)


func _initialize() -> void:
	call_deferred("_build_city_environment")


func _build_city_environment() -> void:
	var visual_source := load(VISUAL_CITY_SCENE) as PackedScene
	if visual_source == null:
		_fail("Could not load visual city: %s" % VISUAL_CITY_SCENE)
		return

	var proxy_source := load(NAVIGATION_PROXY_SCENE) as PackedScene
	if proxy_source == null:
		_fail("Could not load navigation proxy: %s" % NAVIGATION_PROXY_SCENE)
		return

	var scene_root := Node3D.new()
	scene_root.name = "CityEnvironment"
	get_root().add_child(scene_root)
	current_scene = scene_root

	var navigation_region := NavigationRegion3D.new()
	navigation_region.name = "NavigationRegion3D"
	scene_root.add_child(navigation_region)
	navigation_region.owner = scene_root

	var visual_city := visual_source.instantiate() as Node3D
	if visual_city == null:
		_fail("Visual city root must inherit Node3D")
		return
	visual_city.name = "LowPolyCityPack"
	visual_city.scale = Vector3.ONE
	navigation_region.add_child(visual_city)
	visual_city.owner = scene_root

	var collision_root := Node3D.new()
	collision_root.name = "GeneratedCollisions"
	navigation_region.add_child(collision_root)
	collision_root.owner = scene_root

	# Global transforms are reliable after all source nodes enter the SceneTree.
	await process_frame
	var mesh_instances := _collect_mesh_instances(visual_city)
	var collision_count := _generate_static_trimesh_collisions(
		mesh_instances,
		collision_root,
		scene_root
	)
	print(
		"CITY_COLLISIONS mesh_nodes=%d static_bodies=%d"
		% [mesh_instances.size(), collision_count]
	)
	if collision_count == 0:
		_fail("No collision shapes were generated")
		return

	var navigation_proxy := proxy_source.instantiate() as Node3D
	if navigation_proxy == null:
		_fail("Navigation proxy root must inherit Node3D")
		return
	navigation_proxy.name = "NavigationBakeProxy"
	navigation_proxy.transform = visual_city.transform
	navigation_region.add_child(navigation_proxy)
	navigation_proxy.owner = scene_root
	navigation_proxy.add_to_group(NAVIGATION_BAKE_GROUP, true)

	var navigation_mesh := _create_navigation_mesh()
	navigation_region.navigation_mesh = navigation_mesh

	print("CITY_NAVMESH bake_started")
	# Bake on the worker thread. The separate proxy keeps the job small, while
	# polling is_baking() gives this headless builder a real timeout boundary.
	navigation_region.bake_navigation_mesh(true)
	var bake_started_at := Time.get_ticks_msec()
	while (
		navigation_region.is_baking()
		and Time.get_ticks_msec() - bake_started_at < BAKE_TIMEOUT_MSEC
	):
		await process_frame

	if navigation_region.is_baking():
		_fail("NavigationMesh bake timed out; decimate the proxy further")
		return

	var polygon_count := navigation_mesh.get_polygon_count()
	var vertex_count := navigation_mesh.get_vertices().size()
	print(
		"CITY_NAVMESH bake_finished polygons=%d vertices=%d"
		% [polygon_count, vertex_count]
	)
	if polygon_count == 0 or vertex_count == 0:
		_fail("NavigationMesh bake produced no geometry")
		return

	# Retain the source for reproducible rebakes, but never render it in-game.
	navigation_proxy.visible = false

	var output_directory := ProjectSettings.globalize_path(OUTPUT_SCENE).get_base_dir()
	var directory_error := DirAccess.make_dir_recursive_absolute(output_directory)
	if directory_error != OK:
		_fail("Could not create output directory (error %d)" % directory_error)
		return

	var packed_scene := PackedScene.new()
	var pack_error := packed_scene.pack(scene_root)
	if pack_error != OK:
		_fail("PackedScene.pack failed (error %d)" % pack_error)
		return

	var save_error := ResourceSaver.save(packed_scene, OUTPUT_SCENE)
	if save_error != OK:
		_fail("ResourceSaver.save failed (error %d)" % save_error)
		return

	print("CITY_NAVIGATION_SCENE saved=%s" % OUTPUT_SCENE)
	quit(0)


func _collect_mesh_instances(root_node: Node) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	var stack: Array[Node] = [root_node]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D:
			var mesh_instance := node as MeshInstance3D
			if mesh_instance.mesh != null:
				meshes.append(mesh_instance)
		for child in node.get_children():
			stack.append(child)
	return meshes


func _generate_static_trimesh_collisions(
	mesh_instances: Array[MeshInstance3D],
	collision_root: Node3D,
	scene_root: Node
) -> int:
	var collision_count := 0
	for mesh_instance in mesh_instances:
		var trimesh_shape := mesh_instance.mesh.create_trimesh_shape()
		if trimesh_shape == null:
			continue

		var static_body := StaticBody3D.new()
		static_body.name = "Collision_%03d" % collision_count
		static_body.collision_layer = 1
		static_body.collision_mask = 1
		static_body.set_meta("source_mesh_path", str(mesh_instance.get_path()))
		collision_root.add_child(static_body)
		static_body.owner = scene_root
		static_body.global_transform = mesh_instance.global_transform

		var collision_shape := CollisionShape3D.new()
		collision_shape.name = "CollisionShape3D"
		collision_shape.shape = trimesh_shape
		static_body.add_child(collision_shape)
		collision_shape.owner = scene_root
		collision_count += 1
	return collision_count


func _create_navigation_mesh() -> NavigationMesh:
	var navigation_mesh := NavigationMesh.new()
	navigation_mesh.resource_local_to_scene = true
	navigation_mesh.agent_height = 2.0
	navigation_mesh.agent_radius = 0.5
	navigation_mesh.agent_max_climb = 0.4
	navigation_mesh.agent_max_slope = 45.0
	navigation_mesh.cell_size = 0.5
	navigation_mesh.cell_height = 0.25
	navigation_mesh.edge_max_error = 1.0
	navigation_mesh.filter_ledge_spans = true
	navigation_mesh.filter_walkable_low_height_spans = true
	navigation_mesh.geometry_parsed_geometry_type = (
		NavigationMesh.PARSED_GEOMETRY_MESH_INSTANCES
	)
	navigation_mesh.geometry_source_geometry_mode = (
		NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	)
	navigation_mesh.geometry_source_group_name = NAVIGATION_BAKE_GROUP
	navigation_mesh.filter_baking_aabb = NAVIGATION_BAKE_BOUNDS
	return navigation_mesh


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
