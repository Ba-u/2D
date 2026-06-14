extends CanvasLayer

# ══════════════════════════════════════════════════════════════
#  화면 효과(타격 시): 비네팅(채도/명도) + 크로매틱 + 집중선
#
#  사용법:
#  1) 씬에 CanvasLayer 노드를 추가하고 이 스크립트를 붙입니다.
#  2) 후처리용 ColorRect는 코드에서 자동 생성됩니다.
#  3) 플레이어가 적중 시 hit_feedback()을 호출하도록 그룹 "screen_effects"에 등록됩니다.
#
#  ※ 비네팅/크로매틱이 까맣게만 보이면(화면 텍스처 복사 미지원 환경),
#    같은 CanvasLayer 안에 BackBufferCopy 노드(Copy Mode = Viewport)를 추가하세요.
# ══════════════════════════════════════════════════════════════
@export_group("비네팅 (타격 시)")
@export var vignette_enabled: bool = true
@export var vignette_peak: float = 1.0
@export var vignette_fade: float = 0.14                        # 짧게 사라짐(가볍게)
@export_range(0.0, 1.5) var vignette_edge_start: float = 0.45  # 가장자리에만
@export_range(0.0, 1.5) var vignette_edge_end: float = 0.95
@export_range(0.0, 1.0) var vignette_desaturation: float = 0.35 # 채도 감소량(약하게)
@export_range(0.0, 1.0) var vignette_darkness: float = 0.22     # 명도 감소량(약하게)

@export_group("크로매틱 (타격 시)")
@export var chroma_enabled: bool = true
@export var chroma_peak: float = 1.0
@export var chroma_fade: float = 0.08    # 아주 짧게
@export var chroma_amount: float = 0.006 # 채널 분리량(약하게)

@export_group("집중선 (타격 시)")
@export var lines_enabled: bool = true
@export var lines_peak: float = 1.0
@export var lines_fade: float = 0.08     # 짧게
@export var lines_density: float = 20.0  # 선 개수(클수록 촘촘)
@export_range(0.0, 0.5) var lines_width: float = 0.06  # 선 굵기
@export_range(0.0, 1.5) var lines_start: float = 0.55  # 중심에서 이 거리부터 선이 보임

var _post_rect: ColorRect

# 화면을 샘플링해 비네팅 + 크로매틱 + 집중선을 한 번에 처리하는 셰이더
const HIT_POST_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
// 비네팅
uniform float edge_start = 0.2;
uniform float edge_end = 0.95;
uniform float desaturation = 0.85;
uniform float darkness = 0.55;
uniform float vignette_strength = 0.0;
// 크로매틱
uniform float chroma_amount = 0.012;
uniform float chroma_strength = 0.0;
// 집중선
uniform float lines_density = 20.0;
uniform float lines_width = 0.06;
uniform float lines_start = 0.55;
uniform float lines_strength = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 dir = uv - vec2(0.5);
	float dist = length(dir) * 2.0;            // 모서리에서 약 1.41
	vec2 ndir = normalize(dir + vec2(0.0001));

	// 1) 크로매틱: 중심에서도 약간, 가장자리로 갈수록 강하게 R/B 분리
	vec2 off = ndir * chroma_amount * chroma_strength * (dist + 0.25);
	vec3 col;
	col.r = texture(screen_tex, uv + off).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - off).b;

	// 2) 비네팅(채도/명도)
	float vt = clamp(smoothstep(edge_start, edge_end, dist), 0.0, 1.0) * vignette_strength;
	float gray = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(gray), desaturation * vt);  // 채도 낮춤
	col *= (1.0 - darkness * vt);                    // 명도 낮춤

	// 3) 집중선: 각도 기준 방사형 선 (sin 기반 → 노이즈 없이 매끈)
	float ang = atan(dir.y, dir.x);
	float bands = abs(sin(ang * lines_density));
	float w = lines_width * (0.6 + 0.4 * sin(ang * 9.0 + 1.3));  // 굵기 살짝 불규칙
	float line = smoothstep(w, w + 0.12, bands);                 // 0=어두운 선, 1=사이 공간
	float lt = smoothstep(lines_start, 1.2, dist) * lines_strength;
	col *= mix(1.0, line, lt);

	COLOR = vec4(col, 1.0);
}
"""


func _ready() -> void:
	add_to_group("screen_effects")
	layer = 100   # 게임 화면 위에 그려지도록 높은 레이어

	_post_rect = ColorRect.new()
	_post_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)  # 화면 전체
	_post_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE                # 클릭 통과
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = HIT_POST_SHADER
	mat.shader = sh
	_post_rect.material = mat
	add_child(_post_rect)
	_apply_post_params()


func _apply_post_params() -> void:
	if _post_rect == null:
		return
	# 셋 중 하나라도 켜져 있으면 후처리 렉트를 켠다 (평소엔 패스스루)
	_post_rect.visible = vignette_enabled or chroma_enabled or lines_enabled
	var mat := _post_rect.material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("edge_start", vignette_edge_start)
	mat.set_shader_parameter("edge_end", vignette_edge_end)
	mat.set_shader_parameter("desaturation", vignette_desaturation)
	mat.set_shader_parameter("darkness", vignette_darkness)
	mat.set_shader_parameter("chroma_amount", chroma_amount)
	mat.set_shader_parameter("lines_density", lines_density)
	mat.set_shader_parameter("lines_width", lines_width)
	mat.set_shader_parameter("lines_start", lines_start)
	# 세기 값들은 평소 0 (효과 없음)
	mat.set_shader_parameter("vignette_strength", 0.0)
	mat.set_shader_parameter("chroma_strength", 0.0)
	mat.set_shader_parameter("lines_strength", 0.0)


# 셰이더 파라미터를 peak로 올렸다가 fade 동안 0으로.
# tween_method + ignore_time_scale → 히트스톱/슬로모 중에도 실시간으로 정확히 재생
func _pulse_param(param: String, peak: float, fade: float) -> void:
	if _post_rect == null:
		return
	var mat := _post_rect.material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter(param, peak)
	var t := create_tween()
	t.set_ignore_time_scale(true)
	t.tween_method(
		func(v: float): mat.set_shader_parameter(param, v),
		peak, 0.0, fade)


func pulse_vignette(peak: float = -1.0, fade: float = -1.0) -> void:
	if not vignette_enabled:
		return
	_pulse_param("vignette_strength", peak if peak >= 0.0 else vignette_peak, fade if fade >= 0.0 else vignette_fade)


func pulse_chroma(peak: float = -1.0, fade: float = -1.0) -> void:
	if not chroma_enabled:
		return
	_pulse_param("chroma_strength", peak if peak >= 0.0 else chroma_peak, fade if fade >= 0.0 else chroma_fade)


func pulse_lines(peak: float = -1.0, fade: float = -1.0) -> void:
	if not lines_enabled:
		return
	_pulse_param("lines_strength", peak if peak >= 0.0 else lines_peak, fade if fade >= 0.0 else lines_fade)


# 플레이어가 적중 시 호출 (화면 번쩍임은 없음)
func hit_feedback() -> void:
	pulse_vignette()
	pulse_chroma()
	pulse_lines()
