class_name AttackTokens
## Attack permission tokens (Doom 2016 / "battle circle"): an enemy must hold a token for an attack
## kind before it attacks a target, so only a few attack at once and the rest circle, wait and
## telegraph. Pools are per target and per kind; holders that are freed drop their tokens.
##   if AttackTokens.request(player, &"melee", self): ...   # attack
##   AttackTokens.release(player, &"melee", self)          # when the attack (or the attempt) ends
## Limits are tunable per kind (a difficulty knob: more tokens = more aggressive enemies).

const DEFAULT_LIMIT := 1

static var limits := {&"melee": 2, &"ranged": 2}
static var _pools := {}          # "target_id:kind" -> Array[int] (holder instance ids)


static func request(target: Object, kind: StringName, holder: Object) -> bool:
	var pool := _pool(target, kind)
	var id := holder.get_instance_id()
	if id in pool:
		return true
	if pool.size() >= int(limits.get(kind, DEFAULT_LIMIT)):
		return false
	pool.append(id)
	return true


static func release(target: Object, kind: StringName, holder: Object) -> void:
	if target == null or holder == null:
		return
	_pool(target, kind).erase(holder.get_instance_id())


## Drop every token this holder has (death, despawn).
static func release_all(holder: Object) -> void:
	var id := holder.get_instance_id()
	for key: String in _pools:
		(_pools[key] as Array).erase(id)


static func holds(target: Object, kind: StringName, holder: Object) -> bool:
	return target != null and holder.get_instance_id() in _pool(target, kind)


static func count(target: Object, kind: StringName) -> int:
	return _pool(target, kind).size()


static func reset() -> void:
	_pools.clear()


static func _pool(target: Object, kind: StringName) -> Array:
	var key := "%d:%s" % [target.get_instance_id(), kind]
	if not _pools.has(key):
		_pools[key] = []
	var pool: Array = _pools[key]
	for id: int in pool.duplicate():               # holders freed without releasing
		if not is_instance_id_valid(id):
			pool.erase(id)
	return pool
