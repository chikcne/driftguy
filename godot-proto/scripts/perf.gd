class_name Perf
extends RefCounted

# Section timer behind tools/bench.gd. Perf.begin() starts the clock and each
# Perf.mark("name") charges the time since the previous mark to that section.
# Off by default: a disabled mark() is a single flag check.

static var enabled := false
static var acc: Dictionary = {} # section -> total microseconds
static var peak: Dictionary = {} # section -> worst single frame, microseconds
static var _frame: Dictionary = {}
static var _last := 0


static func begin() -> void:
	if enabled:
		_last = Time.get_ticks_usec()


static func mark(section: String) -> void:
	if not enabled:
		return
	var spent := Time.get_ticks_usec() - _last
	acc[section] = int(acc.get(section, 0)) + spent
	_frame[section] = int(_frame.get(section, 0)) + spent
	_last = Time.get_ticks_usec()


static func end_frame() -> void:
	for section: String in _frame:
		if int(_frame[section]) > int(peak.get(section, 0)):
			peak[section] = _frame[section]
	_frame.clear()
