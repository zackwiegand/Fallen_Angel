class_name StateMachine
extends RefCounted
## Small hierarchical finite state machine (HFSM) for enemy brains. See docs/ai/enemy_ai_research.md
## for why an HFSM (and not a behaviour tree / utility AI) fits our enemies.
##
##   var brain := StateMachine.new(self)
##   brain.add(&"calm", CalmState.new())          # CalmState may build its own `sub` machine
##   brain.start(&"calm")
##   brain.update(delta)                            # from _physics_process
##
## Transitions are returned by AIState.update(); unknown names bubble to the parent machine.
## force() interrupts from outside (hurt, death) without asking the current state.

signal changed(from: StringName, to: StringName)

var agent: Node
var parent: StateMachine
var states := {}                 # StringName -> AIState
var current: AIState
var current_name: StringName = &""
var previous_name: StringName = &""
var time_in_state := 0.0


func _init(owner_agent: Node, parent_machine: StateMachine = null) -> void:
	agent = owner_agent
	parent = parent_machine


func add(state_name: StringName, state: AIState) -> AIState:
	state.name = state_name
	state.machine = self
	state.agent = agent
	states[state_name] = state
	return state


## Child machine for a composite state; its unknown transitions bubble up to this machine.
func make_sub() -> StateMachine:
	return StateMachine.new(agent, self)


func start(state_name: StringName) -> void:
	_switch(state_name)


func update(delta: float) -> void:
	if current == null:
		return
	time_in_state += delta
	var next := current.update(delta)
	if next != &"":
		request(next)
		return
	if current.sub:
		current.sub.update(delta)


## Change state by name; names this machine doesn't own go to the parent.
func request(state_name: StringName) -> void:
	if states.has(state_name):
		_switch(state_name)
	elif parent:
		parent.request(state_name)
	else:
		push_error("StateMachine: unknown state %s" % state_name)


## Interrupt from outside (re-enters even if already in that state).
func force(state_name: StringName) -> void:
	_switch(state_name)


func dispatch(event: StringName) -> void:
	if current == null:
		return
	var s := current
	s.on_event(event)
	if s == current and s.sub:        # the event may have caused a transition
		s.sub.dispatch(event)


## Full active path, e.g. "combat/throw" (debug HUD, tests).
func path() -> String:
	if current == null:
		return ""
	var p := String(current_name)
	if current.sub and current.sub.current:
		p += "/" + current.sub.path()
	return p


func _switch(state_name: StringName) -> void:
	var prev := current_name
	if current:
		if current.sub:
			current.sub._exit_all()
		current.exit()
	current = states[state_name]
	previous_name = prev
	current_name = state_name
	time_in_state = 0.0
	current.enter()
	changed.emit(prev, state_name)


func _exit_all() -> void:
	if current:
		if current.sub:
			current.sub._exit_all()
		current.exit()
	current = null
	current_name = &""
