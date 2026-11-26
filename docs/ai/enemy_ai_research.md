# Enemy AI: research notes and design reference

A living reference for designing enemies in this game. Update it when a new enemy teaches us something.
Code lives in `scripts/ai/` (reusable) and `scripts/enemies/` (per enemy). First user: the gremlin
(`scripts/enemies/gremlin.gd`, `gremlin_states.gd`).

## 1. Decision architectures

| Technique | Good at | Weak at | Use here? |
|---|---|---|---|
| **FSM** | Few clear modes, cheap, easy to debug ("what state is it in?") | Transition spaghetti as states grow; duplicated checks | Leaves of the HFSM |
| **Hierarchical FSM** | Groups modes (calm / combat / search) so shared checks live once in the parent; scales to ~20 states | Still hand-authored transitions | **Yes: our default** |
| **Behaviour tree** | Large, reusable behaviour libraries; designers composing in an editor | Reactive interrupts and "remember what I was doing" need extra machinery; overhead for small enemies | Later, if we get many enemy types sharing sub-behaviours |
| **Utility AI** | Picking the best of many options with fuzzy scores; emergent feel | Hard to tune and to predict; needs good curves | Inside one decision node when choices multiply (e.g. which attack) |
| **GOAP / HTN** | Multi-step plans with preconditions (stealth/sim NPCs) | Overkill for action-game enemies; planning cost; hard to make readable | No |

Sources: Game AI Pro, ch. 1 "Behavior Selection Algorithms: An Overview" (Dawe, Gargolinski, Dicken,
Humphreys, Mark), free at <https://www.gameaipro.com/>; utility chapters 9–10 there; FSM vs BT comparison
<https://arxiv.org/pdf/2405.16137>; "Are behavior trees a thing of the past?"
<https://gamedeveloper.com/programming/are-behavior-trees-a-thing-of-the-past->.

**What we chose:** a small HFSM (`StateMachine` + `AIState`). Our enemies have a handful of readable modes,
the player must be able to read them ("it's pacing", "it's winding up", "it lost me"), and a state name
is the best debug tool (`brain.path()` → `combat/throw`). One **decision node** per composite
(`Engage`) picks the next leaf from distance, sight, cooldowns and tokens; that's where a utility score
would go if choices grow. Transitions are return values; unknown names bubble to the parent machine,
so leaves can say "search" without knowing the hierarchy. Interrupts (hurt, dead) are `force()`d.

## 2. Perception

- **Sight = cone + close sense + line of sight.** Guards use one or several view cones (Alien: Isolation's
  Xenomorph uses normal, focused, peripheral and close cones). A small 360° "close" radius stops the
  player from standing behind an enemy unnoticed. We raycast against walls/pillars only (other bodies
  don't block sight).
- **Awareness meter, not a boolean.** Calm → suspicious → alert, filling faster the closer the player
  is (stealth games use near/mid/far cones with different rates). Suspicious = turn and look / go
  investigate ("?"); alert = combat ("!"). Alert is latched until the enemy gives up searching.
- **Hearing = radius per sound.** Every sound has a gameplay radius (a stone vs a gunshot). Ours: guitar
  notes 9 m, strum 12 m, spells 10–12 m, swing 5 m, footsteps 2 m (`player.gd NOISE_M`). A noise adds
  awareness by loudness (distance) and moves the last known position. Since the player *casts by
  playing music*, hearing is the main way gremlins notice you: spellcasting is loud.
- **Last known position (LKP).** Keep updating it for a short time (~0.5 s) after losing sight ("they
  went that way"), then go there, look around, give up, return home. Being hit always alerts and
  points the LKP at the attacker.

Sources: "How Stealth Game Guards See and Hear" (Game Maker's Toolkit, School of Stealth part 1,
transcript <https://amara.org/videos/4SwBdOk0E4LH/en/3100597>); "The NPC AI of The Last of Us: a case study"
<https://arxiv.org/pdf/2207.00682>; stealth enemy breakdown
<https://n2h-games.itch.io/stealth-game-prototype/devlog/849809/mechanical-breakdown-enemy-behavior>;
"Examining the essential building blocks of stealth play"
<https://gamedeveloper.com/design/examining-the-essential-building-blocks-of-stealth-play>.

## 3. Group combat: attack tokens and the battle circle

- **Tokens (Doom 2016).** A shared pool per attack type; an enemy must take a token before attacking and
  returns it afterwards. No token → do something else (circle, reposition, taunt). Higher difficulty =
  more tokens. Demons could steal a token if better placed. Source: "Cyber Demons: the AI of DOOM (2016)"
  <https://www.gamedeveloper.com/design/cyber-demons-the-ai-of-doom-2016->, GDC "Bringing Hell to Life"
  <https://gdcvault.com/play/1024186/Bringing-Hell-to-Life-AI>.
- **Battle circle (Arkham, Assassin's Creed).** Enemies ring the player at a "danger" radius, ask
  permission to attack, strafe while denied; max ~2 simultaneous attackers. "Cinematic" circles wait
  politely, "dangerous" ones (Souls) mob more. Source:
  <https://code.tutsplus.com/battle-circle-ai-let-your-player-feel-like-theyre-fighting-lots-of-enemies--gamedev-13535t>.
- **Regulate the pace.** God of War-style regulation: not everyone attacks at once, a few seconds between
  attacks per enemy, don't attack from off-screen, ease off while the player is recovering. Source:
  "Enemy design and enemy AI for melee combat systems"
  <https://gamedeveloper.com/design/enemy-design-and-enemy-ai-for-melee-combat-systems>.

**What we chose:** `AttackTokens` (static pools per target × kind; `melee` 2, `ranged` 2). Gremlins without
a melee token orbit at `CIRCLE_M` and re-ask every 0.6 s. Tokens are released on every exit path (end of
attack, failed charge, stagger, death).

## 4. Readable attacks (telegraph → strike → recovery)

- Dark Souls 3 breakdown: opening pose (telegraph) → attack signal (hitbox off) → active → end pose →
  return. Human reaction ≈ 240 ms, so signal + attack should be **≥ 340 ms**; recovery ≥ 170–240 ms is
  the player's punish window. Source: <https://www.gamedeveloper.com/game-platforms/anatomy-of-an-enemy-attack-in-dark-souls-3>.
- Telegraph with silhouette + VFX + sound; keep it consistent so it can be learned. Hit-reaction clarity
  matters as much (Hades II legibility critique <https://nex-3.com/blog/hades-ii-has-a-legibility-problem/>,
  <https://gamedeveloper.com/design/enemy-attacks-and-telegraphing>).
- Doom: exaggerated animation sells each demon's intent; pain reactions interrupt attacks; accuracy
  drops when the player moves fast (fair projectiles).

**What we chose:** gremlin throw = 0.45 s windup with an ember swelling in the claw (drawn over the rig),
release, 0.25 s gap, 2–3 per volley, then 3–4.5 s cooldown. Slash = 0.32 s windup (tracks the target
during the first 40%, then commits), hit check at `slash_hit`, recovery + `back_off` (punish window), 40%
combo chance. "!" bark + 0.4 s pause on alert, "?" when investigating/searching. Any hit staggers (small
creature) and cancels windups. Fireballs fly at 4 m/s (player walks 1.4) with a little spread.

## 5. Movement

- **Steering + navigation.** Seek/arrive toward the next navmesh corner; separation keeps a pack apart;
  orbit (tangent) for strafing/circling. Godot 4: `NavigationAgent2D.get_next_path_position()`; wait for
  the map to sync (`NavigationServer2D.map_get_iteration_id(map) != 0`) before querying; don't keep
  querying after `is_navigation_finished()` (jitter). Source:
  <https://docs.godotengine.org/en/4.4/tutorials/navigation/navigation_using_navigationagents.html>.
- **What we chose:** `NavMover` (extends NavigationAgent2D) re-paths only when the goal moves > 6 px,
  treats a finished path as "arrived / as close as possible", falls back to straight steering when the
  level has no navmesh. Separation from other `enemies` instead of RVO avoidance (cheap, deterministic).
  All maths on the ground plane (`Ground`): speeds in m/s, distances in metres, screen = foreshortened.
- Ranged enemies keep distance (Doom inverted cover logic to find spots *visible* to the player).
  Gremlins: throw between 3.5 and 8.5 m, prowl closer while on cooldown, then commit to melee.

## 6. Checklist for the next enemy

1. **Role in a fight** (rusher, shooter, tank, support) and what it teaches the player.
2. **Senses**: sight range / FOV / close radius, hearing scale (`Perception` exports). Does it react to music?
3. **States**: reuse calm → investigate → combat → search → return; write only the combat leaves.
   Keep one decision node per composite; leaves return names.
4. **Every attack**: telegraph (anim + VFX + sound) ≥ 0.34 s before the active frame, hit check on an
   anim event, recovery window, cooldown, which token kind it needs.
5. **Spacing**: preferred range band, what it does while waiting for a token (circle, reposition, taunt).
6. **Hit reactions**: stagger threshold (small things always flinch; big ones need poise damage), death,
   respawn or not.
7. **Readability pass at real pixel size (3–4× zoom)**: can you tell calm / alert / winding up / recovering
   from the sprite alone? Add barks/VFX if not.
8. **Tests** in `tools/test_ai.gd` style (headless, `--fixed-fps 60`, watchdog): stays home when calm,
   alerts by sight and sound, uses each attack in its band, respects tokens, de-aggros, dies/respawns.
9. **Tunables as consts** at the top of the enemy script; note the user's feel tweaks here.

## 7. Open questions / ideas

- Difficulty knob: token limits, windup lengths, projectile speed, accuracy vs player speed (Doom).
- Harmony-aware enemies: react to the backing track's chord or to specific spells (e.g. lightning stuns).
- Utility scoring in `Engage` once enemies have 3+ attacks.
- Gremlin sounds (chitter on alert, throw grunt, slash hiss) to complete the telegraphs.
