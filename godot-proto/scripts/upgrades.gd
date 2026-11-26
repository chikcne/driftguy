class_name Upgrades
extends RefCounted

# All upgrades + Field Repair, derived car/smoke/weapon/explosive/nitro stats,
# rarity/prerequisite gating, and weighted upgrade choice rolling.

const RARITY_COMMON := "common"
const RARITY_UNCOMMON := "uncommon"
const RARITY_RARE := "rare"

const RARITY_WEIGHTS := {
	RARITY_COMMON: 1.0,
	RARITY_UNCOMMON: 0.65,
	RARITY_RARE: 0.30,
}

const RARITY_LABELS := {
	RARITY_COMMON: "",
	RARITY_UNCOMMON: "UNCOMMON",
	RARITY_RARE: "RARE",
}

const ASH_SLOW := [0.0, 0.35, 0.45, 0.55]
const EMBER_DAMAGE := [0.0, 30.0, 50.0, 75.0]
const EMBER_RADIUS := [0.0, 6.0, 7.5, 9.0]
const TOXIC_DPS := [0.0, 5.0, 9.0, 14.0]
const GUN_BARRELS := [0, 1, 2, 2, 3, 4]
const GUN_FIRE_RATE := [0.0, 6.0, 6.0, 8.0, 8.0, 10.0]
const GUN_DAMAGE := [0.0, 7.0, 7.0, 10.0, 10.0, 13.0]
const RAM_FRONT_ARMOR := [0.0, 16.0, 22.0, 28.0, 34.0]
const RAM_FRONT_BONUS := [0.0, 12.0, 20.0, 28.0, 38.0]

# Explosives weapon tables (alternating cadence & blast radius/damage per tier)
const MINE_INTERVAL := [0.0, 3.0, 2.3, 2.3, 1.7, 1.7]
const MINE_RADIUS := [0.0, 4.8, 4.8, 6.2, 6.2, 7.8]
const MINE_DAMAGE := [0.0, 40.0, 40.0, 55.0, 55.0, 75.0]
const MINE_FUSE := 4.0

const GRENADE_INTERVAL := [0.0, 2.5, 1.9, 1.9, 1.4, 1.4]
const GRENADE_RADIUS := [0.0, 4.5, 4.5, 5.8, 5.8, 7.2]
const GRENADE_DAMAGE := [0.0, 34.0, 34.0, 48.0, 48.0, 65.0]
const GRENADE_FUSE := 1.5

# Cross-upgrade / multi-weapon rare synergy tables
const EXPLOSIVE_COUNT := [1, 2, 3]
const PRESSURIZED_BONUS := [0.0, 0.20, 0.40]
const CATALYST_POWER := [1.0, 1.25, 1.50]
const CATALYST_LINGER := [1.0, 1.35, 1.70]
const OVERDRIVE_TANKS := [0, 1, 2]
const OVERDRIVE_CHARGE := [1.0, 1.25, 1.50]
const OVERDRIVE_SPEED := [0.0, 0.08, 0.16]

const BASE_NITROUS_MAX_TANKS := 6
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
	var rarity: String
	var min_level: int
	var requires_any: Array[String]
	var tags: Array[String]

	func _init(
		p_id: String,
		p_name: String,
		p_cat: String,
		p_glyph: String,
		p_max: int,
		p_rarity: String = RARITY_COMMON,
		p_min_level: int = 1,
		p_requires_any: Array[String] = [],
		p_tags: Array[String] = [],
	) -> void:
		id = p_id
		name = p_name
		category = p_cat
		glyph = p_glyph
		max_level = p_max
		rarity = p_rarity
		min_level = p_min_level
		requires_any = p_requires_any
		tags = p_tags

	func is_unlocked(levels: Dictionary, player_level: int = 1) -> bool:
		if player_level < min_level:
			return false
		if requires_any.is_empty():
			return true
		for req_id in requires_any:
			if int(levels.get(req_id, 0)) > 0:
				return true
		return false

	func roll_weight(levels: Dictionary) -> float:
		var base_w: float = float(RARITY_WEIGHTS.get(rarity, 1.0))
		var owned_mult := 1.3 if int(levels.get(id, 0)) > 0 else 1.0
		return base_w * owned_mult

	func describe(next_level: int) -> String:
		match id:
			"engine": return "+12% acceleration"
			"gearing": return "+8% top speed"
			"steering": return "Sharper steering and faster rotation"
			"armor": return "+%d max hull, repairs %d" % [int(ARMOR_HP), int(ARMOR_HP)]
			"magnet": return "+40% scrap pickup range"
			"overdrive":
				return "+%d max nitrous tank%s, +%d%% nitrous charge, +%d%% accel & speed" % [
					int(OVERDRIVE_TANKS[next_level]),
					"s" if int(OVERDRIVE_TANKS[next_level]) > 1 else "",
					int(round((float(OVERDRIVE_CHARGE[next_level]) - 1.0) * 100.0)),
					int(round(float(OVERDRIVE_SPEED[next_level]) * 100.0)),
				]
			"rich": return "+35% smoke volume"
			"fan":
				if next_level == 1:
					return "Rear fan blows smoke outward, clouds spread 16% wider"
				return "Stronger fan, clouds spread 16% wider"
			"linger": return "Smoke lingers 25% longer"
			"caustic": return "+25% smoke damage"
			"pressurized":
				var pct: int = int(round(float(PRESSURIZED_BONUS[next_level]) * 100.0))
				return "+%d%% smoke volume, spread, duration, and damage" % pct
			"ash": return "Grey smoke slows raiders by %d%%" % int(round(float(ASH_SLOW[next_level]) * 100.0))
			"ember": return "Raiders killed in red smoke combust for %d damage" % int(EMBER_DAMAGE[next_level])
			"toxic": return "Green smoke corrodes for %d damage per second after exposure" % int(TOXIC_DPS[next_level])
			"catalyst":
				var p_pct: int = int(round((float(CATALYST_POWER[next_level]) - 1.0) * 100.0))
				var l_pct: int = int(round((float(CATALYST_LINGER[next_level]) - 1.0) * 100.0))
				return "All smoke compounds +%d%% potency and +%d%% linger duration" % [p_pct, l_pct]
			"gun":
				if next_level == 1:
					return "Roof machine gun sweeping in a spiral"
				return "%d barrels, %d sweeps per second, %d damage" % [GUN_BARRELS[next_level], int(GUN_FIRE_RATE[next_level]), int(GUN_DAMAGE[next_level])]
			"ram":
				if next_level == 1:
					return "Armored front plow: %d front armor, +%d ram damage" % [int(RAM_FRONT_ARMOR[next_level]), int(RAM_FRONT_BONUS[next_level])]
				return "Heavier plow: %d front armor, +%d ram damage" % [int(RAM_FRONT_ARMOR[next_level]), int(RAM_FRONT_BONUS[next_level])]
			"mines":
				if next_level == 1:
					return "Lays a proximity mine every %.1fs — explodes on raiders or after %ds" % [MINE_INTERVAL[1], int(MINE_FUSE)]
				if MINE_INTERVAL[next_level] < MINE_INTERVAL[next_level - 1]:
					return "Faster mine chute: lays every %.1fs (%.1fm blast, %d dmg)" % [MINE_INTERVAL[next_level], MINE_RADIUS[next_level], int(MINE_DAMAGE[next_level])]
				return "Bigger mine blast: %.1fm radius, %d damage (every %.1fs)" % [MINE_RADIUS[next_level], int(MINE_DAMAGE[next_level]), MINE_INTERVAL[next_level]]
			"grenades":
				if next_level == 1:
					return "Tosses a bouncing grenade off the rear every %.1fs (%.1fs fuse)" % [GRENADE_INTERVAL[1], GRENADE_FUSE]
				if GRENADE_INTERVAL[next_level] < GRENADE_INTERVAL[next_level - 1]:
					return "Faster rear toss: every %.1fs (%.1fm blast, %d dmg)" % [GRENADE_INTERVAL[next_level], GRENADE_RADIUS[next_level], int(GRENADE_DAMAGE[next_level])]
				return "Bigger frag blast: %.1fm radius, %d damage (every %.1fs)" % [GRENADE_RADIUS[next_level], int(GRENADE_DAMAGE[next_level]), GRENADE_INTERVAL[next_level]]
			"salvo":
				var cnt: int = EXPLOSIVE_COUNT[next_level]
				if next_level == 1:
					return "Doubles explosives fired: %d mines or grenades per release" % cnt
				return "Releases %d mines or grenades at once" % cnt
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
	var compound_linger_scale: float = 1.0
	var gun_barrels: int = 0
	var gun_fire_rate: float = 0.0
	var gun_damage: float = 0.0
	var ram_front_armor: float = 0.0
	var ram_front_bonus: float = 0.0
	var mine_interval: float = 0.0
	var mine_radius: float = 0.0
	var mine_damage: float = 0.0
	var grenade_interval: float = 0.0
	var grenade_radius: float = 0.0
	var grenade_damage: float = 0.0
	var explosive_count: int = 1
	var nitro_max_tanks: int = BASE_NITROUS_MAX_TANKS
	var nitro_charge_scale: float = 1.0


static var _all_cache: Array[UpgradeDef] = []
static var _patch_cache: UpgradeDef = null


static func all_upgrades() -> Array[UpgradeDef]:
	if _all_cache.is_empty():
		_all_cache = [
			# Chassis
			UpgradeDef.new("engine", "Blower Kit", "car", "▲", 5, RARITY_COMMON, 1, [], ["car"]),
			UpgradeDef.new("gearing", "Long Gears", "car", "»", 5, RARITY_COMMON, 1, [], ["car"]),
			UpgradeDef.new("steering", "Quick Rack", "car", "↺", 5, RARITY_COMMON, 1, [], ["car"]),
			UpgradeDef.new("armor", "Scrap Plating", "car", "■", 5, RARITY_COMMON, 1, [], ["car"]),
			UpgradeDef.new("magnet", "Scrap Magnet", "car", "◎", 4, RARITY_COMMON, 1, [], ["car"]),
			UpgradeDef.new("overdrive", "Nitrous Manifold", "car", "◈", 2, RARITY_RARE, 1, ["engine", "gearing", "steering"], ["car", "synergy"]),

			# Smoke
			UpgradeDef.new("rich", "Rich Mixture", "smoke", "☁", 5, RARITY_COMMON, 1, [], ["smoke"]),
			UpgradeDef.new("fan", "Turbine Fan", "smoke", "✣", 5, RARITY_COMMON, 1, [], ["smoke"]),
			UpgradeDef.new("linger", "Heavy Oil", "smoke", "≋", 4, RARITY_COMMON, 1, [], ["smoke"]),
			UpgradeDef.new("caustic", "Caustic Blend", "smoke", "☠", 5, RARITY_COMMON, 1, [], ["smoke"]),
			UpgradeDef.new("pressurized", "Pressurized Exhaust", "smoke", "❖", 2, RARITY_RARE, 1, ["rich", "fan", "linger", "caustic"], ["smoke", "synergy"]),

			# Compounds
			UpgradeDef.new("ash", "Ash Compound", "compound", "●", 3, RARITY_COMMON, 1, [], ["compound"]),
			UpgradeDef.new("ember", "Ember Compound", "compound", "✹", 3, RARITY_COMMON, 1, [], ["compound"]),
			UpgradeDef.new("toxic", "Toxic Compound", "compound", "☣", 3, RARITY_COMMON, 1, [], ["compound"]),
			UpgradeDef.new("catalyst", "Volatile Catalyst", "compound", "✦", 2, RARITY_RARE, 1, ["ash", "ember", "toxic"], ["compound", "synergy"]),

			# Weapons
			UpgradeDef.new("gun", "Spiral Gun", "weapon", "✺", 5, RARITY_COMMON, 1, [], ["weapon", "ballistic"]),
			UpgradeDef.new("ram", "Ram Plow", "weapon", "◢", 4, RARITY_COMMON, 1, [], ["weapon", "melee"]),
			UpgradeDef.new("mines", "Road Mines", "weapon", "◉", 5, RARITY_COMMON, 1, [], ["weapon", "explosive"]),
			UpgradeDef.new("grenades", "Frag Grenades", "weapon", "❂", 5, RARITY_COMMON, 1, [], ["weapon", "explosive"]),
			UpgradeDef.new("salvo", "Cluster Chute", "weapon", "⇶", 2, RARITY_RARE, 1, ["mines", "grenades"], ["weapon", "explosive", "synergy"]),
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
	var steering: int = int(levels.get("steering", 0))
	var eng: int = int(levels.get("engine", 0))
	var gear: int = int(levels.get("gearing", 0))
	var arm: int = int(levels.get("armor", 0))
	var mag: int = int(levels.get("magnet", 0))
	var overdrive: int = int(levels.get("overdrive", 0))
	var rich: int = int(levels.get("rich", 0))
	var fan: int = int(levels.get("fan", 0))
	var linger: int = int(levels.get("linger", 0))
	var caustic: int = int(levels.get("caustic", 0))
	var pressurized: int = int(levels.get("pressurized", 0))
	var ash: int = int(levels.get("ash", 0))
	var ember: int = int(levels.get("ember", 0))
	var toxic: int = int(levels.get("toxic", 0))
	var catalyst: int = int(levels.get("catalyst", 0))
	var gun: int = int(levels.get("gun", 0))
	var ram: int = int(levels.get("ram", 0))
	var mines: int = int(levels.get("mines", 0))
	var grenades: int = int(levels.get("grenades", 0))
	var salvo: int = int(levels.get("salvo", 0))

	var speed_mult: float = 1.0 + float(OVERDRIVE_SPEED[overdrive])
	var smoke_mult: float = 1.0 + float(PRESSURIZED_BONUS[pressurized])
	var comp_power: float = float(CATALYST_POWER[catalyst])

	s.engine_accel = 13.0 * (1.0 + 0.12 * float(eng)) * speed_mult
	s.top_speed = 33.0 * (1.0 + 0.08 * float(gear)) * speed_mult
	s.grip_front = 12.5 * (1.0 + 0.05 * float(steering))
	s.grip_rear = 11.0
	s.steer_lock_low = 0.6 * (1.0 + 0.06 * float(steering))
	s.steer_lock_high = 0.26 * (1.0 + 0.1 * float(steering))
	s.steer_speed = 4.2 * (1.0 + 0.15 * float(steering))
	s.yaw_response = 1.0 * (1.0 + 0.07 * float(steering))

	s.max_hp = 100.0 + ARMOR_HP * float(arm)
	s.magnet_radius = 9.0 * (1.0 + 0.4 * float(mag))
	s.nitro_max_tanks = BASE_NITROUS_MAX_TANKS + OVERDRIVE_TANKS[overdrive]
	s.nitro_charge_scale = OVERDRIVE_CHARGE[overdrive]

	s.smoke_rate = (1.0 + 0.35 * float(rich)) * smoke_mult
	s.smoke_spread = (1.0 + 0.16 * float(fan)) * smoke_mult
	s.smoke_life = (1.0 + 0.25 * float(linger)) * smoke_mult
	s.smoke_damage = 20.0 * (1.0 + 0.25 * float(caustic)) * smoke_mult
	s.fan_power = (6.0 + 3.5 * float(fan)) * smoke_mult if fan > 0 else 0.0
	s.fan_range = (7.0 + 1.6 * float(fan)) * smoke_mult if fan > 0 else 0.0

	s.ash_slow = minf(0.75, ASH_SLOW[ash] * comp_power) if ash > 0 else 0.0
	s.ember_damage = EMBER_DAMAGE[ember] * comp_power
	s.ember_radius = EMBER_RADIUS[ember] * (1.0 + (comp_power - 1.0) * 0.5) if ember > 0 else 0.0
	s.toxic_dps = TOXIC_DPS[toxic] * comp_power
	s.compound_linger_scale = CATALYST_LINGER[catalyst]

	s.gun_barrels = GUN_BARRELS[gun]
	s.gun_fire_rate = GUN_FIRE_RATE[gun]
	s.gun_damage = GUN_DAMAGE[gun]
	s.ram_front_armor = RAM_FRONT_ARMOR[ram]
	s.ram_front_bonus = RAM_FRONT_BONUS[ram]

	s.mine_interval = MINE_INTERVAL[mines]
	s.mine_radius = MINE_RADIUS[mines]
	s.mine_damage = MINE_DAMAGE[mines]
	s.grenade_interval = GRENADE_INTERVAL[grenades]
	s.grenade_radius = GRENADE_RADIUS[grenades]
	s.grenade_damage = GRENADE_DAMAGE[grenades]
	s.explosive_count = EXPLOSIVE_COUNT[salvo]
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


static func roll_choices(levels: Dictionary, count: int, player_level: int = 1) -> Array[UpgradeDef]:
	var pool: Array[UpgradeDef] = []
	for u in all_upgrades():
		if int(levels.get(u.id, 0)) < u.max_level and u.is_unlocked(levels, player_level):
			pool.append(u)
	var picks: Array[UpgradeDef] = []
	while picks.size() < count and pool.size() > 0:
		var total := 0.0
		var weights: Array[float] = []
		for u in pool:
			var w := u.roll_weight(levels)
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
