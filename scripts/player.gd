extends CharacterBody2D

# ══════════════════════════════════════════════════════════════
#  인스펙터에서 조절 가능한 값들 (@export)
#  씬에서 플레이어 노드를 선택하면 우측 인스펙터에 그룹별로 표시됩니다.
# ══════════════════════════════════════════════════════════════
@export_group("이동")
@export var walk_speed: float = 110.0     # 걷기 속도
@export var run_speed: float = 200.0      # 달리기 속도(Shift를 누르고 있을 때)
@export var jump_velocity: float = -300.0 # 점프력(음수: 위 방향)

@export_group("점프 / 중력")
@export var fall_gravity_multiplier: float = 1.8   # 내려올 때 중력 배수(클수록 빨리 떨어짐)
@export var max_fall_speed: float = 900.0          # 최대 낙하 속도(종단 속도)
@export_range(1, 8) var gravity_substeps: int = 4  # 오일러 적분 분할 횟수
# 가변 점프: jump_velocity가 최대 높이, min_jump_velocity가 최소 높이.
# 스페이스를 짧게 누르면 min, 끝까지 누르면 max 높이까지 올라갑니다(둘 다 음수).
@export var min_jump_velocity: float = -150.0      # 짧게 눌렀을 때 최소 점프 속도

@export_group("돌진 / 콤보")
# 콤보 단계별 돌진 초기 속도. index = 콤보 번호이므로 0번은 비워둠(1~3 사용)
@export var lunge_speed: Array[float] = [0.0, 260.0, 260.0, 380.0]
@export var dash_friction: float = 1800.0 # 돌진 후 미끄러지며 멈추는 마찰력

@export_group("공격 중 조작감")
@export var lunge_time: float = 0.20                      # 한 타의 돌진 구간 기준 시간
@export_range(0.0, 1.0, 0.05) var dash_lock_ratio: float = 0.9  # 이 비율까지는 돌진(입력 잠금)
@export var attack_move_speed: float = 60.0              # 잠금 이후 반대 입력 시 살짝 이동 속도
@export var attack_move_accel: float = 900.0             # 그 살짝 이동의 가감속

@export_group("타격감")
@export var hitstop_time: float = 0.01          # 적중 시 화면 정지 시간(실시간 초)
@export var hitstop_time_finisher: float = 0.01 # 마지막 타 적중 시 더 길게
@export var knockback_force: float = 280.0      # 적을 밀어내는 힘
@export var attack_damage: Array[int] = [0, 1, 1, 1]  # 콤보별 데미지(index = 콤보 번호)
@export var hit_shake: float = 0.18             # 적중 시 카메라 흔들림 양(0~1)
@export var hit_shake_finisher: float = 0.28    # 마지막 타 흔들림 양
@export var recoil_force: float = 70.0          # 적중 순간 공격자가 뒤로 밀리는 힘(리코일)
@export var slowmo_scale: float = 0.1           # 피니셔 슬로모 배속(0~1, 작을수록 느림)
@export var slowmo_time: float = 0.0            # 슬로모 지속 시간(0이면 슬로모 끔)

@export_group("공격 판정")
# 콤보별로 공격 판정이 켜지는 애니메이션 프레임 (index = 콤보 번호, 0번은 미사용)
# 참고: Godot 프레임은 0부터 시작합니다. 의도와 한 칸 어긋나면 이 값을 조절하세요.
@export var hit_active_frame: Array[int] = [0, 4, 2, 2]
# 몬스터가 속한 콜리전 레이어 번호 (이 레이어에 있는 대상만 공격에 맞음)
@export var enemy_layer_bit: int = 3

@export_group("공격 이펙트")
# 콤보별 슬래시 이펙트 씬 (index = 콤보 번호, 0번은 미사용)
@export var slash_scenes: Array[PackedScene] = [
	null,
	preload("res://scenes/effect/slash/normal_slash_1.tscn"),
	preload("res://scenes/effect/slash/normal_slash_2.tscn"),
	preload("res://scenes/effect/slash/normal_slash_3.tscn"),
]
@export var slash_offset: Vector2 = Vector2(30, -8)  # 플레이어 기준 이펙트 생성 위치
# 콤보별 슬래시 이펙트가 나오는 프레임 (index = 콤보 번호, 0번 미사용). 1타=4, 2타=3
@export var slash_spawn_frame: Array[int] = [0, 4, 3, 3]
# 적/더미가 데미지를 받을 때 생성되는 타격 이펙트
@export var hit_effect_scene: PackedScene = preload("res://scenes/effect/hit/hit.tscn")

@export_group("대기(Idle) 전환")
@export var idle2_to_idle3_time: float = 60.0    # idle2 → idle3 (1분 무입력)
@export var idle3_to_idle1_time: float = 300.0   # idle3 → idle1 (추가 5분 무입력)

# 콤보 최대 타수(공격 애니메이션 attack1~attack3 개수와 맞춰야 함)
const MAX_COMBO := 3

# ══════════════════════════════════════════════════════════════
#  상태 머신 (FSM)
# ══════════════════════════════════════════════════════════════
enum State { IDLE, WALK, RUN, JUMP, FALL, ATTACK }
var state: State = State.IDLE

var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")

# 공격/콤보 관리
var attack_combo: int = 0
var combo_requested: bool = false
var _swing_time: float = 0.0   # 현재 스윙 시작 후 경과 시간(돌진/제어 구간 판정용)
var facing: int = 1            # 1 = 오른쪽, -1 = 왼쪽
var _already_hit: Array = []   # 한 스윙에서 이미 때린 대상 (중복 타격 방지)
var _in_hitstop: bool = false  # 히트스톱 중복 방지
var _hit_active: bool = false  # 이번 스윙에서 공격 판정이 이미 켜졌는지
var _slash_spawned: bool = false   # 이번 스윙에서 슬래시 이펙트를 이미 생성했는지
var _current_slash: Node = null    # 현재 떠 있는 슬래시 이펙트(다음 타에서 삭제용)

# 대기(idle) 상태 관리
var _idle_stage: int = 1       # 1 / 2 / 3
var _idle_timer: float = 0.0   # 현재 idle 단계 경과 시간
var _has_acted: bool = false   # 한 번이라도 행동/피격했는지 (idle1 vs idle2 구분)

var _base_scale: Vector2 = Vector2.ONE  # 스프라이트 원래 크기 (스쿼시 복귀 기준)

@onready var animated_sprite: AnimatedSprite2D = $animationsprite2D

# 플레이어 하위에 만들어 둔 공격 판정 모양(CollisionShape2D). 평상시엔 판정 OFF.
# 직속 자식이 아니면 아래 경로를 실제 위치에 맞게 바꾸세요.
@onready var attack_left: CollisionShape2D = get_node_or_null("attack_left")
@onready var attack_right: CollisionShape2D = get_node_or_null("attack_right")


# ══════════════════════════════════════════════════════════════
#  준비
# ══════════════════════════════════════════════════════════════
func _ready() -> void:
	add_to_group("player")   # 카메라가 자동으로 찾을 수 있도록 그룹에 등록
	_setup_input_map()
	_setup_attack_shapes()

	if animated_sprite:
		_base_scale = animated_sprite.scale
		animated_sprite.animation_finished.connect(_on_animation_finished)
		animated_sprite.frame_changed.connect(_on_frame_changed)
		_enter_idle()   # 시작은 idle1


func _setup_input_map() -> void:
	# 입력 맵을 코드로 등록 (에디터에서 따로 설정 안 해도 작동)
	if not InputMap.has_action("move_left"):
		InputMap.add_action("move_left")
		var ev_a := InputEventKey.new()
		ev_a.physical_keycode = KEY_A
		InputMap.action_add_event("move_left", ev_a)

	if not InputMap.has_action("move_right"):
		InputMap.add_action("move_right")
		var ev_d := InputEventKey.new()
		ev_d.physical_keycode = KEY_D
		InputMap.action_add_event("move_right", ev_d)

	if not InputMap.has_action("jump"):
		InputMap.add_action("jump")
		var ev_space := InputEventKey.new()
		ev_space.physical_keycode = KEY_SPACE
		InputMap.action_add_event("jump", ev_space)

	if not InputMap.has_action("run"):
		InputMap.add_action("run")
		var ev_shift := InputEventKey.new()
		ev_shift.physical_keycode = KEY_SHIFT
		InputMap.action_add_event("run", ev_shift)

	if not InputMap.has_action("attack"):
		InputMap.add_action("attack")
		var ev_mouse := InputEventMouseButton.new()
		ev_mouse.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("attack", ev_mouse)


func _setup_attack_shapes() -> void:
	# CollisionShape2D는 플레이어 바디의 일부이므로, 켜두면 플레이어 이동 충돌에
	# 끼어들 수 있습니다. 그래서 물리적으로는 항상 disabled로 두고(이동에 영향 X),
	# 공격이 켜진 동안에만 그 '모양'으로 직접 공간을 조회해 몬스터를 찾습니다.
	for shape in [attack_left, attack_right]:
		if shape:
			shape.disabled = true
	_deactivate_hits()


# ══════════════════════════════════════════════════════════════
#  메인 루프
# ══════════════════════════════════════════════════════════════
func _physics_process(delta: float) -> void:
	# 1) 중력 (오일러 적분, 내려올 때 더 빠르게)
	_apply_gravity(delta)

	# 2) 현재 상태별 처리
	match state:
		State.IDLE:   _process_idle(delta)
		State.WALK:   _process_ground_move(delta)
		State.RUN:    _process_ground_move(delta)
		State.JUMP:   _process_jump(delta)
		State.FALL:   _process_fall(delta)
		State.ATTACK: _process_attack(delta)

	# 3) 물리 이동
	var was_on_floor := is_on_floor()
	move_and_slide()

	# 4) 착지 순간 감지 → 착지 스쿼시(묵직함)
	if is_on_floor() and not was_on_floor:
		_on_landed()

	# 5) 공격 판정이 켜져 있으면, 현재 모양으로 겹친 몬스터를 찾아 타격
	if _hit_active:
		_check_hit_overlap()


# ══════════════════════════════════════════════════════════════
#  상태 전환
# ══════════════════════════════════════════════════════════════
func _change_state(new_state: State) -> void:
	if state == new_state:
		return
	# 가만히 있는 상태(IDLE/FALL) 외의 '행동'을 하면 표시 → 다음 idle은 idle2
	if new_state == State.WALK or new_state == State.RUN \
			or new_state == State.JUMP or new_state == State.ATTACK:
		_has_acted = true
	state = new_state
	match state:
		State.IDLE: _enter_idle()
		State.WALK: animated_sprite.play("walk")
		State.RUN:  animated_sprite.play("run")
		State.JUMP: animated_sprite.play("jump")
		State.FALL: animated_sprite.play("fall")
		State.ATTACK: _enter_attack()


# ── 공통 입력 헬퍼 ──
func _get_move_dir() -> float:
	return Input.get_axis("move_left", "move_right")


func _get_attack_dir() -> int:
	# 마우스가 캐릭터보다 오른쪽이면 1(오른쪽), 왼쪽이면 -1(왼쪽)
	return 1 if get_global_mouse_position().x >= global_position.x else -1


func _update_facing(dir: float) -> void:
	if dir > 0:
		facing = 1
	elif dir < 0:
		facing = -1
	if animated_sprite:
		# 원본 규칙 유지: 오른쪽을 볼 때 flip_h = true
		animated_sprite.flip_h = facing > 0


func _try_start_attack() -> bool:
	# 누르고 있으면 공격 시작 (꾹 누르면 콤보로 이어짐)
	if Input.is_action_pressed("attack"):
		_change_state(State.ATTACK)
		return true
	return false


func _do_jump() -> void:
	velocity.y = jump_velocity
	_change_state(State.JUMP)


# Shift를 누르고 있으면 달리기, 아니면 걷기 속도
func _move_speed() -> float:
	return run_speed if Input.is_action_pressed("run") else walk_speed


# 지금 지상 이동이면 WALK인지 RUN인지 결정
func _ground_move_state() -> State:
	return State.RUN if Input.is_action_pressed("run") else State.WALK


# 오일러 적분으로 중력 적용 (delta를 짧은 구간으로 나눠 매 구간 속도에 가속도를 더함)
func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		return
	var g := gravity
	if velocity.y > 0.0:
		g *= fall_gravity_multiplier   # 내려올 때 더 빠르게 떨어짐
	var steps: int = maxi(1, gravity_substeps)
	var sub := delta / float(steps)
	for _i in steps:
		velocity.y += g * sub          # 현재 속도에 중력가속도를 더함
		if velocity.y > max_fall_speed: # 종단 속도 제한
			velocity.y = max_fall_speed
			break
	# 실제 위치(=다음 착지 위치)는 move_and_slide가 이 속도로 갱신합니다.


# ══════════════════════════════════════════════════════════════
#  각 상태 처리
# ══════════════════════════════════════════════════════════════
func _process_idle(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0, run_speed)
	_update_idle_stage(delta)
	if _try_start_attack(): return
	if Input.is_action_just_pressed("jump"):
		_do_jump(); return
	var dir := _get_move_dir()
	if dir != 0:
		_change_state(_ground_move_state()); return
	if not is_on_floor():
		_change_state(State.FALL)


# idle1 / idle2 / idle3 진입 결정
func _enter_idle() -> void:
	_idle_timer = 0.0
	if _has_acted:
		_idle_stage = 2          # 뭔가 한 뒤의 대기
		animated_sprite.play("idle2")
	else:
		_idle_stage = 1          # 시작/아무것도 안 한 상태
		animated_sprite.play("idle1")


# 가만히 있는 동안 시간에 따라 idle2 → idle3 → idle1 로 전환
func _update_idle_stage(delta: float) -> void:
	_idle_timer += delta
	if _idle_stage == 2 and _idle_timer >= idle2_to_idle3_time:
		_idle_stage = 3
		_idle_timer = 0.0
		animated_sprite.play("idle3")
	elif _idle_stage == 3 and _idle_timer >= idle3_to_idle1_time:
		_idle_stage = 1
		_idle_timer = 0.0
		_has_acted = false       # 다시 처음 상태로
		animated_sprite.play("idle1")


# 적에게 맞았을 때 외부(적)에서 호출 → 다음 대기는 idle2, idle3였다면 즉시 idle2로
func notify_damaged() -> void:
	_has_acted = true
	if state == State.IDLE:
		_enter_idle()


# WALK / RUN 공통 지상 이동 처리
func _process_ground_move(_delta: float) -> void:
	var dir := _get_move_dir()
	velocity.x = dir * _move_speed()
	_update_facing(dir)
	if _try_start_attack(): return
	if Input.is_action_just_pressed("jump"):
		_do_jump(); return
	if dir == 0:
		_change_state(State.IDLE); return
	if not is_on_floor():
		_change_state(State.FALL); return
	# 걷기 <-> 달리기 전환 (Shift 상태가 바뀌면)
	var desired := _ground_move_state()
	if state != desired:
		_change_state(desired)


func _process_jump(_delta: float) -> void:
	var dir := _get_move_dir()
	velocity.x = dir * _move_speed()
	_update_facing(dir)
	# 가변 점프: 올라가는 중에 스페이스를 떼면 상승 속도를 최소치로 깎아 낮게 점프
	if Input.is_action_just_released("jump") and velocity.y < min_jump_velocity:
		velocity.y = min_jump_velocity
	if _try_start_attack(): return   # 공중 공격 허용
	if velocity.y >= 0:
		_change_state(State.FALL)


func _process_fall(_delta: float) -> void:
	var dir := _get_move_dir()
	velocity.x = dir * _move_speed()
	_update_facing(dir)
	if _try_start_attack(): return
	if is_on_floor():
		if dir != 0:
			_change_state(_ground_move_state())
		else:
			_change_state(State.IDLE)


func _process_attack(delta: float) -> void:
	_swing_time += delta
	var dir := _get_move_dir()

	if _swing_time < lunge_time * dash_lock_ratio:
		# [돌진 구간] dash_lock_ratio 비율까지 — 입력 무시, 마찰로 미끄러지며 감속
		velocity.x = move_toward(velocity.x, 0, dash_friction * delta)
	else:
		# [제어 구간] 그 이후 — 공격 모션은 그대로 유지
		# 입력이 공격 방향과 '같으면' 돌진값만(추가 이동 X), '반대면' 살짝 보정 이동
		var input_same := (dir > 0 and facing > 0) or (dir < 0 and facing < 0)
		if dir != 0 and not input_same:
			# 공격 방향과 반대 입력 → 아주 살짝 그쪽으로 이동
			velocity.x = move_toward(velocity.x, dir * attack_move_speed, attack_move_accel * delta)
		else:
			# 입력이 없거나 공격 방향과 같으면 → 돌진값만 (마찰로 감속)
			velocity.x = move_toward(velocity.x, 0, dash_friction * delta)

	# 다음 콤보 예약(입력 버퍼링)
	if Input.is_action_just_pressed("attack") and attack_combo < MAX_COMBO:
		combo_requested = true


# ══════════════════════════════════════════════════════════════
#  공격 / 콤보
# ══════════════════════════════════════════════════════════════
func _enter_attack() -> void:
	attack_combo = 1
	combo_requested = false
	_start_swing(attack_combo)


func _start_swing(combo: int) -> void:
	_swing_time = 0.0
	_hit_active = false
	_slash_spawned = false
	_already_hit.clear()
	_deactivate_hits()    # 새 타 시작 시 판정을 끄고 시작 (지정 프레임 도달 시 켜짐)
	animated_sprite.play("attack" + str(combo))
	# 공격 방향은 마우스 위치(좌/우)로 결정 — 그쪽을 바라보며 치고 나감
	_update_facing(_get_attack_dir())
	_apply_lunge(combo)   # 돌진
	_punch_scale()        # 스쿼시 & 스트레치


func _apply_lunge(combo: int) -> void:
	var idx: int = clampi(combo, 0, lunge_speed.size() - 1)
	velocity.x = facing * lunge_speed[idx]


# 콤보 번호에 맞는 슬래시 이펙트를 바라보는 방향대로 생성
func _spawn_slash(combo: int) -> void:
	if combo < 0 or combo >= slash_scenes.size():
		return
	var scene: PackedScene = slash_scenes[combo]
	if scene == null:
		return
	# 이전 타의 이펙트가 아직 떠 있으면 삭제
	_clear_slash()
	var fx := scene.instantiate()
	add_child(fx)
	_current_slash = fx
	if fx is Node2D:
		var n: Node2D = fx
		n.position = Vector2(slash_offset.x * facing, slash_offset.y)
		n.scale.x = absf(n.scale.x) * float(facing)  # 방향에 따라 좌우 반전


# 현재 떠 있는 슬래시 이펙트를 삭제
func _clear_slash() -> void:
	if _current_slash != null and is_instance_valid(_current_slash):
		_current_slash.queue_free()
	_current_slash = null


func _on_animation_finished() -> void:
	if state != State.ATTACK:
		return
	var anim := str(animated_sprite.animation)
	if not anim.begins_with("attack"):
		return

	# 이 타의 공격 애니메이션이 끝났으니 해당 슬래시 이펙트 삭제
	_clear_slash()

	# 예약된 콤보가 있거나 마우스를 꾹 누르고 있으면 다음 타로
	var keep_attacking := combo_requested or Input.is_action_pressed("attack")
	if keep_attacking and attack_combo < MAX_COMBO:
		attack_combo += 1
		combo_requested = false
		_start_swing(attack_combo)
	else:
		_exit_attack()


func _exit_attack() -> void:
	attack_combo = 0
	combo_requested = false
	_deactivate_hits()            # 공격 종료 → 판정 끄기
	# 상황에 맞는 다음 상태로
	if not is_on_floor():
		_change_state(State.FALL)
	elif _get_move_dir() != 0:
		_change_state(_ground_move_state())
	else:
		_change_state(State.IDLE)


# ══════════════════════════════════════════════════════════════
#  타격감 (게임필)
# ══════════════════════════════════════════════════════════════
func _punch_scale() -> void:
	# 휘두를 때 살짝 늘어났다가 빠르게 복귀 (가벼운 느낌)
	if not animated_sprite: return
	animated_sprite.scale = _base_scale * Vector2(1.12, 0.9)
	var t := create_tween()
	t.tween_property(animated_sprite, "scale", _base_scale, 0.09)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_landed() -> void:
	# 착지 시 찌부러졌다가 복귀 → 묵직한 느낌
	if not animated_sprite: return
	animated_sprite.scale = _base_scale * Vector2(1.3, 0.7)
	var t := create_tween()
	t.tween_property(animated_sprite, "scale", _base_scale, 0.15)\
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _flash() -> void:
	# 적중 순간 번쩍
	if not animated_sprite: return
	animated_sprite.modulate = Color(2, 2, 2)
	var t := create_tween()
	t.tween_property(animated_sprite, "modulate", Color.WHITE, 0.12)


func apply_hit_pause(finisher: bool) -> void:
	# 짧은 완전 정지 → (피니셔면) 슬로모 → 서서히 정상 속도로 복귀
	if _in_hitstop:
		return
	_in_hitstop = true

	# 1) 짧은 정지 (실시간 타이머로 풀어줌)
	var freeze := hitstop_time_finisher if finisher else hitstop_time
	Engine.time_scale = 0.0
	await get_tree().create_timer(freeze, true, false, true).timeout

	# 2) 피니셔면 슬로모 후 부드럽게 복귀 (slowmo_time 0이면 생략 → 가볍게)
	if finisher and slowmo_time > 0.0:
		Engine.time_scale = slowmo_scale
		await get_tree().create_timer(slowmo_time, true, false, true).timeout
		var steps := 6
		for i in steps:
			Engine.time_scale = lerpf(slowmo_scale, 1.0, float(i + 1) / float(steps))
			await get_tree().create_timer(0.02, true, false, true).timeout

	Engine.time_scale = 1.0
	_in_hitstop = false


# ══════════════════════════════════════════════════════════════
#  공격 판정 (attack_left / attack_right)
# ══════════════════════════════════════════════════════════════
func _on_frame_changed() -> void:
	if state != State.ATTACK:
		return
	var f := animated_sprite.frame

	# 슬래시 이펙트: 콤보별 지정 프레임부터 (한 스윙에 한 번)
	if not _slash_spawned:
		var sf: int = slash_spawn_frame[clampi(attack_combo, 0, slash_spawn_frame.size() - 1)]
		if f >= sf:
			_slash_spawned = true
			_spawn_slash(attack_combo)

	# 공격 판정: 콤보별 지정 프레임에 도달하면 켠다 (한 스윙에 한 번만)
	if not _hit_active:
		var need: int = hit_active_frame[clampi(attack_combo, 0, hit_active_frame.size() - 1)]
		if f >= need:
			_activate_hit()


func _activate_hit() -> void:
	_hit_active = true   # 이때부터 _physics_process가 매 프레임 겹침을 조회


func _deactivate_hits() -> void:
	_hit_active = false


# 활성 중인 쪽 CollisionShape2D의 '모양'으로 물리 공간을 조회해 겹친 몬스터를 찾는다
func _check_hit_overlap() -> void:
	var shape_node: CollisionShape2D = attack_right if facing > 0 else attack_left
	if shape_node == null or shape_node.shape == null:
		return

	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = shape_node.shape
	params.transform = shape_node.global_transform
	params.collision_mask = 1 << (enemy_layer_bit - 1)  # 몬스터 레이어만
	params.collide_with_bodies = true
	params.collide_with_areas = true
	params.exclude = [self.get_rid()]                   # 자기 자신 제외

	var space := get_world_2d().direct_space_state
	var results := space.intersect_shape(params, 16)
	for r in results:
		_try_hit(r.get("collider"))


func _try_hit(target) -> void:
	if target == null or target == self:
		return
	if target in _already_hit:
		return
	_already_hit.append(target)
	_hit_landed(target)


func _hit_landed(target) -> void:
	# 1) 데미지 전달 (적에 take_damage가 있으면)
	if target.has_method("take_damage"):
		var idx: int = clampi(attack_combo, 0, attack_damage.size() - 1)
		target.take_damage(attack_damage[idx])
		_spawn_hit_effect(target)   # 데미지 들어간 위치에 타격 이펙트

	# 2) 넉백 (적에 apply_knockback이 있으면)
	if target.has_method("apply_knockback"):
		var knock_dir := Vector2(facing, -0.25).normalized()
		target.apply_knockback(knock_dir * knockback_force)

	# 3) 타격 연출
	var finisher := attack_combo >= MAX_COMBO
	velocity.x = -facing * recoil_force   # 공격자 리코일: 진행 반대로 살짝 되튕김
	_flash()                            # 캐릭터 스프라이트 번쩍
	_trigger_screen_feedback(finisher)  # 흔들림 + 펀치 줌 + 화면 번쩍 + 크로매틱/집중선
	apply_hit_pause(finisher)           # 히트스톱 (+ 피니셔 슬로모)


# 적이 맞은 위치에 타격 이펙트 생성
func _spawn_hit_effect(target) -> void:
	if hit_effect_scene == null:
		return
	var fx := hit_effect_scene.instantiate()
	# 공격 방향을 파티클에 전달 (씬에 attack_dir 속성이 있으면) — add_child 전에 설정
	if "attack_dir" in fx:
		fx.attack_dir = Vector2(facing, 0)
	# 시각용 랜덤 회전도 add_child 전에 (파티클 방향이 부모 회전을 반영해 계산되도록)
	if fx is Node2D:
		fx.rotation = randf_range(0.0, TAU)
	# 적이 사라져도 남도록 현재 씬에 붙임
	var host := get_tree().current_scene
	if host == null:
		host = get_parent()
	host.add_child(fx)
	if fx is Node2D and target is Node2D:
		fx.global_position = target.global_position


# 카메라 흔들림 + 화면 전체 번쩍임 트리거
func _trigger_screen_feedback(finisher: bool) -> void:
	var cam := get_viewport().get_camera_2d()
	if cam:
		if cam.has_method("add_shake"):
			cam.add_shake(hit_shake_finisher if finisher else hit_shake, Vector2(facing, 0.0))
		if cam.has_method("punch_zoom"):
			cam.punch_zoom(finisher)
	var fx := get_tree().get_first_node_in_group("screen_effects")
	if fx and fx.has_method("hit_feedback"):
		fx.hit_feedback()
