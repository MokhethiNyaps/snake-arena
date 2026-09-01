extends RefCounted
## §10 — StatModifierStack semantics: stackable-but-capped modifiers,
## refresh-instead-of-stack, expiry, removal.

const StatModifierStackClass = preload("res://scripts/snake/stat_modifier_stack.gd")


func test_add_and_read_multiplier() -> bool:
	var stack: StatModifierStack = StatModifierStackClass.new()
	stack.add(&"surge", &"speed", 1.35, 6.0)
	return is_equal_approx(stack.get_multiplier(&"speed"), 1.35)


func test_identical_type_refreshes_not_stacks() -> bool:
	var stack: StatModifierStack = StatModifierStackClass.new()
	stack.add(&"surge", &"speed", 1.35, 6.0)
	stack.add(&"surge", &"speed", 1.35, 6.0)  # refresh
	return is_equal_approx(stack.get_multiplier(&"speed"), 1.35) \
		and stack.active_count() == 1


func test_different_types_stack_multiply() -> bool:
	var stack: StatModifierStack = StatModifierStackClass.new()
	stack.add(&"surge", &"speed", 1.35, 6.0)
	stack.add(&"other", &"speed", 1.5, 6.0)
	return is_equal_approx(stack.get_multiplier(&"speed"), 1.35 * 1.5) \
		and stack.active_count() == 2


func test_stat_isolation() -> bool:
	var stack: StatModifierStack = StatModifierStackClass.new()
	stack.add(&"surge", &"speed", 1.35, 6.0)
	return is_equal_approx(stack.get_multiplier(&"turn"), 1.0)


func test_removal() -> bool:
	var stack: StatModifierStack = StatModifierStackClass.new()
	stack.add(&"surge", &"speed", 1.35, 6.0)
	stack.remove(&"surge", &"speed")
	return is_equal_approx(stack.get_multiplier(&"speed"), 1.0) \
		and stack.active_count() == 0


func test_remove_all() -> bool:
	var stack: StatModifierStack = StatModifierStackClass.new()
	stack.add(&"surge", &"speed", 1.35, 6.0)
	stack.add(&"surge", &"turn", 1.15, 6.0)
	stack.add(&"chill", &"speed", 0.7, 7.0)
	stack.remove_all(&"surge")
	return stack.active_count() == 1 \
		and is_equal_approx(stack.get_multiplier(&"speed"), 0.7) \
		and is_equal_approx(stack.get_multiplier(&"turn"), 1.0)


func test_expiry_cleans_lazily() -> bool:
	var stack: StatModifierStack = StatModifierStackClass.new()
	stack.add(&"surge", &"speed", 1.35, 0.0005)  # expires ~0.5 ms later
	OS.delay_msec(10)
	return is_equal_approx(stack.get_multiplier(&"speed"), 1.0) \
		and stack.active_count() == 0
