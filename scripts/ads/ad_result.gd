class_name AdResult
extends RefCounted
## §45.1 — Result of an ad request. Carries a code and whether the reward
## was actually earned. Must ALWAYS be produced — never leave a caller hanging.
##
## Owns: the outcome value. No logic beyond factories.

enum Code { SHOWN_COMPLETED, SHOWN_SKIPPED, NO_FILL, ERROR, TIMEOUT, BLOCKED, DISABLED }

var code: Code = Code.DISABLED
## True only when a rewarded ad was watched to completion.
var rewarded: bool = false


## Result for when the ad layer is disabled (Null provider, desktop dev).
static func disabled() -> AdResult:
	var r: AdResult = AdResult.new()
	r.code = Code.DISABLED
	r.rewarded = false
	return r


static func from_code(code: Code, rewarded: bool = false) -> AdResult:
	var r: AdResult = AdResult.new()
	r.code = code
	r.rewarded = rewarded
	return r


func _to_string() -> String:
	return "AdResult(%s, rewarded=%s)" % [Code.keys()[code], rewarded]
