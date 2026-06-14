extends Camera2D

# ══════════════════════════════════════════════════════════════
#  사용법:
#  1) 씬에 Camera2D 노드를 추가하고(플레이어의 자식이 아니라 별도 노드로)
#     이 스크립트를 붙입니다.
#  2) target_path를 비워두면 "player" 그룹에 등록된 노드를 자동으로 따라갑니다.
#     (player.gd가 _ready에서 자동 등록하므로 그대로 두면 됩니다)
#  3) 직접 지정하고 싶으면 인스펙터의 Target Path에 플레이어 노드를 드래그하세요.
# ══════════════════════════════════════════════════════════════
@export_group("따라가기")
@export var target_path: NodePath        # 비워두면 'player' 그룹에서 자동 탐색
@export var follow_speed: float = 8.0    # 부드러움(클수록 빠르게 따라붙음)

@export_group("룩어헤드")
@export var look_ahead: float = 40.0     # 진행 방향으로 살짝 앞서 보는 거리
@export var look_ahead_speed: float = 4.0 # 룩어헤드가 따라붙는 부드러움

@export_group("제한(선택)")
@export var use_limits: bool = false     # 켜면 카메라가 지정 영역 밖으로 못 나감
@export var limit_top_left: Vector2 = Vector2(-100000, -100000)
@export var limit_bottom_right: Vector2 = Vector2(100000, 100000)

@export_group("흔들림(Shake)")
@export var max_shake_offset: Vector2 = Vector2(14, 9)  # 흔들림 최대 이동량(px)
@export var max_shake_roll: float = 0.03                # 흔들림 최대 회전(라디안), 0이면 회전 없음
@export var shake_decay: float = 1.6                    # 흔들림이 가라앉는 속도
@export var shake_directional: float = 16.0             # 타격 방향으로 치우치는 정도(px)

@export_group("펀치 줌")
@export var punch_zoom_amount: float = 0.05    # 적중 시 줌인 비율
@export var punch_zoom_finisher: float = 0.10  # 마지막 타 줌인 비율
@export var punch_zoom_time: float = 0.18      # 원래 줌으로 복귀 시간

var target: Node2D
var _look_offset: float = 0.0
var trauma: float = 0.0          # 0~1, 클수록 강하게 흔들림
var _shake_dir: Vector2 = Vector2.ZERO  # 흔들림 방향 치우침
var _base_zoom: Vector2 = Vector2.ONE   # 원래 줌(펀치 줌 복귀 기준)


func _ready() -> void:
	make_current()
	_base_zoom = zoom
	_resolve_target()

	if use_limits:
		limit_left = int(limit_top_left.x)
		limit_top = int(limit_top_left.y)
		limit_right = int(limit_bottom_right.x)
		limit_bottom = int(limit_bottom_right.y)

	# 시작 시 대상 위치로 바로 스냅
	if target:
		global_position = target.global_position


func _resolve_target() -> void:
	if target_path != NodePath(""):
		target = get_node_or_null(target_path)
	if target == null:
		var players := get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			target = players[0]


func _physics_process(delta: float) -> void:
	if target == null:
		_resolve_target()
		return

	# 진행 방향에 따라 룩어헤드 목표값 계산
	var target_offset := 0.0
	if target is CharacterBody2D:
		var vx: float = target.velocity.x
		if absf(vx) > 5.0:
			target_offset = signf(vx) * look_ahead
	_look_offset = lerp(_look_offset, target_offset, 1.0 - exp(-look_ahead_speed * delta))

	# 프레임레이트 독립적인 부드러운 추적
	var desired := target.global_position + Vector2(_look_offset, 0.0)
	global_position = global_position.lerp(desired, 1.0 - exp(-follow_speed * delta))

	_update_shake(delta)


# 외부(플레이어)에서 호출: 흔들림 누적 (0~1), dir을 주면 그 방향으로 치우침
func add_shake(amount: float, dir: Vector2 = Vector2.ZERO) -> void:
	trauma = minf(trauma + amount, 1.0)
	if dir != Vector2.ZERO:
		_shake_dir = dir.normalized()


func _update_shake(delta: float) -> void:
	if trauma <= 0.0:
		offset = Vector2.ZERO
		rotation = 0.0
		return
	trauma = maxf(trauma - shake_decay * delta, 0.0)
	var s := trauma * trauma   # 제곱이 더 자연스러운 감쇠
	# 랜덤 흔들림 + 타격 방향 치우침
	var rnd := Vector2(
		randf_range(-1.0, 1.0) * max_shake_offset.x,
		randf_range(-1.0, 1.0) * max_shake_offset.y
	)
	offset = (rnd + _shake_dir * shake_directional) * s
	rotation = randf_range(-1.0, 1.0) * max_shake_roll * s


# 외부(플레이어)에서 호출: 적중 순간 살짝 줌인했다가 원래대로 복귀
func punch_zoom(finisher: bool = false) -> void:
	var amt := punch_zoom_finisher if finisher else punch_zoom_amount
	zoom = _base_zoom * (1.0 + amt)
	var t := create_tween()
	t.set_ignore_time_scale(true)  # 슬로모/정지 중에도 실시간으로 복귀
	t.tween_property(self, "zoom", _base_zoom, punch_zoom_time)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
