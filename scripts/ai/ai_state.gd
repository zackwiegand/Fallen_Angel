class_name AIState
extends RefCounted
## One state of a StateMachine. Override enter/exit/update/on_event.
## update() returns the name of the state to switch to, or &"" to stay. A name the owning machine
## doesn't know bubbles up to the parent machine (hierarchical FSM): a leaf like "slash" can return
## "search" and the top-level machine handles it.
## A state may own a child machine (`sub`); it runs after this state's own update.

var name: StringName
var machine: StateMachine
var agent: Node                 # the body this brain drives
var sub: StateMachine           # optional child machine (composite state)


func enter() -> void:
	pass


func exit() -> void:
	pass


func update(_delta: float) -> StringName:
	return &""


## Gameplay/animation events (e.g. &"throw_release"), routed to the active state chain.
func on_event(_event: StringName) -> void:
	pass


## Seconds since this state was entered.
func elapsed() -> float:
	return machine.time_in_state
