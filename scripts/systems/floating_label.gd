class_name FloatingLabel
extends Node3D
## Pooled floating score label (§11: labels are pooled, 30 prewarmed).
## Billboards toward the camera, rises and fades over its lifetime.
## Release is ticked by CollectibleManager (deterministic, headless-safe).
##
## Owns: the Label3D and its fade state.
## Does NOT own: pool timing (manager).
## Talks to: CollectibleManager via the pool registry.

@onready var label: Label3D = $Label

var _lifetime: float = 0.0
var _total: float = 0.0


func show_text(text: String, color: Color) -> void:
	label.text = text
	label.modulate = color
	_lifetime = 0.0
	_total = CollectibleManager.LABEL_LIFETIME
	visible = true


## Rises and fades. Called by CollectibleManager each tick while alive.
func advance(delta: float) -> void:
	_lifetime += delta
	global_position.y += CollectibleManager.LABEL_RISE_SPEED * delta
	var t: float = clampf(_lifetime / _total, 0.0, 1.0)
	var alpha: float = 1.0 if t < 0.5 else 1.0 - (t - 0.5) * 2.0
	label.modulate.a = alpha


func stop() -> void:
	visible = false
