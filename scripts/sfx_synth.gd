class_name SfxSynth
## Procedural, bit-crushed sound effects. Each sound is synthesized once into PCM and wrapped as an
## AudioStreamWAV (no audio files). The crush = sample-and-hold downsampling + amplitude quantization.

const RATE := 22050


## Heavy boot on stone: low thump + gravelly noise crunch + a faint armour jingle.
static func footstep(seed: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var n := int(0.22 * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var phase := 0.0
	var lp := 0.0
	var jingle := rng.randf_range(0.04, 0.1)
	var ring_f := rng.randf_range(0.9, 1.15)
	for i in n:
		var t := float(i) / RATE
		phase += TAU * lerpf(120.0, 48.0, minf(t / 0.06, 1.0)) / RATE
		var thump := sin(phase) * exp(-t / 0.035)
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.35          # one-pole low-pass on white noise
		var crunch := lp * exp(-t / 0.045)
		if rng.randf() < 0.01 * exp(-t / 0.05):                 # gravel grains
			crunch += rng.randf_range(-0.8, 0.8)
		var ring := (sin(TAU * 2150.0 * ring_f * t) + 0.7 * sin(TAU * 3320.0 * ring_f * t)
				+ 0.5 * sin(TAU * 4710.0 * ring_f * t)) * exp(-t / 0.09) * jingle
		s[i] = thump * 0.9 + crunch * 0.8 + ring
	return _finish(s, 5, 3, 0.9)


## Whoosh: noise through a band-pass whose centre sweeps up into the strike and back down.
## Peaks at PEAK seconds, so trigger it PEAK before contact.
const SWING_PEAK := 0.22

static func swing() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var n := int(0.5 * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var low := 0.0
	var band := 0.0
	for i in n:
		var t := float(i) / RATE
		var fc: float
		var env: float
		if t < SWING_PEAK:
			var u := t / SWING_PEAK
			fc = lerpf(350.0, 2600.0, u * u)
			env = u * u
		else:
			fc = lerpf(2600.0, 500.0, minf((t - SWING_PEAK) / 0.2, 1.0))
			env = exp(-(t - SWING_PEAK) / 0.07)
		var f := 2.0 * sin(PI * fc / RATE)                       # state-variable filter
		low += f * band
		var high := rng.randf_range(-1.0, 1.0) - low - 0.45 * band
		band += f * high
		s[i] = band * env
	return _finish(s, 6, 2, 0.8)


## Palm-muted E5 power chord, downstroke (strings 7 ms apart), overdriven and crushed.
static func strum() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var n := int(1.8 * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var strings := [82.41, 123.47, 164.81]                     # E2, B2, E3
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var x := 0.0
		for k in strings.size():
			var tk := t - k * 0.007
			if tk < 0.0:
				continue
			var env := 0.75 * exp(-tk / 0.25) + 0.25 * exp(-tk / 1.1)   # chug, then a ringing tail
			for detune in [0.998, 1.002]:
				var ph: float = strings[k] * detune * tk
				x += 2.0 * (ph - floorf(ph + 0.5)) * env       # saw
		x = tanh(x * 2.5)                                      # distortion
		x += rng.randf_range(-1.0, 1.0) * exp(-t / 0.008) * 0.6   # pick attack
		lp += (x - lp) * lerpf(0.6, 0.18, minf(t / 0.3, 1.0))   # bright attack, darker tail
		s[i] = lp
	return _finish(s, 5, 2, 0.85)


## One plucked, overdriven lead note (for the spell keys).
static func note(freq: float) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(freq)
	var n := int(0.9 * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var vib := 1.0 + 0.004 * sin(TAU * 5.5 * t) * minf(t / 0.3, 1.0)   # vibrato swells in
		var ph := freq * vib * t
		var saw := 2.0 * (ph - floorf(ph + 0.5))
		var sq := 1.0 if fmod(ph * 2.0, 2.0) < 1.0 else -1.0                 # octave-up pulse for bite
		var env := minf(t / 0.003, 1.0) * (0.7 * exp(-t / 0.18) + 0.3 * exp(-t / 0.7))
		var x := tanh((saw + 0.35 * sq) * env * 3.0)
		x += rng.randf_range(-1.0, 1.0) * exp(-t / 0.006) * 0.5
		lp += (x - lp) * lerpf(0.7, 0.25, minf(t / 0.2, 1.0))
		s[i] = lp
	return _finish(s, 6, 2, 0.8)


## Chip synth: 25% pulse wave, a quick octave blip on the attack, delayed vibrato, 4-bit crush with
## no downsampling (keeps it bright and 8-bit). The second note-key instrument.
static func chip(freq: float) -> AudioStreamWAV:
	var n := int(0.7 * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var vib := 1.0 + 0.006 * sin(TAU * 6.0 * t) * clampf((t - 0.12) / 0.15, 0.0, 1.0)
		var f := freq * (2.0 if t < 0.03 else 1.0) * vib
		ph += f / RATE
		var x := 1.0 if fmod(ph, 1.0) < 0.25 else -1.0
		var env := minf(t / 0.002, 1.0) * (0.55 * exp(-t / 0.12) + 0.45 * exp(-t / 0.5))
		s[i] = x * env
	return _finish(s, 4, 1, 0.7)


## Fireball launch: roaring low rumble + crackling noise that swells and trails off.
static func fireball() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var n := int(0.6 * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var env := minf(t / 0.04, 1.0) * exp(-t / 0.22)
		phase += TAU * lerpf(90.0, 40.0, t / 0.6) / RATE
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.12
		var crackle := rng.randf_range(-1.0, 1.0) if rng.randf() < 0.03 else 0.0
		s[i] = (sin(phase) * 0.7 + lp * 2.5 + crackle * 0.5) * env
	return _finish(s, 5, 3, 0.85)


## Explosion: noisy boom with a falling cutoff and a sub thump.
static func explosion() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var n := int(0.7 * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += (rng.randf_range(-1.0, 1.0) - lp) * lerpf(0.5, 0.05, minf(t / 0.4, 1.0))
		phase += TAU * lerpf(70.0, 30.0, minf(t / 0.3, 1.0)) / RATE
		s[i] = (lp * 2.0 * exp(-t / 0.16) + sin(phase) * exp(-t / 0.12))
	return _finish(s, 4, 4, 0.9)


## Lightning zap: a falling saw buzz chopped by random crackle gates.
static func zap() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	var n := int(0.18 * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var ph := 0.0
	var gate := 1.0
	for i in n:
		var t := float(i) / RATE
		ph += lerpf(1800.0, 250.0, t / 0.18) / RATE
		if i % 90 == 0:
			gate = 1.0 if rng.randf() < 0.7 else 0.2
		var x := 2.0 * (ph - floorf(ph + 0.5)) * 0.6 + rng.randf_range(-1.0, 1.0) * 0.6
		s[i] = x * gate * exp(-t / 0.07)
	return _finish(s, 4, 2, 0.85)


## Melee thwack on a straw dummy.
static func hit() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 51
	var n := int(0.16 * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.3
		phase += TAU * lerpf(160.0, 70.0, minf(t / 0.05, 1.0)) / RATE
		s[i] = lp * 1.5 * exp(-t / 0.03) + sin(phase) * exp(-t / 0.05)
	return _finish(s, 5, 3, 0.9)


## Looping electric hum for a charging spell: mains-style buzz with random crackle (seamless loop).
static func charge_hum() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 61
	var n := RATE                       # 1 s; 60 Hz and harmonics complete whole cycles, so it loops
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var ph := 60.0 * t
		var buzz := 2.0 * (ph - floorf(ph + 0.5)) * 0.5 + sin(TAU * 180.0 * t) * 0.3
		var crackle := rng.randf_range(-1.0, 1.0) if rng.randf() < 0.02 else 0.0
		s[i] = buzz * 0.6 + crackle * 0.8
	var w := _finish(s, 5, 2, 0.7)
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	return w


## Short rising blip for each new charge (pitched up per charge by the player).
static func charge_tick() -> AudioStreamWAV:
	var n := int(0.09 * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		ph += lerpf(500.0, 1300.0, t / 0.09) / RATE
		s[i] = (1.0 if fmod(ph, 1.0) < 0.5 else -1.0) * exp(-t / 0.04)
	return _finish(s, 4, 2, 0.6)


## Faint glassy ping on every delay-echo hit (it rings through the delay bus too).
static func echo_ping() -> AudioStreamWAV:
	var n := int(0.12 * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		s[i] = (sin(TAU * 1760.0 * t) + 0.4 * sin(TAU * 2640.0 * t)) * exp(-t / 0.03)
	return _finish(s, 5, 2, 0.6)


## Pedal pickup: quick rising square arpeggio (E G B E).
static func pickup() -> AudioStreamWAV:
	var notes := [329.63, 392.0, 493.88, 659.25]
	var step := int(0.06 * RATE)
	var n := step * notes.size() + int(0.2 * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var ph := 0.0
	for i in n:
		var k := mini(i / step, notes.size() - 1)
		var t := float(i - k * step) / RATE
		ph += notes[k] / RATE
		s[i] = (1.0 if fmod(ph, 1.0) < 0.5 else -1.0) * exp(-t / (0.05 if k < notes.size() - 1 else 0.12))
	return _finish(s, 4, 2, 0.7)


## Background loop: Em - C - G - D in E natural minor (the key of the note keys' E minor pentatonic),
## one bar each at `bpm` (default MUSIC_BPM; tap tempo re-synthesizes). Dark detuned-saw pad + plucked 8th-note bass on the roots + drums
## (DRUMS pattern below).
## Chord tails wrap around the loop end, so it loops seamlessly. Pure function: safe on a thread.
const MUSIC_BPM := 100.0              # default tempo
const MUSIC_CHORDS := [
	# name, pad voicing (Hz), bass root (Hz); kept below the note keys (E3..A4) so the melody sits on top
	["Em", [82.41, 123.47, 164.81, 196.00], 82.41],     # E2 B2 E3 G3
	["C", [98.00, 130.81, 164.81, 196.00], 65.41],      # G2 C3 E3 G3
	["G", [98.00, 146.83, 196.00, 246.94], 98.00],      # G2 D3 G3 B3
	["D", [110.00, 146.83, 185.00, 220.00], 73.42],     # A2 D3 F#3 A3
]

# Drum pattern on a 16th-note grid, 16 steps per bar, one row per bar (4 bars).
#   beat:      1 . . . 2 . . . 3 . . . 4 . . .
const DRUMS := {
	"kick":  ["x . . . . . x . x . . x . . . .",
			  "x . . . . . x . x . . x . . x x",     # double-kick flourish
			  "x . . . . . x . x . . x . . . .",
			  "x . . . . . x . x . . . . . . ."],
	"snare": [". . . . x . . . . . . . x . . g",     # g = ghost note
			  ". . . . x . . . . . . . x . . g",
			  ". . . . x . . . . . . . x . . g",
			  ". . . . x . . . . . . . . . . ."],
	"hat":   ["x . x . x . x . x . x . x . o .",     # o = open hat
			  "x . x . x . x . x . x . x . o .",
			  "x . x . x . x . x . x . x . o .",
			  "x . x . x . x . x . x . . . . ."],
	"tom":   [". . . . . . . . . . . . . . . .",
			  ". . . . . . . . . . . . . . . .",
			  ". . . . . . . . . . . . . . . .",
			  ". . . . . . . . . . . . h h l l"],    # fill: high, high, low, low
	"crash": ["x . . . . . . . . . . . . . . .",
			  ". . . . . . . . . . . . . . . .",
			  ". . . . . . . . . . . . . . . .",
			  ". . . . . . . . . . . . . . . ."],
}


## One drum hit as samples (deterministic noise so the loop never changes).
static func _drum(kind: String, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var dur: float = {"kick": 0.35, "snare": 0.25, "hat": 0.05, "open": 0.3, "crash": 1.6, "tom_h": 0.3, "tom_l": 0.35}[kind]
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var ph := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var noise := rng.randf_range(-1.0, 1.0)
		lp += (noise - lp) * 0.25
		var hp := noise - lp                                    # crude high-pass for cymbals
		match kind:
			"kick":
				ph += TAU * (45.0 + 110.0 * exp(-t / 0.03)) / RATE
				s[i] = sin(ph) * exp(-t / 0.16) + noise * exp(-t / 0.004) * 0.4
			"snare":
				ph += TAU * 190.0 / RATE
				s[i] = sin(ph) * exp(-t / 0.05) * 0.6 + lp * 1.6 * exp(-t / 0.09)
			"hat":
				s[i] = hp * exp(-t / 0.012)
			"open":
				s[i] = hp * exp(-t / 0.09)
			"crash":
				var ring := signf(sin(TAU * 540.0 * t)) * 0.2 + signf(sin(TAU * 845.0 * t)) * 0.15
				s[i] = (hp + ring) * exp(-t / 0.5)
			"tom_h", "tom_l":
				var f := 150.0 if kind == "tom_h" else 100.0
				ph += TAU * f * (1.0 + 0.5 * exp(-t / 0.04)) / RATE
				s[i] = sin(ph) * exp(-t / 0.14) + lp * exp(-t / 0.02) * 0.5
	return s


static func music_loop(bpm := MUSIC_BPM) -> AudioStreamWAV:
	var bar := 4.0 * 60.0 / bpm
	var n := int(bar * MUSIC_CHORDS.size() * RATE)
	var mix := PackedFloat32Array()
	mix.resize(n)
	var bar_n := int(bar * RATE)
	var tail_n := int(0.7 * RATE)
	for c in MUSIC_CHORDS.size():
		var start := c * bar_n
		var pad: Array = MUSIC_CHORDS[c][1]
		var root: float = MUSIC_CHORDS[c][2]
		var lp := 0.0
		var blp := 0.0
		var eighth := bar_n / 8
		for i in bar_n + tail_n:
			var t := float(i) / RATE
			# pad: slow swell in, release into the next chord
			var env := minf(t / 0.35, 1.0)
			if i > bar_n:
				env *= exp(-(t - bar) / 0.2)
			var x := 0.0
			for f: float in pad:
				for det in [0.997, 1.003]:
					var ph: float = f * det * t
					x += ph - floorf(ph + 0.5)
			lp += (x * env - lp) * 0.08                    # dark: heavy low-pass
			# bass: palm-muted 8th-note pluck on the root (only within the bar)
			var b := 0.0
			if i < bar_n:
				var tb := float(i % eighth) / RATE
				var phb := root * t
				var accent := 1.0 if (i / eighth) % 2 == 0 else 0.7
				b = tanh(2.0 * (phb - floorf(phb + 0.5)) * 2.0) * exp(-tb / 0.09) * accent
			blp += (b - blp) * 0.15
			mix[(start + i) % n] += lp * 0.5 + blp * 0.6
	# drums
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var hits := {}
	for k in ["kick", "snare", "hat", "open", "crash", "tom_h", "tom_l"]:
		hits[k] = _drum(k, rng)
	var step_n := bar_n / 16
	var levels := {"x": 1.0, "g": 0.35, "o": 1.0, "h": 1.0, "l": 1.0}
	var gain := {"kick": 1.0, "snare": 0.8, "hat": 0.3, "tom": 0.7, "crash": 0.35}
	for part: String in DRUMS:
		for bar_i in 4:
			var steps: PackedStringArray = DRUMS[part][bar_i].split(" ")
			for st in steps.size():
				var c := steps[st]
				if c == ".":
					continue
				var kind := part
				if part == "hat" and c == "o":
					kind = "open"
				elif part == "tom":
					kind = "tom_h" if c == "h" else "tom_l"
				var hit: PackedFloat32Array = hits[kind]
				var at := bar_i * bar_n + st * step_n
				var g: float = gain[part] * levels[c]
				for i in hit.size():
					mix[(at + i) % n] += hit[i] * g
	var w := _finish(mix, 6, 2, 0.75)
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	return w


static func _finish(s: PackedFloat32Array, bits: int, hold: int, peak: float) -> AudioStreamWAV:
	var m := 0.0
	for v in s:
		m = maxf(m, absf(v))
	var q := pow(2.0, bits - 1)
	var held := 0.0
	var bytes := PackedByteArray()
	bytes.resize(s.size() * 2)
	for i in s.size():
		if i % hold == 0:
			held = roundf(s[i] / m * peak * q) / q
		bytes.encode_s16(i * 2, int(clampf(held, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = bytes
	return w
