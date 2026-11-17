import { BASE_TUNING, type CarTuning } from "./vehicle";

export type UpgradeId =
  | "engine"
  | "gearing"
  | "steering"
  | "armor"
  | "magnet"
  | "rich"
  | "fan"
  | "linger"
  | "caustic"
  | "ash"
  | "ember"
  | "toxic"
  | "gun"
  | "ram"
  | "patch";

export type UpgradeCategory = "car" | "smoke" | "compound" | "weapon" | "repair";

export interface UpgradeDef {
  id: UpgradeId;
  name: string;
  category: UpgradeCategory;
  glyph: string;
  maxLevel: number;
  describe: (nextLevel: number) => string;
}

export type UpgradeLevels = Record<UpgradeId, number>;

const ASH_SLOW = [0, 0.35, 0.45, 0.55];
const EMBER_DAMAGE = [0, 30, 50, 75];
const EMBER_RADIUS = [0, 6, 7.5, 9];
const TOXIC_DPS = [0, 5, 9, 14];
const GUN_BARRELS = [0, 1, 2, 2, 3, 4];
const GUN_FIRE_RATE = [0, 6, 6, 8, 8, 10];
const GUN_DAMAGE = [0, 7, 7, 10, 10, 13];
const PATCH_HEAL = 35;
const ARMOR_HP = 25;

const percent = (value: number): string => `${Math.round(value * 100)}%`;

export const UPGRADES: UpgradeDef[] = [
  { id: "engine", name: "Blower Kit", category: "car", glyph: "▲", maxLevel: 5, describe: () => "+12% acceleration" },
  { id: "gearing", name: "Long Gears", category: "car", glyph: "»", maxLevel: 5, describe: () => "+8% top speed" },
  { id: "steering", name: "Quick Rack", category: "car", glyph: "↺", maxLevel: 5, describe: () => "Sharper steering and faster rotation" },
  { id: "armor", name: "Scrap Plating", category: "car", glyph: "■", maxLevel: 5, describe: () => `+${ARMOR_HP} max hull, repairs ${ARMOR_HP}` },
  { id: "magnet", name: "Scrap Magnet", category: "car", glyph: "◎", maxLevel: 4, describe: () => "+40% scrap pickup range" },
  { id: "rich", name: "Rich Mixture", category: "smoke", glyph: "☁", maxLevel: 5, describe: () => "+35% smoke volume" },
  {
    id: "fan",
    name: "Turbine Fan",
    category: "smoke",
    glyph: "✣",
    maxLevel: 5,
    describe: (level) => (level === 1 ? "Rear fan blows smoke outward, clouds spread 16% wider" : "Stronger fan, clouds spread 16% wider"),
  },
  { id: "linger", name: "Heavy Oil", category: "smoke", glyph: "≋", maxLevel: 4, describe: () => "Smoke lingers 25% longer" },
  { id: "caustic", name: "Caustic Blend", category: "smoke", glyph: "☠", maxLevel: 5, describe: () => "+25% smoke damage" },
  {
    id: "ash",
    name: "Ash Compound",
    category: "compound",
    glyph: "●",
    maxLevel: 3,
    describe: (level) => `Grey smoke slows raiders by ${percent(ASH_SLOW[level])}`,
  },
  {
    id: "ember",
    name: "Ember Compound",
    category: "compound",
    glyph: "✹",
    maxLevel: 3,
    describe: (level) => `Raiders killed in red smoke combust for ${EMBER_DAMAGE[level]} damage`,
  },
  {
    id: "toxic",
    name: "Toxic Compound",
    category: "compound",
    glyph: "☣",
    maxLevel: 3,
    describe: (level) => `Green smoke corrodes for ${TOXIC_DPS[level]} damage per second after exposure`,
  },
  {
    id: "gun",
    name: "Spiral Gun",
    category: "weapon",
    glyph: "✺",
    maxLevel: 5,
    describe: (level) =>
      level === 1
        ? "Roof machine gun sweeping in a spiral"
        : `${GUN_BARRELS[level]} barrels, ${GUN_FIRE_RATE[level]} sweeps per second, ${GUN_DAMAGE[level]} damage`,
  },
  {
    id: "ram",
    name: "Ram Plow",
    category: "weapon",
    glyph: "◢",
    maxLevel: 4,
    describe: () => "Ramming hurts raiders, 12% less collision damage taken",
  },
];

export const PATCH_UPGRADE: UpgradeDef = {
  id: "patch",
  name: "Field Repair",
  category: "repair",
  glyph: "✚",
  maxLevel: Number.POSITIVE_INFINITY,
  describe: () => `Repair ${PATCH_HEAL} hull`,
};

export function emptyLevels(): UpgradeLevels {
  const levels = { patch: 0 } as UpgradeLevels;
  for (const upgrade of UPGRADES) levels[upgrade.id] = 0;
  return levels;
}

export interface Stats {
  tuning: CarTuning;
  maxHp: number;
  magnetRadius: number;
  smokeRate: number;
  smokeSpread: number;
  smokeLife: number;
  smokeDamage: number;
  fanPower: number;
  fanRange: number;
  ashSlow: number;
  emberDamage: number;
  emberRadius: number;
  toxicDps: number;
  gunBarrels: number;
  gunFireRate: number;
  gunDamage: number;
  ramDamage: number;
  ramGuard: number;
}

export const HEAL_ON_PICK: Partial<Record<UpgradeId, number>> = { armor: ARMOR_HP, patch: PATCH_HEAL };

export function deriveStats(levels: UpgradeLevels): Stats {
  const steering = levels.steering;
  return {
    tuning: {
      ...BASE_TUNING,
      engineAccel: BASE_TUNING.engineAccel * (1 + 0.12 * levels.engine),
      topSpeed: BASE_TUNING.topSpeed * (1 + 0.08 * levels.gearing),
      gripFront: BASE_TUNING.gripFront * (1 + 0.05 * steering),
      steerLockLow: BASE_TUNING.steerLockLow * (1 + 0.06 * steering),
      steerLockHigh: BASE_TUNING.steerLockHigh * (1 + 0.1 * steering),
      steerSpeed: BASE_TUNING.steerSpeed * (1 + 0.15 * steering),
      yawResponse: BASE_TUNING.yawResponse * (1 + 0.07 * steering),
    },
    maxHp: 100 + ARMOR_HP * levels.armor,
    magnetRadius: 9 * (1 + 0.4 * levels.magnet),
    smokeRate: 1 + 0.35 * levels.rich,
    smokeSpread: 1 + 0.16 * levels.fan,
    smokeLife: 1 + 0.25 * levels.linger,
    smokeDamage: 20 * (1 + 0.25 * levels.caustic),
    fanPower: levels.fan > 0 ? 6 + 3.5 * levels.fan : 0,
    fanRange: levels.fan > 0 ? 7 + 1.6 * levels.fan : 0,
    ashSlow: ASH_SLOW[levels.ash],
    emberDamage: EMBER_DAMAGE[levels.ember],
    emberRadius: EMBER_RADIUS[levels.ember],
    toxicDps: TOXIC_DPS[levels.toxic],
    gunBarrels: GUN_BARRELS[levels.gun],
    gunFireRate: GUN_FIRE_RATE[levels.gun],
    gunDamage: GUN_DAMAGE[levels.gun],
    ramDamage: 22 * levels.ram,
    ramGuard: 0.12 * levels.ram,
  };
}

export function rollChoices(levels: UpgradeLevels, count: number): UpgradeDef[] {
  const pool = UPGRADES.filter((upgrade) => levels[upgrade.id] < upgrade.maxLevel);
  const picks: UpgradeDef[] = [];
  while (picks.length < count && pool.length > 0) {
    const weights = pool.map((upgrade) => (levels[upgrade.id] > 0 ? 1.3 : 1));
    let roll = Math.random() * weights.reduce((sum, weight) => sum + weight, 0);
    let index = 0;
    while (index < pool.length - 1 && roll > weights[index]) {
      roll -= weights[index];
      index++;
    }
    picks.push(pool[index]);
    pool.splice(index, 1);
  }
  if (picks.length < count) picks.push(PATCH_UPGRADE);
  return picks;
}
