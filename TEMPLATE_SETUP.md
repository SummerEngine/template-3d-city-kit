# Template setup

This starter is ready to open before the city assets exist.

1. Read `ASSETS.md` and obtain the visual city from its authoritative source.
2. Create the aligned decimated navigation proxy.
3. Put both files at the exact paths documented in `assets/models/README.md`.
4. Run `tools/build_city_navigation.gd` headlessly.
5. Instance the generated `scenes/city_environment.tscn` in a new gameplay scene.
6. Add the player, camera, lighting changes, NPCs, and game loop required by the project.

Do not bake navigation from the full render model. The split between exact static collision and decimated navigation geometry is the reusable core of this starter.
