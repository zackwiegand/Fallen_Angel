# Rocker POC (Godot 4.7.2)

## Goal
A playable proof of concept: a metal-rocker character (gothic plate armor, combat boots, guitar as weapon)
who can **move in 8 directions**, **attack (guitar swing)** and **strum** in all 8 directions, rendered
in a chunky pixel-art isometric look (Dead Cells–style).

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
  buffer = window / 4 (bigger window = more view, same sizes); window opens at room size (480×320 → 1920×1280,
  capped to the screen). 1 texel = 1 game px
  = 3/80 m. Ground depth foreshortens by sin 38°, wall height by cos 38°. A 16px tile = 0.6 m wide,
  0.97 m deep (floor), 0.76 m tall (wall face).

## Current architecture (built)
- `blender/export_gltf.py` — `blender -b -P blender/export_gltf.py`. Execs the sprite-poc scripts, adds a plain
  under-layer (body visible with armor/boots off), splits parts into slots (body/armor/boots), rigidly skins
  each slot to one shared skeleton (+ `root` bone = lift/foot planting, + `guitar` bone = prop placement),
  bakes idle/walk/strum/swing at 30 fps, writes `assets/rocker/rocker_base.glb` (rig + body + anims),
  `assets/gear/armor_*.glb`, `boots_*.glb` (rig + mesh, no anims), `guitar_*.glb` (static, sockets kept).
  Then run `godot --headless --path . --import`.
- `scripts/rocker_rig.gd` — loads the base, re-parents skinned gear meshes onto the base Skeleton3D
  (Skin binds resolve by bone name → base animations drive all gear), guitars on a BoneAttachment3D("guitar").
  AnimationTree state machine built in code (idle↔strum cut, swing blends). `anim_fps` > 0 steps playback.
- `scripts/gear_catalog.gd` — items per slot; `recolor` remaps material names to other `Toon.PALETTE` entries.
- `scripts/toon.gd` + `shaders/toon.gdshader` — sprite-poc toon materials (3 bands, Blender lights, Lambert /π),
  swapped in by imported material name. `shaders/sprite_outline.gdshader` — hard alpha + 1px outer outline.
- `scripts/player.gd` — 8-dir movement in screen space, facing snap, input actions (bound in `main.gd`).
- Dungeon: `tools/build_dungeon.gd` generates `assets/env/dungeon_tiles.png` (16px atlas, layout in the
  script header), `dungeon_tileset.tres` and `scenes/dungeon.tscn` (Floor + y-sorted Walls TileMapLayers).
  Wall tiles sort by their base line (y_sort_origin), so the player walks behind pillars.
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
- Controls: arrows move, J swing, K strum, Q W E R A S D F = E minor pentatonic E3 G3 A3 B3 D4 E4 G4 A4, 1-3 gear.
- `scripts/spellbook.gd`: Fire = any E-minor / G-major triad within 1 s (any order/inversion) → `cast`
  animation (new, baked in export_gltf.py `anim_cast`; release at 0.386 s) → `scripts/fx/fireball.gd`.
  Lightning = skip pattern 1 3 2 4 3 5…, up or down; 4 notes = 1 charge, +1 per note (max 12), released on a
  1.2 s pause (Spellbook.SKIP_RELEASE) or pattern break → `scripts/fx/chain_lightning.gd` (N hits; sweeps every dummy in range before revisiting; 7 dummies in an arc).
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
