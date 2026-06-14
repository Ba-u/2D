extends Node2D

func _ready():
	# 애니메이션 노드를 변수에 담아둡니다.
	var anim = get_node("sprite")
	
	# "fade_out" 애니메이션을 재생합니다.
	anim.play("fade_out")
	
	# Godot 4의 새로운 대기(Wait) 문법입니다. (yield 대신 await 사용)
	# 애니메이션 노드의 'animation_finished' 시그널이 울릴 때까지 여기서 기다립니다.
	await anim.animation_finished
	
	# 애니메이션이 완전히 끝나면 이 노드를 삭제합니다.
	queue_free()
