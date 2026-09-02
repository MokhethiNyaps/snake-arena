extends Node
## AUTOLOAD #3 — ConsentManager (§22/§45.8). Resolves BEFORE AdManager inits.
##
## Owns: the consent state and its persistence (user://consent.cfg).
## Phase 1: structural stub — state UNKNOWN, dev default GRANTED on resolve.
## Phase 11: real UMP flow on mobile, portal deferral on web, PrivacyConsent
##           screen, CCPA link, age-gate flags.
## Does NOT own: anything ad-serving; AdManager only READS this.
## Talks to: AdManager, PrivacyConsent screen, Settings.

enum ConsentState { UNKNOWN, GRANTED, DENIED }

signal consent_resolved(state: ConsentState)

var state: ConsentState = ConsentState.UNKNOWN
var consent_version: String = ""
var consent_timestamp_unix: int = 0

const CONSENT_PATH: String = "user://consent.cfg"


func _ready() -> void:
	_try_load()


const CONSENT_VERSION: String = "cc-consent-v1"
const CONSENT_SCENE: String = "res://scenes/ui/consent.tscn"

## §45.8 Phase 11 flow, driven by boot BEFORE any menu/run:
## • Web portal build — the portal handles consent; do not double-prompt.
## • Otherwise UNKNOWN — show the PrivacyConsent screen; ACCEPT/DECLINE
##     sets the persisted state. DECLINE keeps the game fully playable
##     (AdManager blocks serving; nothing gameplay-facing is gated).
func needs_ui() -> bool:
	return state == ConsentState.UNKNOWN

func show_consent_screen() -> void:
	UIManager.push_screen(load(CONSENT_SCENE))

## Portal-deferred resolution (web): consent is the PORTAL's responsibility.
func resolve_portal() -> void:
	if state == ConsentState.UNKNOWN:
		state = ConsentState.GRANTED
		consent_version = "portal-deferred"
		consent_timestamp_unix = int(Time.get_unix_time_from_system())
		_save()
		consent_resolved.emit(state)


func set_consent(new_state: ConsentState, version: String) -> void:
	state = new_state
	consent_version = version
	consent_timestamp_unix = int(Time.get_unix_time_from_system())
	_save()
	consent_resolved.emit(state)


func is_granted() -> bool:
	return state == ConsentState.GRANTED


func _try_load() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(CONSENT_PATH) != OK:
		return
	state = cfg.get_value("consent", "state", ConsentState.UNKNOWN)
	consent_version = cfg.get_value("consent", "version", "")
	consent_timestamp_unix = cfg.get_value("consent", "timestamp", 0)


func _save() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("consent", "state", state)
	cfg.set_value("consent", "version", consent_version)
	cfg.set_value("consent", "timestamp", consent_timestamp_unix)
	cfg.save(CONSENT_PATH)
