class_name TestSignalHost
extends Object
## Debug-only test bridge: lets headless tests observe signals emitted by
## gameplay classes without awaiting (the test runner is synchronous).
##
## Owns: a static registry (instance_id -> host) and re-emitted signal
## mirrors for the events tests care about. Zero shipping cost: emitters
## only look at this registry in debug builds (OS.is_debug_build()).
## Talks to: SnakeController (and later systems) which call
##            TestSignalHost.relay(emitter_id, signal_name, value).

## instance_id -> TestSignalHost
static var registry: Dictionary = {}

signal power_changed(power: float)
signal boosted_changed(boosting: bool)
signal died(snake: Object)


## Called by gameplay emitters right after their own signal emission.
static func relay(emitter_id: int, signal_name: StringName, value: Variant) -> void:
	if not OS.is_debug_build():
		return
	var host: Variant = registry.get(emitter_id)
	if host == null or not host is TestSignalHost:
		return
	host.emit_signal(signal_name, value)


static func register(emitter_id: int) -> TestSignalHost:
	var host: TestSignalHost = TestSignalHost.new()
	registry[emitter_id] = host
	return host


static func unregister(emitter_id: int) -> void:
	registry.erase(emitter_id)
