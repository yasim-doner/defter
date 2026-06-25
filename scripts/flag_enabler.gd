extends Node

@export var require_mid_level_1: bool = false
@export var require_mid_level_2: bool = false
@export var require_mid_level_3: bool = false
@export var require_mid_level_4: bool = false
@export var require_mid_level_5: bool = false
@export var enable_when_true: bool = true

func _ready() -> void:
	if GameManager:
		var any_required = false
		var all_conditions_met = true
		
		if require_mid_level_1:
			any_required = true
			if not GameManager.level_flags.get("mid_level_1_done", false): all_conditions_met = false
		if require_mid_level_2:
			any_required = true
			if not GameManager.level_flags.get("mid_level_2_done", false): all_conditions_met = false
		if require_mid_level_3:
			any_required = true
			if not GameManager.level_flags.get("mid_level_3_done", false): all_conditions_met = false
		if require_mid_level_4:
			any_required = true
			if not GameManager.level_flags.get("mid_level_4_done", false): all_conditions_met = false
		if require_mid_level_5:
			any_required = true
			if not GameManager.level_flags.get("mid_level_5_done", false): all_conditions_met = false
			
		if any_required:
			var should_enable = all_conditions_met if enable_when_true else not all_conditions_met
			
			var parent = get_parent()
			if parent:
				if not should_enable:
					parent.queue_free()
