extends CharacterBody2D

# ══════════════════════════════════════════════════════════════
#  연습용 허수아비
#  사용법:
#  1) 씬에 CharacterBody2D 노드를 추가하고 이 스크립트를 붙입니다.
#  2) layer_bit을 player.gd의 enemy_layer_bit과 같은 값(기본 3)으로 맞춥니다.
#     → 그래야 플레이어 공격 히트박스가 이 허수아비를 감지합니다.
#  콜리전 모양과 HP 라벨은 코드에서 자동 생성되므로 따로 안 만들어도 됩니다.
#
#  플레이어가 호출하는 인터페이스:
#    take_damage(amount: int)
#    apply_knockback(force: Vector2)
# ══════════════════════════════════════════════════════════════
@export var max_hp: int = 1000
@export var layer_bit: int = 3                 # 플레이어 enemy_layer_bit과 동일하게
@export var world_layer_bit: int = 1           # 바닥/벽이 속한 레이어
@export var body_size: Vector2 = Vector2(40, 64)
@export var knockback_friction: float = 1200.0 # 넉백이 잦아드는 정도
@export var respawn_delay: float = 1.0         # 0이면 죽을 때 사라짐, >0이면 부활(연습용)
@export var body_color: Color = Color(0.82, 0.42, 0.36)

var hp: int
var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
var _alive: bool = true
var _label: Label
var _base_scale: Vector2


func _ready() -> void:
	hp = max_hp
	_base_scale = scale
	collision_layer = 1 << (layer_bit - 1)        # 플레이어 히트박스가 감지할 레이어
	collision_mask = 1 << (world_layer_bit - 1)   # 바닥 위에 서있도록
	_setup_shape()
	_setup_label()
	queue_redraw()
	# 플레이어가 그룹에 등록된 뒤(_ready 이후) 충돌 예외를 걸기 위해 지연 호출
	call_deferred("_ignore_player_collision")


func _ignore_player_collision() -> void:
	# 플레이어와는 서로 통과(물리 충돌 무시). 바닥 등 다른 충돌은 그대로 유지.
	for p in get_tree().get_nodes_in_group("player"):
		if p is PhysicsBody2D:
			add_collision_exception_with(p)
			p.add_collision_exception_with(self)


func _setup_shape() -> void:
	# 콜리전 모양이 없으면 코드로 생성
	if get_node_or_null("CollisionShape2D") == null:
		var cs := CollisionShape2D.new()
		cs.name = "CollisionShape2D"
		var rect := RectangleShape2D.new()
		rect.size = body_size
		cs.shape = rect
		add_child(cs)


func _setup_label() -> void:
	_label = Label.new()
	_label.position = Vector2(-body_size.x * 0.5, -body_size.y * 0.5 - 30)
	add_child(_label)
	_update_label()


func _update_label() -> void:
	if _label:
		_label.text = "HP %d / %d" % [hp, max_hp]


func _physics_process(delta: float) -> void:
	# 중력
	if not is_on_floor():
		velocity.y += gravity * delta
	# 넉백은 마찰로 서서히 잦아듦
	velocity.x = move_toward(velocity.x, 0.0, knockback_friction * delta)
	move_and_slide()


func _draw() -> void:
	# 스프라이트가 없어도 보이도록 사각형으로 몸통을 그립니다.
	var rect := Rect2(-body_size * 0.5, body_size)
	draw_rect(rect, body_color)                       # 몸통
	draw_rect(rect, Color(0, 0, 0, 0.6), false, 2.0)  # 테두리


# ══════════════════════════════════════════════════════════════
#  플레이어가 호출하는 인터페이스
# ══════════════════════════════════════════════════════════════
func take_damage(amount: int) -> void:
	if not _alive:
		return
	hp -= amount
	_update_label()
	_flash()
	_punch()
	if hp <= 0:
		_die()


func apply_knockback(force: Vector2) -> void:
	if not _alive:
		return
	velocity += force


# ── 피격 반응 ──
func _flash() -> void:
	modulate = Color(3, 3, 3)   # 흰색으로 번쩍
	var t := create_tween()
	t.tween_property(self, "modulate", Color.WHITE, 0.15)


func _punch() -> void:
	scale = _base_scale * Vector2(0.8, 1.2)  # 세로로 찌부 → 복귀
	var t := create_tween()
	t.tween_property(self, "scale", _base_scale, 0.18)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _die() -> void:
	_alive = false
	if respawn_delay <= 0.0:
		queue_free()
		return
	# 잠깐 반투명해졌다가 부활 (연습용 무한 타겟)
	modulate = Color(1, 1, 1, 0.25)
	if _label:
		_label.text = "..."
	await get_tree().create_timer(respawn_delay).timeout
	hp = max_hp
	_alive = true
	modulate = Color.WHITE
	_update_label()
