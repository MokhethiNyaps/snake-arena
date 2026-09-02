class_name CollectibleNode
extends Node3D
## §3.3 — One pooled, live collectible (cells, rare shard, corpse mote).
## Pure DATA + logic since Phase 10: position/def/values/decay for the
## manager's hash and collection code. NO visuals — CollectibleRenderer
## draws every alive node through per-shape MultiMeshes (§19: 420 individual
## meshes measured ~840 draw calls vs the 150 budget; see decision #71).
##
## Owns: the CollectibleDef it was spawned as and its power/score values
##       (corpse motes override the def's).
## Does NOT own: the pool, the hash, collection logic, or any rendering.
## Talks to: nobody — the manager reads its fields.

var def: CollectibleDef = null
## Power granted when absorbed (corpse motes override the def value).
var power_value: float = 0.0
## Score granted when absorbed (corpse motes override the def value).
var score_value: float = 0.0
## Seconds until this mote decays; 0 = lives until collected.
var decay_remaining: float = 0.0
## True once absorb/release has been requested this tick (manager bookkeeping).
var consumed: bool = false

## Configures the pooled node for a new life.
func activate(p_def: CollectibleDef, p_power: float, p_score: float, pos: Vector3) -> void:
	def = p_def
	power_value = p_power
	score_value = p_score
	decay_remaining = p_def.decay_time
	consumed = false
	global_position = pos
	visible = true


## Release back to the pool, unregistered from the hash by the manager.
func deactivate() -> void:
	consumed = true
	def = null
	visible = false






