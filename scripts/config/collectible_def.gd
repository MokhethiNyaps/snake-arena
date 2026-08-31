class_name CollectibleDef
extends Resource
## §3.3 — One collectible archetype (sub-resource of CollectibleTable).
##
## Owns: power/score/weight/visual data for one collectible type.
## Does NOT own: spawning or pooling; that is CollectibleManager's job.
## Talks to: nothing; pure data.

enum Type { CELL_SMALL, CELL_MEDIUM, CELL_LARGE, SHARD_RARE, CORPSE_MOTE }
enum MeshShape { SPHERE, OCTAHEDRON, CUBE, DODECAHEDRON }

## Which collectible this defines.
@export var type: Type = Type.CELL_SMALL
## Power granted on collection.
@export var power: float = 1.0
## Score granted on collection.
@export var score: int = 10
## Relative spawn weight (CORPSE_MOTE uses 0: it is only dropped, never random-spawned).
@export var spawn_weight: float = 70.0
## Base material colour.
@export var color: Color = Color(0.1, 0.9, 1.0)
## Primitive mesh used for the pick-up visual.
@export var mesh_shape: MeshShape = MeshShape.SPHERE
## World scale of the mesh.
@export var scale: float = 0.35
## Seconds before despawning; 0 = lives until collected.
@export var decay_time: float = 0.0
