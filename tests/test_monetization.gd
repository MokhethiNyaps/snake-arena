extends RefCounted
## Phase 11 — §45 monetization wiring: WebPortal/AdMob provider degradation
## contracts (never hang, always emit show_completed), consent flow, the
## remote-config seam, and the "no AdMob types outside AdProviderAdMob" rule.


func test_webportal_degrades_without_js() -> bool:
	var wp: AdProviderWebPortal = AdProviderWebPortal.new()
	wp.initialize(null, 0)
	if wp.is_initialized() != true:
		printerr("  initialize must succeed even without JS")
		return false
	if wp.is_available(AdPlacementId.ID.INTER_RUN):
		printerr("  must be unavailable without JavaScriptBridge")
		return false
	if wp.portal_name != "":
		printerr("  portal must be undetected headless")
		return false
	# The §45.1 contract: a provider must ALWAYS resolve AND emit
	# show_completed — AdManager races that signal against its watchdog.
	var got: Array = []
	wp.show_completed.connect(func(r: AdResult) -> void: got.append(r))
	var t0: int = Time.get_ticks_msec()
	var r1: AdResult = await wp.show_rewarded(AdPlacementId.ID.REVIVE)
	var r2: AdResult = await wp.show_interstitial(AdPlacementId.ID.INTER_RUN)
	var ms: int = Time.get_ticks_msec() - t0
	if ms > 500:
		printerr("  degradation took %d ms — must be immediate, never hang" % ms)
		return false
	if r1.code != AdResult.Code.DISABLED or r2.code != AdResult.Code.DISABLED:
		printerr("  no-JS shows must resolve DISABLED")
		return false
	if got.size() != 2:
		printerr("  show_completed must emit on EVERY resolution path (got %d)" % got.size())
		return false
	return true


func test_admob_scaffold_degrades() -> bool:
	if AdProviderAdMob.plugin_present():
		printerr("  plugin cannot be present in this sandbox")
		return false
	var admob: AdProviderAdMob = AdProviderAdMob.new()
	admob.initialize(null, 0)
	if admob.is_available(AdPlacementId.ID.INTER_RUN):
		printerr("  scaffold without plugin must be unavailable")
		return false
	var r: AdResult = await admob.show_rewarded(AdPlacementId.ID.REVIVE)
	if r.code != AdResult.Code.DISABLED:
		printerr("  scaffold show must resolve DISABLED, got %s" % AdResult.Code.keys()[r.code])
		return false
	return true


func test_no_admob_types_outside_provider() -> bool:
	var allowed: Array = ["res://scripts/ads/ad_provider_admob.gd", "res://tests/test_monetization.gd"]
	var dir: DirAccess = DirAccess.open("res://scripts")
	var stack: Array = ["res://scripts"]
	var hits: Array = []
	while not stack.is_empty():
		var d: String = stack.pop_back()
		var dd: DirAccess = DirAccess.open(d)
		dd.list_dir_begin()
		var f: String = dd.get_next()
		while f != "":
			var path: String = d + "/" + f
			if dd.current_is_dir() and not f.begins_with("."):
				stack.append(path)
			elif f.ends_with(".gd"):
				# config .gd files DECLARE the ad-unit ids as data (§45.2:
				# "values in ads.tres") — the type-leak rule is about code.
				if not allowed.has(path) and not path.begins_with("res://scripts/config"):
					var src: String = FileAccess.get_file_as_string(path)
					for line in src.split("\n"):
						var code: String = line.split("#")[0].to_lower()
						# §45.2: no AdMob SDK types outside the provider. Our
						# wrapper class name is exempt (it IS the abstraction);
						# raw SDK identifiers (plugin singletons, the ad-unit
						# scheme) are the leak this catches.
						var bare: String = code.replace("adprovideradmob", "")
						if "poing" in bare or "ca-app-pub" in bare or "admob" in bare:
							hits.append("%s: %s" % [path, line.strip_edges()])
			f = dd.get_next()
		dd.list_dir_end()
	if not hits.is_empty():
		printerr("  AdMob types leaked outside the provider:\n    " + "\n    ".join(hits))
		return false
	return true


func test_consent_flow_persists() -> bool:
	DirAccess.remove_absolute("user://consent.cfg")
	ConsentManager.state = ConsentManager.ConsentState.UNKNOWN
	if not ConsentManager.needs_ui():
		printerr("  UNKNOWN must need the consent UI")
		return false
	ConsentManager.set_consent(ConsentManager.ConsentState.GRANTED, ConsentManager.CONSENT_VERSION)
	if not ConsentManager.is_granted():
		printerr("  ACCEPT did not grant")
		return false
	# Reload from disk: state + version + timestamp persisted (§45.8).
	ConsentManager.state = ConsentManager.ConsentState.UNKNOWN
	ConsentManager._try_load()
	if ConsentManager.state != ConsentManager.ConsentState.GRANTED:
		printerr("  consent did not persist to consent.cfg")
		return false
	# DECLINE blocks serving but the game stays playable.
	ConsentManager.set_consent(ConsentManager.ConsentState.DENIED, ConsentManager.CONSENT_VERSION)
	var pace: Dictionary = AdManager.can_show(AdPlacementId.ID.INTER_RUN)
	if bool(pace["allowed"]) or str(pace["reason"]) != "consent-denied":
		printerr("  DECLINE must block serving with reason consent-denied, got %s" % str(pace))
		return false
	# Restore a granted state for the rest of the suite.
	ConsentManager.set_consent(ConsentManager.ConsentState.GRANTED, ConsentManager.CONSENT_VERSION)
	return true


func test_remote_config_seam() -> bool:
	RemoteConfig.clear_overrides()
	if RemoteConfig.has_override("test/key"):
		printerr("  fresh config must have no overrides")
		return false
	if not RemoteConfig.apply_json('{"test/speed": 12.5, "test/count": 3}'):
		printerr("  valid JSON must apply")
		return false
	if not is_equal_approx(RemoteConfig.get_float("test/speed", 0.0), 12.5):
		printerr("  float override wrong")
		return false
	if RemoteConfig.get_int("test/count", 0) != 3:
		printerr("  int override wrong")
		return false
	if RemoteConfig.apply_json("this is not json"):
		printerr("  invalid JSON must be refused")
		return false
	if not is_equal_approx(RemoteConfig.get_float("test/speed", 0.0), 12.5):
		printerr("  refused payload must keep previous overrides")
		return false
	RemoteConfig.clear_overrides()
	if RemoteConfig.has_override("test/speed"):
		printerr("  clear must drop overrides")
		return false
	return true


func test_analytics_session_counters() -> bool:
	# The session_end counters intercept ad_shown / run_started internally.
	Analytics._session_ads = 0
	Analytics._session_runs = 0
	Analytics.track(&"ad_shown", {"placement": 1})
	Analytics.track(&"ad_shown", {"placement": 2})
	EventBus.run_started.emit()
	if Analytics._session_ads != 2:
		printerr("  ad_shown not counted: %d" % Analytics._session_ads)
		return false
	if Analytics._session_runs != 1:
		printerr("  run_started not counted: %d" % Analytics._session_runs)
		return false
	return true
