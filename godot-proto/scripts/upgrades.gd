class_name Upgrades
extends RefCounted

# Direct 1:1 port of src/upgrades.ts: all 14 upgrades + Field Repair,
# derived car/smoke/weapon stats, and weighted upgrade choice rolling.

const ASH_SLOW := [0.0, 0.35, 0.45, 0.55]
const EMBER_DAMAGE := [0.0, 30.0, 50.0, 75.0]
const EMBER_RADIUS := [0.0, 6.0, 7.5, 9.0]
const TOXIC_DPS := [0.0, 5.0, 9.0, 14.0]
const GUN_BARRELS := [0, 1, 2, 2, 3, 4]
const GUN_FIRE_RATE := [0.0, 6.0, 6.0, 8.0, 8.0, 10.0]
const GUN_DAMAGE := [0.0, 7.0, 7.0, 10.0, 10.0, 13.0]
const PATCH_HEAL := 35.0
const ARMOR_HP := 25.0

const CATEGORY_COLORS := {
	"car": Color("#f2a03a"),
	"smoke": Color("#f4ecdc"),
	"compound": Color("#e2452f"),
	"weapon": Color("#ffd45e"),
	"repair": Color("#6fe08a"),
}

const CATEGORY_LABELS := {
	"car": "CHASSIS",
	"smoke": "SMOKE",
	"compound": "COMPOUND",
	"weapon": "WEAPON",
	"repair": "REPAIR",
}

const HEAL_ON_PICK := {
	"armor": ARMOR_HP,
	"patch": PATCH_HEAL,
}


class UpgradeDef:
	extends RefCounted
	var id: String
	var name: String
	var category: String
	var glyph: String
	var max_level: int # 9999 for infinite (patch)

	func _init(p_id: String, p_name: String, p_cat: String, p_glyph: String, p_max: int) -> void:
		id = p_id
		name = p_name
		category = p_cat
		glyph = p_glyph
		max_level = p_max

	func describe(next_level: int) -> String:
		match id:
			"engine": return "+12% acceleration"
			"gearing": return "+8% top speed"
			"steering": return "Sharper steering and faster rotation"
			"armor": return "+%d max hull, repairs %d" % [int(ARMOR_HP), int(ARMOR_HP)]
			"magnet": return "+40% scrap pickup range"
			"rich": return "+35% smoke volume"
			"fan":
				if next_level == 1:
					return "Rear fan blows smoke outward, clouds spread 16% wider"
				return "Stronger fan, clouds spread 16% wider"
			"linger": return "Smoke lingers 25% longer"
			"caustic": return "+25% smoke damage"
			"ash": return "Grey smoke slows raiders by %d%%" % int(round(ASH_SLOW[next_level] * 100.0))
			"ember": return "Raiders killed in red smoke combust for %d damage" % int(EMBER_DAMAGE[next_level])
			"toxic": return "Green smoke corrodes for %d damage per second after exposure" % int(TOXIC_DPS[next_level])
			"gun":
				if next_level == 1:
					return "Roof machine gun sweeping in a spiral"
				return "%d barrels, %d sweeps per second, %d damage" % [GUN_BARRELS[next_level], int(GUN_FIRE_RATE[next_level]), int(GUN_DAMAGE[next_level])]
			"ram": return "Ramming hurts raiders, 12% less collision damage taken"
			"patch": return "Repair %d hull" % int(PATCH_HEAL)
		return ""


class Stats:
	extends RefCounted
	var engine_accel: float = 13.0
	var top_speed: float = 33.0
	var grip_front: float = 12.5
	var grip_rear: float = 11.0
	var steer_lock_low: float = 0.6
	var steer_lock_high: float = 0.26
	var steer_speed: float = 4.2
	var yaw_response: float = 1.0

	var max_hp: float = 100.0
	var magnet_radius: float = 9.0
	var smoke_rate: float = 1.0
	var smoke_spread: float = 1.0
	var smoke_life: float = 1.0
	var smoke_damage: float = 20.0
	var fan_power: float = 0.0
	var fan_range: float = 0.0
	var ash_slow: float = 0.0
	var ember_damage: float = 0.0
	var ember_radius: float = 0.0
	var toxic_dps: float = 0.0
	var gun_barrels: int = 0
	var gun_fire_rate: float = 0.0
	var gun_damage: float = 0.0
	var ram_damage: float = 0.0
	var ram_guard: float = 0.0


static var _all_cache: Array[UpgradeDef] = []
static var _patch_cache: UpgradeDef = null


static func all_upgrades() -> Array[UpgradeDef]:
	if _all_cache.is_empty():
		_all_cache = [
			UpgradeDef.new("engine", "Blower Kit", "car", "▲", 5),
			UpgradeDef.new("gearing", "Long Gears", "car", "»", 5),
			UpgradeDef.new("steering", "Quick Rack", "car", "↺", 5),
			UpgradeDef.new("armor", "Scrap Plating", "car", "■", 5),
			UpgradeDef.new("magnet", "Scrap Magnet", "car", "◎", 4),
			UpgradeDef.new("rich", "Rich Mixture", "smoke", "☁", 5),
			UpgradeDef.new("fan", "Turbine Fan", "smoke", "✣", 5),
			UpgradeDef.new("linger", "Heavy Oil", "smoke", "≋", 4),
			UpgradeDef.new("caustic", "Caustic Blend", "smoke", "☠", 5),
			UpgradeDef.new("ash", "Ash Compound", "compound", "●", 3),
			UpgradeDef.new("ember", "Ember Compound", "compound", "✹", 3),
			UpgradeDef.new("toxic", "Toxic Compound", "compound", "☣", 3),
			UpgradeDef.new("gun", "Spiral Gun", "weapon", "✺", 5),
			UpgradeDef.new("ram", "Ram Plow", "weapon", "◢", 4),
		]
	return _all_cache


static func patch_upgrade() -> UpgradeDef:
	if _patch_cache == null:
		_patch_cache = UpgradeDef.new("patch", "Field Repair", "repair", "✚", 9999)
	return _patch_cache


static func empty_levels() -> Dictionary:
	var levels := { "patch": 0 }
	for u in all_upgrades():
		levels[u.id] = 0
	return levels


static func derive_stats(levels: Dictionary) -> Stats:
	var s := Stats.new()
	var steering: int = levels["steering"]
	var eng: int = levels["engine"]
	var gear: int = levels["gearing"]
	var arm: int = levels["armor"]
	var mag: int = levels["magnet"]
	var rich: int = levels["rich"]
	var fan: int = levels["fan"]
	var linger: int = levels["linger"]
	var caustic: int = levels["caustic"]
	var ash: int = levels["ash"]
	var ember: int = levels["ember"]
	var toxic: int = levels["toxic"]
	var gun: int = levels["gun"]
	var ram: int = levels["ram"]

	s.engine_accel = 13.0 * (1.0 + 0.12 * float(eng))
	s.top_speed = 33.0 * (1.0 + 0.08 * float(gear))
	s.grip_front = 12.5 * (1.0 + 0.05 * float(steering))
	s.grip_rear = 11.0
	s.steer_lock_low = 0.6 * (1.0 + 0.06 * float(steering))
	s.steer_lock_high = 0.26 * (1.0 + 0.1 * float(steering))
	s.steer_speed = 4.2 * (1.0 + 0.15 * float(steering))
	s.yaw_response = 1.0 * (1.0 + 0.07 * float(steering))

	s.max_hp = 100.0 + ARMOR_HP * float(arm)
	s.magnet_radius = 9.0 * (1.0 + 0.4 * float(mag))
	s.smoke_rate = 1.0 + 0.35 * float(rich)
	s.smoke_spread = 1.0 + 0.16 * float(fan)
	s.smoke_life = 1.0 + 0.25 * float(linger)
	s.smoke_damage = 20.0 * (1.0 + 0.25 * float(caustic))
	s.fan_power = (6.0 + 3.5 * float(fan)) if fan > 0 else 0.0
	s.fan_range = (7.0 + 1.6 * float(fan)) if fan > 0 else 0.0
	s.ash_slow = ASH_SLOW[ash]
	s.ember_damage = EMBER_DAMAGE[ember]
	s.ember_radius = EMBER_RADIUS[ember]
	s.toxic_dps = TOXIC_DPS[toxic]
	s.gun_barrels = GUN_BARRELS[gun]
	s.gun_fire_rate = GUN_FIRE_RATE[gun]
	s.gun_damage = GUN_DAMAGE[gun]
	s.ram_damage = 22.0 * float(ram)
	s.ram_guard = 0.12 * float(ram)
	return s


static func apply_to_car(car: CarBody, stats: Stats) -> void:
	car.engine_accel = stats.engine_accel
	car.top_speed = stats.top_speed
	car.grip_front = stats.grip_front
	car.grip_rear = stats.grip_rear
	car.steer_lock_low = stats.steer_lock_low
	car.steer_lock_high = stats.steer_lock_high
	car.steer_speed = stats.steer_speed
	car.yaw_response = stats.yaw_response


static func roll_choices(levels: Dictionary, count: int) -> Array[UpgradeDef]:
	var pool: Array[UpgradeDef] = []
	for u in all_upgrades():
		if levels[u.id] < u.max_level:
			pool.append(u)
	var picks: Array[UpgradeDef] = []
	while picks.size() < count and pool.size() > 0:
		var total := 0.0
		var weights: Array[float] = []
		for u in pool:
			var w := 1.3 if levels[u.id] > 0 else 1.0
			weights.append(w)
			total += w
		var roll := randf() * total
		var idx := 0
		while idx < pool.size() - 1 and roll > weights[idx]:
			roll -= weights[idx]
			idx += 1
		picks.append(pool[idx])
		pool.remove_at(idx)
	if picks.size() < count:
		picks.append(patch_upgrade())
	return picks


static func scrap_needed(level: int) -> float:
	return floor(3.0 + float(level) * 3.0 + pow(float(level), 1.7))
