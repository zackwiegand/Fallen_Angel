extends Control
## Game shell: the 2D world renders into a low-res SubViewport that the container upscales
## (nearest, integer) to the window; the HUD stays at full resolution on top.
## Stretch is off, so a bigger window shows more of the world at the same pixel size; the window
## opens at VIEW_PX game pixels (capped to the screen) and the player's camera follows through the floor.

const PIXEL_SCALE := 4
const VIEW_PX := Vector2i(480, 320)    # game pixels visible when the window opens

const BINDINGS := {
	"move_up": [KEY_UP], "move_down": [KEY_DOWN], "move_left": [KEY_LEFT], "move_right": [KEY_RIGHT],
	"swing": [KEY_J, MOUSE_BUTTON_LEFT], "strum": [KEY_K, MOUSE_BUTTON_RIGHT],
	"cycle_guitar": [KEY_1], "cycle_armor": [KEY_2], "cycle_boots": [KEY_3], "toggle_music": [KEY_M],
	"seq_record": [KEY_Z], "seq_play": [KEY_X], "seq_clear": [KEY_C], "cycle_instrument": [KEY_V],
	"octave_down": [KEY_BRACKETLEFT], "octave_up": [KEY_BRACKETRIGHT], "tap_tempo": [KEY_T], "seq_rest": [KEY_SPACE],
	"pedal_menu": [KEY_TAB], "pedal_bypass": [KEY_B, KEY_SPACE],      # PedalboardMenu (bypass only in the menu)
	# note keys, low to high (Spellbook: E minor pentatonic)
	"note_0": [KEY_Q], "note_1": [KEY_W], "note_2": [KEY_E], "note_3": [KEY_R],
	"note_4": [KEY_A], "note_5": [KEY_S], "note_6": [KEY_D], "note_7": [KEY_F],
}

@onready var player := $Game/GameViewport/World/Player
@onready var hud: Label = $HUD
var music: Music
var sequencer: Sequencer


func _ready() -> void:
	_setup_input()
	music = Music.new()
	music.name = "Music"
	add_child(music)
	# step sequencer: its own Sfx (slightly under live notes), clocked by the backing track
	var loop_sfx := Sfx.new()
	loop_sfx.name = "LoopSfx"
	loop_sfx.note_volume_db = -8.0
	add_child(loop_sfx)
	sequencer = Sequencer.new()
	sequencer.name = "Sequencer"
	sequencer.music = music
	sequencer.sfx = loop_sfx
	add_child(sequencer)
	player.note_played.connect(sequencer.record)
	sequencer.bpm_changed.connect(music.set_bpm)
	var view := SequencerView.new()
	view.sequencer = sequencer
	add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	view.position = Vector2(12, size.y - view.custom_minimum_size.y - 10)
	view.anchor_top = 1.0
	view.anchor_bottom = 1.0
	view.offset_top = -view.custom_minimum_size.y - 10
	view.offset_bottom = -10
	# effect pedals: pickups on the floor + the pedalboard screen (Tab)
	PedalPickup.spawn_all(player.get_parent(), player)
	var pedal_menu := PedalboardMenu.new()
	pedal_menu.name = "PedalboardMenu"
	pedal_menu.pedalboard = player.pedalboard
	pedal_menu.pixel_scale = PIXEL_SCALE
	add_child(pedal_menu)
	$Game.stretch_shrink = PIXEL_SCALE
	_fit_window()


func _fit_window() -> void:
	var screen := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var size := (VIEW_PX * PIXEL_SCALE).min(screen.size - Vector2i(0, 60))      # leave room for the title bar
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED and size != DisplayServer.window_get_size():
		DisplayServer.window_set_size(size)
		DisplayServer.window_set_position(screen.position + (screen.size - size) / 2)


func _process(_delta: float) -> void:
	hud.text = ("Arrows move   J/LMB swing   K/RMB strum   1-3 gear   M music (%s)\n" % (music.current_chord() if not music.muted else "off")
			+ "Notes  Q W E R A S D F  =  E G A B D E G A\n"
			+ "Fire: triad (Q W R, W R A ...)   Lightning: skip 1 3 2 4 3 5... (Q E W R E A ...), pause to release\n"
			+ player.spellbook.describe() + "    Instrument (V): " + Sfx.INSTRUMENTS[player.instrument][0] + "    Octave ([ ]): %+d\n" % player.octave
			+ player.gear_summary() + "\nPedals (Tab): " + player.pedalboard.summary())


func _setup_input() -> void:
	for action: String in BINDINGS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for code: int in BINDINGS[action]:
			var ev: InputEvent
			if action in ["swing", "strum"] and code <= MOUSE_BUTTON_XBUTTON2:
				ev = InputEventMouseButton.new()
				ev.button_index = code
			else:
				ev = InputEventKey.new()
				ev.physical_keycode = code
			InputMap.action_add_event(action, ev)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_music"):
		music.toggle(sequencer.phase())
	elif event.is_action_pressed("tap_tempo"):
		sequencer.tap()
	elif event.is_action_pressed("seq_rest"):
		sequencer.add_rest()
	elif event.is_action_pressed("seq_record"):
		sequencer.toggle_record()
	elif event.is_action_pressed("seq_play"):
		sequencer.toggle_play()
	elif event.is_action_pressed("seq_clear"):
		sequencer.clear()
