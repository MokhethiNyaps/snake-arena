class_name PowerUpPickup
extends Node3D
## §10 — The pooled power-up pickup: a spinning emissive prism tinted by
## the def's aura colour, so players can read WHICH verb is on the ground
## before they eat it. No per-node _process — PowerUpManager ticks it.
##
## Owns: its visual. Nothing else.
## Talks to: PowerUpManager only.

@onready var mesh: MeshInstance3D = $Mesh


func activate(def: PowerUpDef) -> void:
	var mat: StandardMaterial3D = mesh.material_override as StandardMaterial3D
	if mat == null:
		mat = StandardMaterial3D.new()
		mat.emission_enabled = true
		mat.emission_energy_multiplier = 1.6
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh.material_override = mat
	mat.albedo_color = def.aura_color
	mat.emission = def.aura_color
	visible = true


func deactivate() -> void:
	visible = false
