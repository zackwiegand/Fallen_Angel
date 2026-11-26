# Rocker POC (Godot 4.7.2)

## Goal
A playable proof of concept: a metal-rocker character (gothic plate armor, combat boots, guitar as weapon)
who can **move in 8 directions**, **attack (guitar swing)** and **strum** in all 8 directions, rendered
in a chunky pixel-art isometric look (Dead Cells–style).

## Git rules (user, 2026-11-26)
- Repo: this folder only, remote `origin` = github.com/zackwiegand/Fallen_Angel. Identity is per-repo
  (`zackwiegand <zackerywiegandl@gmail.com>`); never change global git config.
- **Commit freely** at logical steps (a feature, a fix, a refactor), several small commits rather than one big
  one, clear messages. Stage specific paths, not stray files.
- **NEVER push** — the user pushes. Never add remotes, force anything or rewrite pushed history.
- **NEVER work outside this repo** — no other repos, no work repos. `sprite-poc/` is read-only source
  (export_gltf.py execs it); don't modify it.

## Key decision: real-time 3D → pixel (not pre-baked sprite sheets)
User wants lots of swappable gear (armor, boots, helmets, guitars). Baking a sheet per combination is
multiplicative (10×10×10 items ≈ 1 GB). So:
- Export the rig + meshes from Blender as **glTF**; animations baked to keyframes.
- Each gear piece is its own mesh/scene, attached via **BoneAttachment3D** (or skinned to the shared skeleton)
  and swapped at runtime → asset count is additive.
- Render the 3D character in a **low-res SubViewport** (~80px tall char; 128px canvas for big swings),
  upscale with nearest filtering. Fixed isometric orthographic camera; character rotates for 8 dirs
  (snap facing to 45° steps for the pixel look).
- Recreate the look as shaders: toon/cel shading, fixed palette quantize, dark outline (+ selective inner
  outlines between parts), done as a post-process on the SubViewport.
- Pixel shimmer when rotating/moving is **acceptable** ("could give it character") — don't over-engineer snapping.

## Source assets (Blender pipeline, Python, Blender MCP available)
`/Users/patriciabrewer/dev/sprite-poc/` — read its `NOTES.md` first.
- `rocker.py` (character build: faceted plate, skin arms, bracers, boots), `guitar_reaper.py`, `guitar_battleaxe.py`
  (swappable guitars; must provide grip points: strum, fret, axe_lo, axe_hi).
- `anims.py` — idle ("bull ready to charge" breathing), old-man walk, strum, baseball-mechanics swing (20 frames).
  Animations are procedural (IK to grip points) → must be **baked to keyframes** before glTF export.
- `rocker.blend`, rendered GIF/PNG references in `out/<guitar>/<anim>/` — use these to compare the Godot look.
- User was 100% happy with these animations; keep their style.

## Game & camera decisions (user, 2026-11-25)
- **The game is 2D.** 3D models exist only to produce the pixel-art character: each character's rig renders
  into its own transparent 128px SubViewport shown 1:1 as a Sprite2D in a 2D world (CharacterBody2D).
- **Front 3/4 view, camera never rotates.** Rig camera looks straight "north" (-Z) tilted 38° down; it is NOT
  the diagonal iso of the sprite-poc renders. The character still turns to 8 facings; environment art is
  drawn from this single view only.
- **One pixel scale everywhere (no mixels):** 1 game px = 4×4 window px (nearest). Stretch is off, so the game
  buffer = window / 4 (bigger window = more view, same sizes); window opens at a 480×320 game-px view
  (`main.gd` VIEW_PX → 1920×1280, capped to the screen) and the player's Camera2D follows, clamped to the room. 1 texel = 1 game px
  = 3/80 m. Ground depth foreshortens by sin 38°, wall height by cos 38°. A 16px tile = 0.6 m wide,
  0.97 m deep (floor), 0.76 m tall (wall face).

## Current architecture (built)
- Camera: `scripts/pixel_camera.gd` (`PixelCamera`, the player's Camera2D) snaps to whole game px and emits
  `scrolled(subpixel)`; `main.gd` renders the game view MARGIN_PX bigger on each side and shifts it by the
  remainder in window px, so the world scrolls smoothly (no 0/1/2 px judder = "camera shake") while the
  low-res render stays pixel-perfect. Room bounds = Camera2D `limit_*` (built-in clamp off; PixelCamera clamps).
  Test: `godot --headless --path . --fixed-fps 60 -s tools/test_camera.gd`.
- `blender/export_gltf.py` — `blender -b -P blender/export_gltf.py`. Execs the sprite-poc scripts, adds a plain
  under-layer (body visible with armor/boots off), splits parts into slots (body/armor/boots), rigidly skins
  each slot to one shared skeleton (+ `root` bone = lift/foot planting, + `guitar` bone = prop placement),
  bakes idle/walk/strum/swing (+ Godot-only cast/run) at 30 fps, writes `assets/rocker/rocker_base.glb` (rig + body + anims),
  `assets/gear/armor_*.glb`, `boots_*.glb` (rig + mesh, no anims), `guitar_*.glb` (static, sockets kept).
  Then run `godot --headless --path . --import`.
- `scripts/rocker_rig.gd` — loads the base, re-parents skinned gear meshes onto the base Skeleton3D
  (Skin binds resolve by bone name → base animations drive all gear), guitars on a BoneAttachment3D("guitar").
  AnimationTree state machine built in code (idle↔strum cut, swing blends). `anim_fps` > 0 steps playback.
- `scripts/gear_catalog.gd` — items per slot; `recolor` remaps material names to other `Toon.PALETTE` entries.
- `scripts/toon.gd` + `shaders/toon.gdshader` — sprite-poc toon materials (3 bands, Blender lights, Lambert /π),
  swapped in by imported material name. `shaders/sprite_outline.gdshader` — hard alpha + 1px outer outline.
- `scripts/player.gd` — 8-dir movement in screen space, facing snap, input actions (bound in `main.gd`).
- **Run**: double-tap an arrow (same arrow twice within `RUN_TAP_WINDOW` 0.25 s) → `player.running`, `run_speed`
  3.1 m/s (~2.2× walk). Keeps running while any direction is held; a gap shorter than `RUN_GRACE` (0.15 s, e.g.
  a quick left → right reversal) keeps the run. Run state reads raw input, so holding a direction through a
  swing/strum/cast resumes the run afterwards (actions themselves stop the character, as from the walk).
  `run` clip = `anim_run` in export_gltf.py (walk's hunch/rigid boots + RUN_LEAN, longer stride, short flight,
  guitar bouncing a beat late; RUN_TUCK kept low because a high heel tuck reads as kneeling at sprite size).
  `RockerRig.set_gait(&"idle"/&"walk"/&"run")`: walk and run share leg phases (L heel strike 0, R 0.5), so a
  gait switch starts the new clip at the old phase via AnimationNodeAnimation `start_offset` (also across the
  ~60 ms idle gap of a double-tap, `GAIT_MEMORY`). Note: the playback position excludes `start_offset`;
  `gait_phase()` adds it back. Tests `tools/test_run.gd`, visuals + crop check `tools/run_shots.gd -- <dir>`.
- Dungeon (demo floor, 56×38 tiles = 896×608 px): `tools/build_dungeon.gd` (art pass, import, scene pass; see its
  header) generates `assets/env/dungeon_tiles.png` (floor + 2 seamless cobble variants, walls, pillars),
  `dungeon_decals.png` (moss, blood, cracks, puddles, bones, skulls, chains, rubble, bone piles), `dungeon_tileset.tres`
  and `scenes/dungeon.tscn`: Floor, Decals (no collision; swap the PNG for hand-painted art, same layout) and
  y-sorted Walls TileMapLayers. Wall/pillar tiles sort by their base line (y_sort_origin), so the player walks
  behind pillars; only the base row collides. Layout (pillars, decals, spawns) = consts at the script top.
  `Navigation` = NavigationRegion2D baked at build time over the floor minus pillars/dummies (agent radius 6 px) →
  NavigationAgent2D works. `Spawns` holds Marker2Ds in groups `gremlin_spawn` and `pedal_spawn` (meta `pedal_id`).
  `tools/test_floor.gd` (size, markers, nav paths), `tools/floor_shots.gd` (overview + 4x crops, needs a window).
- Tools: `tools/capture.gd` (contact sheet poses × 8 facings, optional gear indices),
  `tools/screenshot.gd`, `tools/test_logic.gd` (headless state machine + gear smoke test), `tools/inspect.gd`.

## Animation workflow (decided 2026-11-25: Blender stays in the pipeline)
- **Blender = models + authoring animations.** New clips go in `blender/export_gltf.py` (like `anim_cast`):
  procedural functions of phase with IK to the guitar sockets (sprite-poc style), or hand-keyed in Blender.
  Then `blender -b -P blender/export_gltf.py && godot --headless --path . --import`; the clip appears on the rig.
  In Godot: add it to the AnimationTree in `rocker_rig.gd` and its timed events to `ANIM_EVENTS`.
- **Godot = runtime layers + gameplay.** Procedural modifiers on top of the baked clips (e.g. `guitar_hands.gd`),
  blending, events, gear swap. Don't hand-key bones in Godot's editor; it has no IK posing.
- Keep sprite-poc files untouched; put Godot-specific overrides/new clips in export_gltf.py.

## Gotchas / tuning
- Guitar mount: the glTF `guitar` bone's frame stays in Blender (Z-up) axes while guitar files are Y-up, so
  `rocker_rig.gd` mounts guitars under a +90° X correction. `tools/socket_check.gd` verifies hands == sockets.
- Front-view arm tuning lives in `export_gltf.py` ("front-view tuning": FRET_X, picking-elbow pole, strum
  elbow lift) — overrides on top of sprite-poc, whose files stay untouched. `tools/closeup.gd` renders
  hi-res poses from the game camera for posing work.

## Spells (game premise: melee with the guitar, cast spells by playing note patterns)
- Controls: arrows move (double-tap = run), J swing, K strum, Q W E R A S D F = E minor pentatonic E3 G3 A3 B3 D4 E4 G4 A4, 1-3 gear.
- `scripts/spellbook.gd`: Fire = any E-minor / G-major triad within 1 s (any order/inversion) → `cast`
  animation (new, baked in export_gltf.py `anim_cast`; release at 0.386 s) → `scripts/fx/fireball.gd`.
  Lightning = skip pattern 1 3 2 4 3 5…, up or down; 4 notes = 1 charge, +1 per note (max 12), released on a
  1.2 s pause (Spellbook.SKIP_RELEASE) or pattern break → `scripts/fx/chain_lightning.gd` (N hits by priority: nearest enemy ahead → next enemy within BOUNCE_RANGE 150 px, fewest hits first, then least
  recently hit, then nearest, so a mob is hit evenly; all within CHAIN_REACH 200 px of the caster; `tools/test_lightning.gd`).
- Charging: `Spellbook.charge_changed(spell, charges)` + `skip_progress()` tell code a spell is building.
  `scripts/fx/charge_aura.gd` (two layers wrapping the sprite) grows crackling arcs per charge, ground ring
  from 6, pulse per charge, burst on release; `Sfx.set_charge` loops a rising hum + per-charge tick.
  Palette is per spell (`ChargeAura.PALETTES`) so fire can get its own aura later. `tools/aura_shots.gd`.
- Note hands: `scripts/guitar_hands.gd` (SkeletonModifier3D on the skeleton) = procedural layer over idle/walk.
  Two-bone IK, offsets from the animated hands along the guitar's axes, elbow keeps the baked bend plane
  (zero offset == baked pose). Fret hand slides NECK_LOW..NECK_HIGH per note, picking hand alternates
  down/up strokes; off during actions. Modifier output only exists inside `modification_processed`
  (Godot restores the animated pose after skinning), so tests sample there: `tools/test_hands.gd`,
  visuals `tools/hands_shots.gd`.
- Swing deals melee damage at contact (`swing_hit` event). `scenes/dummy.tscn` practice dummies never die.
- 2D spells live on the ground plane with a visual height (`player._tip_ground()` projects the 3D headstock).
- `tools/test_spells.gd` (pattern + damage tests), `tools/spell_shots.gd` (frames of both spells).

## Pedals (collectible effect pedals; order matters)
- Data: `scripts/pedals/pedal_def.gd` (`PedalDef`: names, colours, `make_audio_effect()`, `transform(cast)`),
  one subclass per pedal (`delay_pedal.gd` CHIEF CD-3, `phaser_pedal.gd` Skyman Phaser-R), listed in
  `PedalRegistry.PEDALS`. New pedal = subclass + one registry line (+ model, see "Pedal models").
- `Pedalboard` (child of the player): ordered `chain`, bypass per pedal, `chain_changed`. Owns the `Pedals`
  AudioServer bus (one effect per pedal in chain order, bypass = effect disabled). Only the guitar plays on it: the
  player's notes + strum (`Sfx.instrument_bus`, `Sfx.INSTRUMENT_EVENTS`). Steps, swing, spells, hits (`Sfx.bus`),
  music and the looper's `LoopSfx` stay dry.
- Spells: `scripts/spells/spell_cast.gd` (`SpellCast`) is the cast as data; `pedalboard.apply(cast).launch(world)`.
  Each active pedal transforms it for the ones after it. Delay: +3 echoes (`Damage.deal`, ECHO_TIME 0.3 s apart =
  the audio repeat time, each half: 12 → 6 3 2). Phaser: pierce + purple aura; if echoes already exist (delay
  before it) they become 3 ghost casts on the same path at 1/2, 1/4, 1/8 damage, all piercing. So Phaser > Delay
  = pierce + echoes on every target; Delay > Phaser = piercing ghosts. Lightning pierce = each bolt passes through
  its target (PIERCE_OVERSHOOT) and strikes everything on its line.
- Echo hits use kind `<element>_echo` (`Damage.echo_kind/base_kind/is_echo`); targets show them fainter
  (`dummy.gd`). New hittable things should call `Damage.base_kind()` before element logic.
- World: `PedalPickup` (scene `scenes/pedals/pedal_pickup.tscn`) spawns at `pedal_spawn` markers (meta
  `pedal_id`) or fallback spots, joins the chain on touch. `PedalTrail` floats the pedals after the player
  (snake follow when moving, arc behind when idle, handed out right→left so the chain reads like a real board)
  with verlet-rope cables guitar → in jack (right) → out jack (left) → next. Tunables at the top of each script.
- Menu: `PedalboardMenu` (Tab, pauses, PROCESS_MODE_ALWAYS), GTR > pedals > AMP, Enter pick up/drop + arrows
  reorder, B/Space bypass, live text from `Pedalboard.describe()`. Drawn in game px with `PixelFont` (now has capitals).
- `tools/test_pedals.gd` (orders, bypass, echo values, bus order, pierce on dummies, pickup + menu flow),
  `tools/pedal_trail_shots.gd -- <dir>` (needs a window: trail, ghosts, echoes, menu).

## Sound
- `scripts/sfx_synth.gd` synthesizes bit-crushed PCM at startup (no audio files): footstep variants, swing
  whoosh, palm-muted power-chord strum. `scripts/sfx.gd` plays them.
- Timing: `RockerRig.ANIM_EVENTS` adds method tracks to the baked clips (heel strikes, strum hit at 0.6 s,
  whoosh peaking at swing contact) → `anim_event` signal → `Sfx.play`. `tools/test_sfx.gd` checks timing.

## Music
- `SfxSynth.music_loop()`: Em - C - G - D (E natural minor = key of the note keys), 100 BPM, 4 bars / 9.6 s,
  detuned-saw pad + 8th-note bass + drums (`SfxSynth.DRUMS` 16th-note grid: kick/snare/hats, bar-2 double
  kick, bar-4 tom fill, crash on the loop). Tails wrap so it loops seamlessly. `scripts/music.gd` synthesizes
  it on a WorkerThreadPool task, plays under the notes (VOLUME_DB, user-tuned), M toggles, `current_chord()` for harmony-aware
  features. `tools/test_music.gd` (key, seam, level, drum onset). Note: a SCRIPT ERROR in a headless test
  leaves Godot waiting forever (no `timeout` on macOS) — give tests a watchdog timer.

## Step sequencer / instruments
- `scripts/sequencer.gd`: synth-style step sequencer, steps = 16ths at the current tempo. Z starts step entry
  (clears) / Z stops and loops. Each note press appends a step; presses within CHORD_WINDOW (0.06 s) share a step
  (chords); Space = rest step. Length = steps entered (max 64, auto-stops). Playback starts on the next 16th of
  the backing track (lengths other than 16/64 drift against the bars, like a real sequencer). Steps store
  [note, instrument, octave]. X play-stop, C clear. Sound only (own `LoopSfx`, -8 dB).
- Tempo: default `SfxSynth.MUSIC_BPM` (100). T = tap tempo (`Sequencer.tap`: 3+ taps, average of the last 4
  intervals, 60..200, 2 s pause resets). The sequencer owns `bpm`; steps are stored by index so loops keep their
  rhythm at any tempo. `bpm_changed` -> `Music.set_bpm` re-synthesizes the loop on a worker thread (cached per BPM)
  and swaps it in at the same phase; the sequencer clocks off `Music.phase()`, so they stay locked.
- `scripts/sequencer_view.gd`: HUD piano-roll (64 × 8): lit columns = sequence length, loop-end marker, colour per
  instrument, octave tint, playhead, blinking red record cursor.
- Instruments: `Sfx.INSTRUMENTS` (Lead guitar = `SfxSynth.note`, Chip synth = `SfxSynth.chip`), V cycles the live
  one (`player.instrument`). `[` / `]` shift `player.octave` (-2..+2, pitch_scale 2^oct, sound only; spells
  still read key indices). `player.note_played(index, instrument, octave)` feeds the looper, which stores it.
- `tools/test_sequencer.gd` drives the clock by hand (deterministic): step entry, chords, rests, length, tap tempo.

## Adding gear
- New armor/boots/helmet: build it in Blender bound to the rig bones (like rocker.py parts), add its name
  prefixes to the slot lists in `export_gltf.py`, re-export, add a `GearCatalog` entry. New slot = new key.
- New guitar: must follow the sprite-poc GUITAR CONTRACT (same socket positions) — hands are baked against them.
- New material: add a `Toon.PALETTE` entry with the same name as the Blender material.

## Pedal models
- `blender/pedals/build_pedals.py` (`blender -b -P blender/pedals/build_pedals.py`, then `godot --headless --path . --import`)
  builds every pedal procedurally → `assets/pedals/pedal_<id>.glb` (+ `pedals.blend` for inspection). The PEDAL
  CONTRACT is in its header: origin = base centre, footswitch edge toward -Y (Blender), one merged mesh +
  `jack_in` (pedal's right) / `jack_out` (left) Empties, LED material named `Led<x>`.
- `scripts/pedals/pedal_view.gd` (`PedalView`): `setup(id)`, `facing` (8-dir snap), `lit` (LED ↔ `Led<x>Off`),
  `jack_point(&"in"/&"out")` (local 2D px). Own 40px SubViewport, same camera/scale as the rig, re-renders only
  when facing/lit change. ~16 px wide on screen.
- Add a pedal: write `build_<id>()` in build_pedals.py (chunky: knobs/LED ≥ 2–3 px, value contrast), register it in
  `PEDALS`, add its material names to `Toon.PALETTE` (+ `Led<x>` in `Toon.EMISSIVE` and `Led<x>Off` in the palette),
  rebuild, check with `godot --path . -s tools/pedal_shots.gd -- <dir>` (needs a window).

## Gremlin (first enemy) / adding enemy types
- Pipeline: `blender -b -P blender/enemies/gremlin.py && godot --headless --path . --import` →
  `assets/enemies/gremlin/gremlin.glb` (+ `blender/enemies/gremlin.blend` for inspection).
  `blender/enemies/enemy_common.py` is the shared part: control rig with 2-bone IK chains (pole angles
  auto-calibrated) + Copy Rotation "orient" locks for hands/feet → procedural clips (functions of phase) →
  per-frame bone matrices baked onto a constraint-free export rig at 30 fps → one rigidly skinned mesh → GLB,
  one NLA track per clip. Mesh helpers come from sprite-poc (exec'd, untouched) + `ring_y`, `tube`, `gait`.
- Gremlin: ≤ 1/3 of the rocker (horn tips 0.78 m), dark red `GremlinSkin`, ivory `GremlinHorn` (horns, claws,
  spikes), emissive `GremlinEye` / `GremlinMaw` / `GremlinFire` (fireball held while throwing, scaled by the
  `held` bone). Clips: idle, walk (0.43 m/s), gallop (2.17 m/s), throw (release 0.55 s), slash (hit 0.27 s), hit,
  death (holds). Locomotion is in place: move the body at `GremlinRig.WALK_SPEED` / `GALLOP_SPEED`.
- `scripts/enemies/gremlin_rig.gd` (`GremlinRig`): own 64px SubViewport + outlined Sprite2D, same camera/scale
  as the player (reads `player.gd` consts), feet at the node origin, contact shadow. `facing` (8-dir snap),
  `play(anim)` (one-shots return to the last loop; death holds), `anim_length()`, `hand_point()` /
  `hand_ground()` (throwing claw), `anim_event` (step / throw_release / slash_hit / death_done via method
  tracks from `ANIM_EVENTS`), `action_finished`. `tools/gremlin_shots.gd -- <dir>` (needs a window): pose ×
  8-facing sheet, motion strips, scale shot next to the rocker.
- New enemy: copy gremlin.py's shape (BONES, IK_CHAINS, ORIENT, build_model, clips, `build_enemy(...)`),
  add its materials to `Toon.PALETTE` / `EMISSIVE`, write a rig script like `GremlinRig` (or generalise it
  once there are two), mirror clip event times in its `ANIM_EVENTS`.

## Enemies / AI
- Research + design checklist for new enemies: `docs/ai/enemy_ai_research.md` (read it before adding one).
- Reusable (`scripts/ai/`): `StateMachine`/`AIState` (small HFSM; `update()` returns the next state name,
  unknown names bubble to the parent, `force()` for interrupts, `path()` → "combat/throw"), `Perception`
  (sight cone + close sense + wall LOS, hearing, awareness meter CALM/SUSPICIOUS/ALERT, last-known position;
  `tick()` from the body), `SoundStimulus.emit(source, radius_m)` (group call to every Perception; *not* named
  Noise, which is a Godot class), `AttackTokens` (per-target pools: melee 2, ranged 2), `NavMover`
  (NavigationAgent2D + straight fallback + separation). `scripts/ground.gd` = ground-plane maths (m, m/s).
- Gremlin (`scripts/enemies/`, `scenes/enemies/gremlin.tscn`): body `gremlin.gd` (tunables at the top), brain
  `gremlin_states.gd` (calm idle/pace → investigate "?" → combat "!" engage/throw/reposition/charge/slash/back_off/
  circle → search → return; hurt/dead interrupts), `enemy_fireball.gd` (hits "player", passes allies, bursts on
  walls/props), `enemy_spawner.gd` (main.gd adds it as World/Enemies; spawns at `gremlin_spawn` markers).
  Gremlins die (30 HP) and respawn after 8 s at their marker.
- Player: in group "player", `take_damage` = red flash (sprite_outline `flash` uniform) + shove + number, no
  death (user decision). Notes/strum/swing/casts emit sounds the gremlins hear (`player.NOISE_M`).
- Tests: `godot --headless --path . --fixed-fps 60 -s tools/test_ai.gd` (deterministic, fast); visuals
  `godot --path . -s tools/ai_shots.gd -- <out.png>`. Tests that need the dummies alone free `World/Enemies`.

## Next steps
- Inner outlines between parts (vertex colour `part` is already exported per part group for an ID pass).
- Hand-painted dungeon art can replace the generated atlas in place (same layout).

## Constraints
- No paid services / asset libraries — build originals from the user's descriptions.
- Machine has no Pillow/ffmpeg/ImageMagick. `godot` CLI is on PATH (`godot --headless` works).

## Lessons carried over from the Blender sprite POC (keep these in Godot)
- **Readability = value contrast first.** Dark-on-dark vanishes at sprite size (black sleeves on black plate).
  That's why the arms are bare skin, exaggerated ~30% thicker, with tan wrist wraps; bracers are dark brown leather
  (user's choice). Props must contrast with the armor.
- **Judge the look at real sprite size viewed 3–4x**, never from a hi-res render.
- Chunky, exaggerated proportions beat realism at ~80px (thin swords/necks become 1–2px and disappear).
- Scale: METRES_PER_PX = 3/80 → char ~80px tall; swing reaches ~2.3m so it needs a 128px canvas. Check that nothing
  crops after scale/reach changes.
- Render left-facing directions for real (don't mirror) — mirroring swaps the guitar hand.
- Lighting fixed to world made back views dark — consider lights that follow the camera.
- Idle rest pose == strum frame 0, so idle↔strum cut seamlessly. The swing needs transition blends —
  the user plans to handle these in Godot (AnimationTree blending / fence-post frames).
- Animation details the user liked: hunched older-man walk with planted feet and rigid boots;
  "bull ready to charge" idle breathing; baseball-style swing (hips lead, front knee locks, full arm extension,
  guitar edge aligned to the arc at contact).

## User preferences
- Works in VS Code's terminal with Claude Code (likes Shift+Enter). Has Godot open alongside.
- Fine with pixel shimmer. Prefers seeing results (GIFs/screenshots) over long explanations.
- Wants original assets made from their descriptions; may supply concept art later.
