extends Node2D

# ══════════════════════════════════════════════════════════════
#  hit 이펙트: 기존 fade_out 애니메이션 + 사방으로 튀는 파티클(스파크)
#  파티클 노드는 코드에서 자동 생성되므로 씬에 따로 안 만들어도 됩니다.
#  값들은 인스펙터에서 조절할 수 있어요.
# ══════════════════════════════════════════════════════════════
@export_group("파티클")
@export var attack_dir: Vector2 = Vector2.RIGHT    # 공격 방향(플레이어가 설정) — 이 방향으로 퍼짐
@export var particle_amount: int = 12              # 파티클 개수
@export var particle_lifetime: float = 0.35        # 파티클 수명(초)
@export var particle_speed_min: float = 120.0      # 초기 속도(최소)
@export var particle_speed_max: float = 260.0      # 초기 속도(최대)
@export var particle_spread: float = 35.0          # 한쪽으로 퍼지는 각도(작을수록 직선에 가까움)
@export var particle_scale: float = 4.0            # 파티클 크기
@export var particle_damping: float = 100.0        # 감속(클수록 빨리 멈춤)
@export var particle_color: Color = Color(1.0, 0.92, 0.6)  # 색
@export var particle_texture: Texture2D            # 비우면 작은 사각형으로 그려짐


func _ready() -> void:
	# 애니메이션 노드를 변수에 담아둡니다.
	var anim = get_node("sprite")

	# 파티클을 터뜨리고 fade_out 애니메이션을 재생합니다.
	_spawn_particles()
	anim.play("fade_out")

	# 애니메이션이 끝나면 파티클까지(자식이므로) 함께 삭제됩니다.
	await anim.animation_finished
	queue_free()


# 적중 위치에서 사방으로 튀는 1회성 파티클 생성
func _spawn_particles() -> void:
	var p := CPUParticles2D.new()
	add_child(p)
	# 공격 방향(월드 기준)으로 향하게 — 부모의 랜덤 회전과 무관하도록 global_rotation 설정
	p.global_rotation = attack_dir.normalized().angle()

	p.one_shot = true            # 한 번만
	p.explosiveness = 1.0        # 동시에 터지듯
	p.amount = particle_amount
	p.lifetime = particle_lifetime

	# 공격 방향으로 한쪽 부채꼴 퍼짐
	p.direction = Vector2(1, 0)
	p.spread = particle_spread
	p.initial_velocity_min = particle_speed_min
	p.initial_velocity_max = particle_speed_max
	p.gravity = Vector2.ZERO     # 중력 없이 곧게 튀어나감
	p.damping_min = particle_damping
	p.damping_max = particle_damping  # 점점 감속하며 멈춤

	# 크기 (점점 작아지며 사라지게)
	p.scale_amount_min = particle_scale
	p.scale_amount_max = particle_scale
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = curve

	p.color = particle_color
	if particle_texture:
		p.texture = particle_texture

	p.emitting = true            # 발사!
