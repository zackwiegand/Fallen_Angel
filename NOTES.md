# Rocker POC: session notes (2026-11-25)

A summary for picking this up later. The architecture and the "how to" details live in `CLAUDE.md`; this file covers what was built, why, and what's open.
**Next session: start planning the actual game** (the user's words: "good framework, may begin to make it an actual game next time with some planning").

## Game premise (from the user)
A rocker dude goes through dungeons and hell. He fights melee with his guitar and **casts spells by playing note patterns**, with different patterns for different spells. The game is **2D**: a 3D rig renders the pixel-art character sprites live. The camera is a **front 3/4 view and never rotates**.

## What exists now (all working, all tested)
| Area | State |
|---|---|
| Character | sprite-poc rocker exported by `blender/export_gltf.py` (headless Blender). Gear slots body/armor/boots share one skeleton; guitars ride a `guitar` bone. Toon shader and outline match the Blender sprites. |
| Animations | idle / walk / strum / swing from sprite-poc (baked), plus a new **cast** (fireball thrust) built in the export script. A front-view tuning block overrides sprite-poc's arm poles and fret position. |
| Gear swap | 1/2/3 cycle guitar (Reaper, Battle-axe) / armor (Gothic, Bone recolour, none) / boots (Combat, Oxblood, none). |
| Movement | arrow keys, 8 directions, facing snapped to 45°. 320-wide game buffer ×4 nearest; the window is sized to show the whole room. |
| Dungeon | generated 16px tiles (cobble floor, brick walls), y-sorted walls, **7 practice dummies in an arc** (never die; flash, wobble, pixel damage numbers). |
| Notes | Q W E R A S D F = E minor pentatonic E3–A4. Two instruments (V): lead guitar, chip synth. Octave shift [ ] (−2..+2, sound only). A procedural **hands layer** (two-bone IK modifier) frets and picks each note over idle/walk. |
| Spells | **Fire** = any Em/G triad within 1 s → cast animation → fireball (12 dmg). **Lightning** = skip pattern 1 3 2 4 3 5…, up or down with edge turnarounds; 4 notes = 1 charge, +1 per note (max 30); releases after a 1.2 s pause or a pattern break; chains across every dummy before revisiting (5 dmg per hit). Lightning **charge aura** grows per charge, with a hum and per-charge ticks. Swing does 8 melee damage. |
| Audio | Everything is synthesized and bit-crushed in GDScript (no audio files): steps, swing, strum, notes, spells, hits. **Backing track** Em–C–G–D with drums, 100 BPM default, M toggles, user set its volume to +2 dB. |
| Step sequencer | Z rec on/off, notes = steps (chords if pressed together), Space = rest, length = steps entered (max 64), X play/stop, C clear, T tap tempo (the music re-synthesizes and stays in phase). Remembers instrument and octave per step. HUD piano-roll strip. |

Tests (all headless, all passing): `tools/test_logic.gd`, `test_spells.gd`, `test_hands.gd`, `test_sfx.gd`, `test_music.gd`, `test_sequencer.gd`. Visual capture tools: `capture.gd`, `closeup.gd`, `screenshot.gd`, `spell_shots.gd`, `aura_shots.gd`, `hands_shots.gd`.

## How the user works / likes things
- Wants to *see* results (screenshots, sheets) and prefers short explanations; asks follow-ups in plain terms (e.g. "loop controls again?").
- Iterates fast with small feel tweaks (timing windows, volume, bounce behaviour), so expose tunables as named constants at the top of scripts.
- Tunes values themself (music VOLUME_DB → +2). Respect their edits and loosen tests rather than revert.
- Uses the editor's embedded **Game** tab; input only works in **Input** mode (it confused them once).
- Plays slowly, so keep pattern timing generous (the lightning release went 0.55 → 1.2 s on request).
- Uses plain terms for features ("bounce", "aura", "stagger back down"); confirm the exact key order when explaining patterns.

## Workflow decision
Blender stays in the pipeline for models and for authoring new animations (like the cast clip); Godot handles runtime layers (the IK hands) and gameplay. See CLAUDE.md, "Animation workflow".

## Gotchas learned
- Blender's glTF `guitar` bone frame stays in Z-up axes; guitars mount under +90° X (`rocker_rig.gd`). `tools/socket_check.gd` verifies it.
- The toon lighting needs Lambert /π to match Blender's band thresholds.
- pipeline.py's `OUT` global clobbered our path once; the export script uses `ASSETS`.
- SkeletonModifier3D results only exist inside `modification_processed` (Godot restores the animated pose after skinning).
- AnimationTree state machines sit at `Start` until a travel(); Start→idle is now AUTO.
- A SCRIPT ERROR in a headless test hangs Godot (macOS has no `timeout`), so tests carry a watchdog timer.
- Bash heredoc/Python edits invalidate the editor's file-read state; re-Read before Write.

## Open threads / ideas for planning the real game
- **Fire spell charging**: undecided (user: "not sure about fire yet"). The aura has per-spell palettes ready (`ChargeAura.PALETTES`).
- More spells and patterns (the spellbook is built to add detectors). Harmony-aware bonuses via `Music.current_chord()`.
- Real enemies (AI, health, death) to replace the dummies; player health/mana; a damage model per element.
- Rooms → dungeon generation, "hell" biome palette; hand-drawn or concept art could replace the generated tiles (same atlas layout).
- Inner outlines between body parts (vertex colour `part` already exported); palette quantize.
- Save state: tempo, sequences, gear.
- Not done: per-loop tempo, saving sequences, fire charge, controller support, menus.
