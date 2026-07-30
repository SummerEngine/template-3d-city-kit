# 3D City Kit Starter

A Summer Engine / Godot starter workspace for turning a large imported city GLB into a static, walkable environment. It is a construction template rather than a finished game: import a city asset, generate collision and navigation, then build the player and gameplay scene on top.

The verified reference asset has 88 mesh descendants and about 1.1 million triangles, so the core rule is: **use the original meshes for exact static physics, but a decimated duplicate for navigation baking**. Asset source, license, scale, and repository policy: `ASSETS.md`.

The template opens into `scenes/city_kit_workspace.tscn`, a lit scale-check workspace with a 1 m reference cube and setup instructions. It intentionally does not redistribute the city GLBs or a generated `city_environment.tscn`.

## Prerequisites — build in this order

1. Obtain `low poly city pack` using `ASSETS.md` and place the visual model at `res://assets/models/low_poly_city_pack.glb`.
2. Produce a geometry-only decimated derivative at `res://assets/models/low_poly_city_nav_proxy.glb`. Preserve the source origin and transforms; aim for roughly 10% of the triangles.
3. Run the included builder from the project root:

```sh
godot --headless --path . --script res://tools/build_city_navigation.gd
```

Summer Engine projects can use the Summer executable in place of `godot`. The builder creates `res://scenes/city_environment.tscn` and exits.

## Step 1 — verify scale before generating anything

Instance the visual GLB temporarily next to a default `CSGBox3D` or `MeshInstance3D` with a `BoxMesh`. Leave the outer city instance at `scale = Vector3.ONE`.

The asset's imported hierarchy contains an internal `0.01` authoring-unit conversion. That conversion is already part of the imported scene; the correct outer instance scale remains **1.0**. Check that a door is close to 2 m high and a road lane is about 3–4 m wide. If those references are wrong, inspect the import hierarchy before compensating with another arbitrary scale.

**Checkpoint:** the 1 m cube reads plausibly beside doors, sidewalks, cars, and road widths.

## Step 2 — generate exact static collision

The builder recursively collects every `MeshInstance3D` below `LowPolyCityPack`. For each non-empty mesh it creates one sibling `StaticBody3D`, copies the mesh's global transform, and assigns a `CollisionShape3D` made with `mesh.create_trimesh_shape()`.

This is appropriate because the city is static. Do not use concave trimesh shapes on moving `RigidBody3D` or `CharacterBody3D` nodes. If the production project needs cheaper physics, replace individual building shapes with authored boxes or simplified convex shapes after the exact reference pass works.

**Checkpoint:** the number of generated bodies matches the number of usable mesh descendants (88 for the verified source asset).

## Step 3 — bake navigation from the proxy only

The builder instances `NavigationBakeProxy` under `NavigationRegion3D`, adds it to the persistent `city_navigation_bake_source` group, and configures the `NavigationMesh` to parse mesh instances from that group and its children. The visual GLB and the generated collision bodies are therefore excluded from the navigation geometry pass.

The checked-in constants use the verified street-level bake bounds. If another export has a different origin or extent, adjust `NAVIGATION_BAKE_BOUNDS` before running the script. Agent dimensions are configured for a roughly human-sized character: 2 m height, 0.5 m radius, 0.4 m maximum climb, and 45° maximum slope.

After baking, the proxy remains in the output scene for reproducible rebakes but is hidden. The `NavigationMesh` is embedded in the generated scene.

**Checkpoint:** select `NavigationRegion3D` and enable visible navigation/debug geometry. Turquoise polygons should cover roads and plazas, stop at building footprints, and avoid props that are large enough to block the configured agent.

## Exact generated scene tree

```text
CityEnvironment (Node3D)
└── NavigationRegion3D
    ├── LowPolyCityPack (instance: low_poly_city_pack.glb, scale 1.0)
    ├── GeneratedCollisions (Node3D)
    │   ├── Collision_000 (StaticBody3D)
    │   │   └── CollisionShape3D (ConcavePolygonShape3D / trimesh)
    │   ├── Collision_001 (StaticBody3D)
    │   │   └── CollisionShape3D
    │   ├── …
    │   └── Collision_087 (StaticBody3D)
    │       └── CollisionShape3D
    └── NavigationBakeProxy (instance: low_poly_city_nav_proxy.glb)
        [group: city_navigation_bake_source, hidden after bake]
```

Camera, lighting, `WorldEnvironment`, player, and NPCs belong in the gameplay scene that instances `city_environment.tscn`; they are deliberately not coupled to the reusable environment output.

## Step 4 — verify physics and pathfinding

1. Instance `city_environment.tscn` in a lit gameplay/test scene.
2. Drop a capsule-shaped `CharacterBody3D` a metre above a road or plaza and apply gravity with `move_and_slide()`.
3. Move it into a building facade. It must remain on the ground and report a horizontal slide-collision normal at the wall.
4. Add a `NavigationAgent3D`, wait until the navigation map has completed its first region synchronization (`NavigationServer3D.map_get_iteration_id(map_rid) >= 2` in the verified setup), then request a short path between two points on the same connected navigation island.
5. Check script errors, runtime debugger errors, and a visible navigation screenshot before accepting the scene.

## Gotchas

### Sketchfab node names may be corrupted

FBX-to-GLB exports can produce mojibake or otherwise unusable node names. Do not search for strings such as `road`, `ground`, or `building` to decide which meshes receive collision. Traverse every `MeshInstance3D`, skip null meshes, and store the source `NodePath` as metadata for later inspection. Also note that separate nodes are not guaranteed to be semantically clean: a mesh may contain a broad material or city section rather than exactly one house.

### Do not apply the 0.01 conversion twice

The correct outer scale for this asset is 1.0 because the imported hierarchy already contains the internal 0.01 conversion. Always prove scale with a 1 m cube and real-world references before generating collision or baking navigation; rebuilding 88 embedded shapes after a scale correction is expensive.

### Separate physics geometry from navigation geometry

Feeding the full ~1.1M-triangle render city into Recast can freeze the editor or exceed a bake timeout. Exact trimesh collision and navigation have different requirements:

- **Physics:** original 88 mesh descendants, exact static trimesh shapes.
- **Navigation:** aligned, decimated proxy, parsed by a dedicated source group.
- **Rendering:** original visual GLB only; the proxy is hidden after bake.

Do not simplify the render asset just to make NavMesh baking finish, and do not use the proxy as the player's physical floor unless its reduced silhouette was explicitly authored for that purpose.

### Generated scenes can be large

Embedding 88 concave shapes can make the generated `.tscn` tens or hundreds of megabytes. Generate it inside the consuming project and review that project's asset policy before committing it. Never commit the source or proxy GLBs to this repository.

## If the build fails

- `Could not load ...glb`: confirm both assets finished importing and the paths match the constants.
- Collision count is zero: open the visual GLB and confirm it has `MeshInstance3D` descendants with non-null meshes.
- Bake returns zero polygons: confirm the proxy overlaps the visual city, belongs to `city_navigation_bake_source`, and intersects `NAVIGATION_BAKE_BOUNDS`.
- Bake times out: reduce proxy geometry again; do not fall back to the full visual model.
- Agent returns its own position or an empty path: wait for navigation-map synchronization, confirm both points are on the same connected island, and inspect the turquoise debug geometry.
