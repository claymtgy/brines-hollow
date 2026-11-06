# Brine's Hollow — prototype

Co-op coastal voxel sandbox. Godot 4.7; voxel core in C++ (GDExtension), gameplay in GDScript.

## Build the native extension (once, and after changing `native/src`)

Needs a C++17 compiler, CMake and Python 3.

```sh
native/build.sh            # -> bin/libbrines.linux.template_debug.x86_64.so
native/build.sh release    # for exports / Steam Deck builds
```

`native/godot-cpp` holds the official C++ bindings; `native/extension_api.json` is dumped from
the installed engine (`godot --headless --dump-extension-api`) so the bindings match it exactly.

## Run

```sh
godot --path ~/Games/brines_hollow          # menu: Solo / Host / Join
godot --path . -- --solo                   # skip the menu
godot --path . -- --host                   # host co-op (UDP port 24565)
godot --path . -- --join=192.168.1.20      # join a host
```

Or open the folder in the Godot editor and press F5.

## Worlds, saves and the dedicated server

```sh
godot --path . -- --solo --world=hollow            # solo; loads/creates user://worlds/hollow/
godot --path . -- --host --world=hollow            # host co-op from your save
godot --headless --path . -- --server --world=hollow      # dedicated server (UDP 24565)
godot --headless --path . -- --server=25000 --world=hollow
godot --path . -- --join=SERVER_IP                 # join; your progress is stored on that server
```

- Saves live in `user://worlds/<name>/` (on Linux: `~/.local/share/godot/app_userdata/Brine's Hollow/worlds/`).
  `--new-world` archives the existing save (`<name>.bak-<time>`) and starts fresh.
- The host / server is the authority: it owns terrain edits, farms, salt pans, the village and
  boats, and is the only machine that writes saves (autosave every 60 s, 30 s on a dedicated
  server, and on window close).
- Joining players receive the edited chunk columns, then live edits. Their inventory, quests and
  appearance are stored by the server under a stable per-machine player key
  (`user://profile_<name>.cfg`, choose with `--profile=NAME`).
- Building costs materials: 1 item per 4 voxels, the same rate digging gives back.

## Controls

| Key | Action |
|---|---|
| WASD / Shift / Space | move / sprint / jump (swim up in water) |
| Mouse / Wheel / V | orbit camera / zoom / swap shoulder |
| LMB | use tool |
| 1 / 2 / 3 | Pickaxe (dig) / Hammer (place voxels) / Blueprints (prefabs) |
| Q / E | previous / next material or prefab |
| Z / X | brush size |
| R / G | rotate prefab / toggle 6-voxel grid snap |
| MMB | pick the material you're looking at |
| Hold T | fast-forward time (host/solo) — watch the tide move |
| F1 / F3 | help / stats |
| Esc (Start on a pad) | pause menu: resume, settings (controls, graphics presets incl. Steam Deck, UI scale, key rebinding), save & quit |

## Layout

| File | What it does |
|---|---|
| `native/src/voxel_store.cpp` | C++: sparse chunk storage, mesher (AO + colour variation), raycast, AABB collision, brushes, terrain fill |
| `scripts/voxel_world.gd` | scene wrapper: chunk meshes, threaded remesh dispatch, lights, edit commands |
| `scripts/mesher.gd` | wrapper for meshing small models (characters, tools, ghosts) natively |
| `scripts/worldgen.gd` | island, tidal flats, terraced cliffs, sea stacks, sea cave, trees, starter hut |
| `scripts/prefabs.gd` | prefab library (walls, hut, dock, lamp post, boat, ...) + rotation |
| `scripts/player.gd` | voxel AABB movement with auto-step, swimming, tools, ghost preview |
| `scripts/camera_rig.gd` | over-the-shoulder camera with terrain collision |
| `scripts/character_model.gd` | voxel fisherfolk at 2x terrain detail, procedural animation |
| `scripts/sky_cycle.gd` | day/night palette, fog, tide clock, water plane |
| `scripts/main.gd` | session setup, host-authoritative co-op, dev test modes |

## Key numbers

- Voxel = 0.18 m (player ≈ 10 voxels tall); island 512×128×512 voxels (92 m across)
- Tide: ±1.26 m, two cycles per 12-minute day
- Co-op: everyone generates the same world from the seed; edits are sent as tiny
  commands (`dig`, `place`, `prefab`) through the host, which keeps a log for late joiners

## Dev flags

`--preset=deck|low|medium|high` (this run only), `--bench[=detail]`, `--menushot=DIR`.

`--shot=DIR` (scripted screenshots), `--bench` (GPU timing), `--netcheck` (with `--host`/`--join`,
verifies edit sync), `--seed=N`, `--time=0.5`.
