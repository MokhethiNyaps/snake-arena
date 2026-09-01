class_name CollectBurst
extends Node3D
## Pooled one-shot collect burst (§11: particle bursts are pooled).
## Release back to the pool is ticked by CollectibleManager (deterministic,
## works headless — the particles' own "finished" signal needs a renderer).
##
## Owns: the GPUParticles3D node and its per-instance material colour.
## Does NOT own: pool timing (manager) or spawn decisions.
## Talks to: CollectibleManager via the pool registry.

@onready var particles: GPUParticles3D = $Particles


func fire(color: Color) -> void:
	var mat: ParticleProcessMaterial = particles.process_material
	mat.color = color
	particles.restart()
	particles.emitting = true
	visible = true


func stop() -> void:
	particles.emitting = false
	visible = false
