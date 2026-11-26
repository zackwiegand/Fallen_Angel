# Work plan 2026-11-26: pedals, gremlins, demo floor, run

Six parallel workstreams, each in its own git worktree/branch, merged into `main` by the lead session.
This file is the contract between them: **who owns which files, and the interfaces they meet at.**

## User decisions (2026-11-26)
- Player has **no death**: hits flash/knock back the player and show damage numbers. Gremlins **die** and
  respawn after a delay so the floor stays populated.
- CHIEF delay echoes **spell damage only** (not the guitar swing): 3 echoes, each half the previous
  (10 → 5 → 2.5 → 1.25, rounded, min 1).
- **Pedal order matters for gameplay** (rules below), and also sets the audio chain order and the trail order.
- Demo floor **3–4× the current room**, camera follows the player.

## Folder layout (new code goes here, keep it game-ready)
```
blender/pedals/        build_pedals.py (+ shared helpers), export -> assets/pedals/*.glb
blender/enemies/       gremlin.py (model + rig + baked anims), export -> assets/enemies/gremlin/*.glb
scripts/pedals/        pedal data, pedalboard (chain), pedal trail, pedal view, pickups, menu UI
scripts/enemies/       gremlin body, gremlin rig, enemy projectile, spawner
scripts/ai/            reusable AI pieces (state machine, perception, steering, attack tokens)
docs/ai/               enemy AI research notes (living reference for future enemies)
tools/                 headless tests (test_*.gd, with watchdog) and capture tools (*_shots.gd)
```
Style: match the existing scripts (class_name, `##` doc comments, tunables as named consts at the top,
typed GDScript). No paid assets. Every new feature gets a headless test and a capture tool for visuals.

## Ownership (only the owner edits a file; shared files get small, additive, clearly-commented edits)
| Workstream | Owns |
|---|---|
| A. Pedal models | `blender/pedals/**`, `assets/pedals/**`, `scripts/pedals/pedal_view.gd`, `tools/pedal_shots.gd` |
| B. Pedal gameplay | `scripts/pedals/**` (except pedal_view.gd internals), `scripts/fx/fireball.gd`, `scripts/fx/chain_lightning.gd`, audio buses, `tools/test_pedals.gd` |
| C. Gremlin model | `blender/enemies/**`, `assets/enemies/**`, `scripts/enemies/gremlin_rig.gd`, `tools/gremlin_shots.gd` |
| D. Gremlin AI | `scripts/ai/**`, `scripts/enemies/**` (except gremlin_rig.gd internals), `docs/ai/**`, `tools/test_ai.gd` |
| E. Demo floor | `tools/build_dungeon.gd`, `assets/env/**`, `scenes/dungeon.tscn`, `scripts/dungeon.gd`, `main.gd::_fit_window_to_room` |
| F. Run | `blender/export_gltf.py`, `assets/rocker/**`, `scripts/rocker_rig.gd`, movement code in `scripts/player.gd`, `tools/test_run.gd` |

Shared files: `scripts/player.gd`, `scripts/main.gd`, `scenes/*.tscn`, `CLAUDE.md`. Keep edits there minimal and
localized (one hook, one signal connection, one binding); put the logic in your own new files. Don't
reformat or reorder code you don't own. Add a short section for your feature to `CLAUDE.md`.

## Interfaces
### Damage (existing, keep)
`take_damage(amount: int, kind: StringName, from_dir: Vector2)` and `hit_point() -> Vector2` on anything
hittable. Group `"enemies"` = things the player's spells/swing hit (dummies, gremlins). The player joins
group `"player"` and gets `take_damage`/`hit_point` too (workstream D). Projectiles skip their `caster` and
bodies of their own side (player spells skip `"player"`, gremlin fireballs skip `"enemies"`).
Physics layers stay as they are (everything on layer 1); sides are decided by groups.

### Pedal view (A implements, B uses)
```gdscript
class_name PedalView extends Node2D
func setup(pedal_id: StringName) -> void   # &"chief_delay", &"skyman_phaser"
var facing: Vector2                        # ground dir like player.facing; view snaps to 8 directions
var lit: bool                              # LED / "on" state (bypass = off)
```
Live 3D → pixel like the character (toon shader + outline, small SubViewport, same METRES_PER_PX and 38°
camera as `player.gd`) so the pedals match the art and new pedals are just new .glb files. B may commit a
placeholder `pedal_view.gd` (coloured box) with this exact interface; A's version replaces it at merge.
Pedal size on screen: chunky, readable, roughly 14–18 px wide.

### Gremlin rig (C implements, D uses)
```gdscript
class_name GremlinRig extends Node2D        # owns its SubViewport + Sprite2D, feet at the node origin
signal anim_event(event: StringName)        # &"step", &"throw_release", &"slash_hit", &"death_done"
var facing: Vector2                         # snaps to 8 directions
func play(anim: StringName) -> void         # &"idle", &"walk", &"gallop", &"throw", &"slash", &"hit", &"death"
func anim_length(anim: StringName) -> float
func hand_point() -> Vector2                # local 2D pos of the throwing claw (fireball spawn)
```
D may commit a placeholder `gremlin_rig.gd` (drawn shape) with this exact interface; C's replaces it.
Gremlin height: at most **1/3 of the rocker's height** (rocker ≈ 80 px tall → gremlin ≈ 24–27 px on all fours).

### Level markers (E places in dungeon.tscn, B and D consume)
- `Marker2D` nodes in group `"gremlin_spawn"` (6–10 spread across the floor, not next to the player start).
- `Marker2D` nodes in group `"pedal_spawn"` with metadata `pedal_id` (`&"chief_delay"`, `&"skyman_phaser"`).
- Floor tiles carry a **navigation layer** (pillars/walls excluded) so enemies can use NavigationAgent2D.
- Keep the 7 practice dummies near the player start.
Spawners must still work without markers (fallback positions) so branches test independently.

## Pedal gameplay rules (B)
- Pickups on the floor; walking over one adds it to the end of the chain. Pedals trail the player, linked
  by a sagging sound cable (rope sim), and hover in a loose cluster near the player when idle, in chain order.
- Pedalboard menu (Tab; pauses the game): reorder with arrows / Enter to pick up & drop, footswitch toggle
  (bypass), shows each pedal and the current gameplay rule summary.
- Audio: player's live sounds (notes, strum, spell sfx) go through a `Pedals` AudioServer bus whose effect
  order mirrors the chain (AudioEffectDelay ≈ BOSS-DD style slapback/echo; AudioEffectPhaser). Music stays dry.
- Spells pass through the chain **in order**; each pedal transforms the cast for what comes after it:
  - **Phaser → Delay**: the projectile pierces; every enemy it pierces gets the 3 damage echoes (echo ticks on
    the target, timed to the audio delay).
  - **Delay → Phaser**: the delay repeats the *cast*: 3 ghost projectiles follow the original on the same path
    at 1/2, 1/4, 1/8 damage, and the phaser makes all of them pierce (shimmering purple).
  - Delay alone: echo ticks on the first target hit. Phaser alone: projectile pierces.
  - Lightning: pierce = the chain doesn't stop at its hit count early / passes through (B decides, document it);
    delay = echo ticks per hit or ghost re-chains by the same order rule.
  - Phased projectiles get a shimmery purple aura.
- Bypassed pedals are skipped (sound and gameplay).

## Run (F)
Double-tap a direction (≤ ~0.25 s between taps) to run; keeps running while any direction is held; a short
grace buffer (~0.15 s) with no direction (e.g. quick left → right) doesn't drop out of the run. Run clip in
the old-man style (hunched, heavy, rigid boots), authored in `export_gltf.py`. Tunables as consts.
