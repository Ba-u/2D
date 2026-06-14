extends CanvasLayer

# ══════════════════════════════════════════════════════════════
#  화면 효과: 전체 번쩍임(Flash) + 타격 시 비네팅(채도/명도) + 크로매틱 + 집중선(zoom)
#
#  사용법:
#  1) 씬에 CanvasLayer 노드를 추가하고 이 스크립트를 붙입니다.
#     (플레이어와 형제 노드로, 루트 아래 아무 데나 두면 됩니다)
#  2) 번쩍임/비네팅용 ColorRect 두 개는 코드에서 자동 생성됩니다.
#  3) 플레이어가 적중 시 flash()를 호출하도록 그룹 "screen_effects"에 자동 등록됩니다.
#
#  ※ 만약 비네팅이 까맣게만 보이면, 일부 환경에선 화면 텍스처 복사가 필요합니다.
#    이 경우 같은 CanvasLayer 안에 BackBufferCopy 노드(Copy Mode = Viewport)를
#    추가하면 해결됩니다.
# ══════════════════════════════════════════════════════════════
@export_group("번쩍임(Flash)")
@export var flash_color: Color = Color(1, 1, 1)  # 번쩍임 색
@export_range(0.0, 1.0) var flash_strength: float = 0.5  # 시작 알파(번쩍임 세기)
@export var flash_duration: float = 0.12                 # 사라지는 시간

@export_group("비네팅 (타격 시에만)")
@export var vignette_enabled: bool = true
@export var vignette_peak: float = 1.0                        # 타격 시 비네팅 최대 세기
@export var vignette_fade: float = 0.25                       # 비네팅이 사라지는 시간
@export_range(0.0, 1.5) var vignette_edge_start: float = 0.55  # 중심에서 이 거리부터 효과 시작
@export_range(0.0, 1.5) var vignette_edge_end: float = 1.0     # 이 거리에서 효과 최대
@export_range(0.0, 1.0) var vignette_desaturation: float = 0.7 # 가장자리 채도 감소량(최대 세기 기준)
@export_range(0.0, 1.0) var vignette_darkness: float = 0.45    # 가장자리 명도 감소량(최대 세기 기준)

@export_group("크로매틱 (타격 시)")
@export var chroma_enabled: bool = true
@export var chroma_peak: float = 1.0     # 타격 시 크로매틱 최대 세기
@export var chroma_fade: float = 0.10    # 사라지는 시간(아주 짧게)
@export var chroma_amount: float = 0.005 # 최대 채널 분리량

@export_group("집중선 (타격 시)")
@export var lines_enabled: bool = true
@export var lines_peak: float = 1.0      # 타격 시 집중선 최대 세기
@export var lines_fade: float = 0.14     # 사라지는 시간
@export var lines_density: float = 60.0  # 선 밀도
@export_range(0.0, 1.5) var lines_start: float = 0.45  # 중심에서 이 거리부터 선이 보임

var _flash_rect: ColorRect
var _vignette_rect: ColorRect

# 화면을 샘플링해 비네팅(채도/명도) + 크로매틱 + 집중선을 한 번에 처리하는 셰이더
const HIT_POST_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
// 비네팅
uniform float edge_start = 0.55;
uniform float edge_end = 1.0;
uniform float desaturation = 0.7;
uniform float darkness = 0.45;
uniform float vignette_strength = 0.0;
// 크로매틱
uniform float chroma_amount = 0.005;
uniform float chroma_strength = 0.0;
// 집중선(zoom-in 라인)
uniform float lines_density = 60.0;
uniform float lines_start = 0.45;
uniform float lines_strength = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 dir = uv - vec2(0.5);
	float dist = length(dir) * 2.0;            // 모서리에서 약 1.41
	vec2 ndir = normalize(dir + vec2(0.0001));

	// 1) 크로매틱: 중심에서 멀수록 R/B 채널을 분리
	vec2 off = ndir * chroma_amount * chroma_strength * dist;
	vec3 col;
	col.r = texture(screen_tex, uv + off).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - off).b;

	// 2) 비네팅(채도/명도)
	float vt = smoothstep(edge_start, edge_end, dist) * vignette_strength;
	float gray = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(gray), desaturation * vt);  // 채도 낮춤
	col *= (1.0 - darkness * vt);                    // 명도 낮춤

	// 3) 집중선: 각도 기반 줄무늬를 바깥쪽에 어둡게 → zoom-in 라인 느낌
	float ang = atan(dir.y, dir.x);
	float stripe = step(0.5, fract(sin(ang * lines_density) * 43758.5453));
	float lt = smoothstep(lines_start, 1.2, dist) * lines_strength;
	col *= mix(1.0, stripe, lt);

	COLOR = vec4(col, 1.0);
}
"""


func _ready() -> void:
	add_to_group("screen_effects")
	layer = 100   # 게임 화면 위에 그려지도록 높은 레이어

	# 1) 비네팅 (먼저 추가 → 아래에 깔리고 화면을 샘플링)
	_vignette_rect = ColorRect.new()
	_setup_fullrect(_vignette_rect)
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = HIT_POST_SHADER
	mat.shader = sh
	_vignette_rect.material = mat
	add_child(_vignette_rect)
	_apply_post_params()

	# 2) 번쩍임 (나중에 추가 → 맨 위)
	_flash_rect = ColorRect.new()
	_setup_fullrect(_flash_rect)
	_flash_rect.color = Color(flash_color.r, flash_color.g, flash_color.b, 0.0)
	add_child(_flash_rect)


func _setup_fullrect(rect: ColorRect) -> void:
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)  # 화면 전체 채움
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE                # 클릭 통과


func _apply_post_params() -> void:
	if _vignette_rect == null:
		return
	# 셋 중 하나라도 켜져 있으면 후처리 렉트를 켠다 (평소엔 패스스루)
	_vignette_rect.visible = vignette_enabled or chroma_enabled or lines_enabled
	var mat := _vignette_rect.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("edge_start", vignette_edge_start)
		mat.set_shader_parameter("edge_end", vignette_edge_end)
		mat.set_shader_parameter("desaturation", vignette_desaturation)
		mat.set_shader_parameter("darkness", vignette_darkness)
		mat.set_shader_parameter("chroma_amount", chroma_amount)
		mat.set_shader_parameter("lines_density", lines_density)
		mat.set_shader_parameter("lines_start", lines_start)
		# 세기 값들은 평소 0 (효과 없음)
		mat.set_shader_parameter("vignette_strength", 0.0)
		mat.set_shader_parameter("chroma_strength", 0.0)
		mat.set_shader_parameter("lines_strength", 0.0)


func _get_mat() -> ShaderMaterial:
	if _vignette_rect == null:
		return null
	return _vignette_rect.material as ShaderMaterial


# ══════════════════════════════════════════════════════════════
#  플레이어가 호출: 화면 전체 번쩍임
#  인자를 비우면 인스펙터 기본값 사용
# ══════════════════════════════════════════════════════════════
func flash(strength: float = -1.0, duration: float = -1.0) -> void:
	if _flash_rect == null:
		return
	var a: float = strength if strength >= 0.0 else flash_strength
	var dur: float = duration if duration >= 0.0 else flash_duration
	_flash_rect.color = Color(flash_color.r, flash_color.g, flash_color.b, a)
	var t := create_tween()
	t.tween_property(_flash_rect, "color:a", 0.0, dur)


# 타격 시 비네팅을 잠깐 켰다가 사라지게 (가장자리 채도/명도 down)
func pulse_vignette(peak: float = -1.0, fade: float = -1.0) -> void:
	if not vignette_enabled:
		return
	_pulse_param("vignette_strength", peak if peak >= 0.0 else vignette_peak, fade if fade >= 0.0 else vignette_fade)


# 타격 시 아주 짧게 크로매틱 분리
func pulse_chroma(peak: float = -1.0, fade: float = -1.0) -> void:
	if not chroma_enabled:
		return
	_pulse_param("chroma_strength", peak if peak >= 0.0 else chroma_peak, fade if fade >= 0.0 else chroma_fade)


# 타격 시 집중선(zoom-in 라인) 펄스
func pulse_lines(peak: float = -1.0, fade: float = -1.0) -> void:
	if not lines_enabled:
		return
	_pulse_param("lines_strength", peak if peak >= 0.0 else lines_peak, fade if fade >= 0.0 else lines_fade)


# 셰이더 파라미터를 peak로 올렸다가 fade 동안 0으로 트윈하는 공통 헬퍼
func _pulse_param(param: String, peak: float, fade: float) -> void:
	var mat := _get_mat()
	if mat == null:
		return
	mat.set_shader_parameter(param, peak)
	var t := create_tween()
	t.tween_property(mat, "shader_parameter/" + param, 0.0, fade)


# 플레이어가 적중 시 호출: 번쩍임 + 비네팅 + 크로매틱 + 집중선을 함께
func hit_feedback() -> void:
	flash()
	pulse_vignette()
	pulse_chroma()
	pulse_lines()
