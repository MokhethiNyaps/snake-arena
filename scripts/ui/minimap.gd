extends Control
## §13.2 minimap — circular, drawn in one _draw pass at 10 Hz. Shows the
## arena bounds + live shrink ring, the player (bright, with facing tick),
## rivals ONLY within `rival_range` units (sized dots, colour-coded by
## threat), and the last surge marker. Never reveals the whole board.
##
## Owns: nothing but pixels. Talks to: HUD feeds it cached refs each frame.

const RIVAL_RANGE: float = 70.0
const BALANCE: GameBalanceConfig = preload("res://resources/config/game_balance.tres")

var arena: Node3D = null
var player_snake: SnakeController = null
var map_radius_px: float = 78.0
var show_map: bool = true:
	set(v):
		show_map = v
		visible = v

var _surge_pos: Vector3 = Vector3.INF
var _bg: Color = Color(0.04, 0.07, 0.10, 0.55)
var _ring: Color = Color(0.35, 0.85, 0.95, 0.9)


func _ready() -> void:
	custom_minimum_size = Vector2(map_radius_px * 2.0 + 8.0, map_radius_px * 2.0 + 8.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	EventBus.surge_incoming.connect(_on_surge_incoming)


func _on_surge_incoming(pos: Vector3) -> void:
	_surge_pos = pos
	set_process(true)  # keep redrawing while the marker lives


func _map_center() -> Vector2:
	return size * 0.5


func _world_to_map(p: Vector3) -> Vector2:
	var arena_r: float = BALANCE.arena_radius
	var s: float = map_radius_px / maxf(1.0, arena_r)
	return _map_center() + Vector2(p.x, p.z) * s


func _draw() -> void:
	if not show_map or arena == null or player_snake == null:
		return
	var arena_r: float = BALANCE.arena_radius
	# Arena disc + rim.
	draw_circle(_map_center(), map_radius_px, _bg)
	draw_arc(_map_center(), map_radius_px, 0.0, TAU, 48, _ring, 1.2)
	# Live shrink ring (§3.6) while collapsing.
	if arena.combat_manager != null and arena.combat_manager.is_shrinking():
		var s: float = map_radius_px / maxf(1.0, arena_r)
		draw_arc(_map_center(), arena.combat_manager.current_radius() * s,
			0.0, TAU, 48, Color(1.0, 0.35, 0.25, 0.9), 1.6)
	# Surge marker.
	if _surge_pos != Vector3.INF:
		draw_circle(_world_to_map(_surge_pos), 3.0, Color(0.95, 0.4, 1.0, 0.9))
	# Rivals within RIVAL_RANGE only — threat-coloured (§13.2, #45 scaled-int).
	var eat_x10: int = int(round(player_snake.config.eat_power_ratio * 10.0))
	var my_x10: int = int(round(player_snake.power * 10.0))
	if arena.ai_director != null:
		for ai in arena.ai_director.ai_controllers:
			if ai.snake == null or not ai.snake.alive:
				continue
			var d: float = player_snake.global_position.distance_to(ai.snake.global_position)
			if d > RIVAL_RANGE:
				continue
			var their_x10: int = int(round(ai.snake.power * 10.0))
			var col: Color = Color(0.8, 0.8, 0.8, 0.85)
			if their_x10 > my_x10:
				col = Color(0.95, 0.25, 0.2, 0.95)   # can eat me → red
			elif my_x10 >= their_x10 * eat_x10:
				col = Color(0.3, 0.95, 0.4, 0.95)     # I can eat → green
			draw_circle(_world_to_map(ai.snake.global_position), 2.4, col)
	# Player: bright dot + facing tick.
	var me: Vector2 = _world_to_map(player_snake.global_position)
	draw_circle(me, 3.4, Color(1.0, 1.0, 1.0, 1.0))
	var fwd: Vector3 = player_snake.facing_vector()
	draw_line(me, me + Vector2(fwd.x, fwd.z) * 7.0, Color(1.0, 1.0, 1.0, 0.9), 1.4)
