import { Material, Scene, ShadowGenerator } from "@babylonjs/core";
import { InstanceBatch } from "./kit";
import { clamp, moveToward, randRange, randSigned, TAU, wrapAngle } from "./math";
import { buildEnemyModels, type EnemyKind } from "./models";
import { createSmokeSample, PUFF, type SmokeSystem } from "./smoke";
import { sampleSlope, type Slope } from "./terrain";
import type { Stats } from "./upgrades";
import type { CarBody } from "./vehicle";
import type { Contact, World } from "./world";

export interface EnemySpec {
  kind: EnemyKind;
  radius: number;
  hp: number;
  speed: number;
  accel: number;
  turn: number;
  grip: number;
  damage: number;
  scrap: number;
  halfLength: number;
  halfWidth: number;
  mass: number;
}

export const ENEMY_SPECS: Record<EnemyKind, EnemySpec> = {
  bike: { kind: "bike", radius: 0.95, hp: 8, speed: 30, accel: 16, turn: 2.6, grip: 3.6, damage: 3, scrap: 1, halfLength: 0.9, halfWidth: 0.4, mass: 0.2 },
  buggy: { kind: "buggy", radius: 1.55, hp: 26, speed: 26, accel: 12, turn: 1.9, grip: 2.6, damage: 7, scrap: 2, halfLength: 1.5, halfWidth: 0.95, mass: 0.6 },
  truck: { kind: "truck", radius: 2.4, hp: 110, speed: 19, accel: 7, turn: 1.1, grip: 2.0, damage: 18, scrap: 7, halfLength: 2.8, halfWidth: 1.2, mass: 1.5 },
  interceptor: { kind: "interceptor", radius: 1.7, hp: 60, speed: 35, accel: 15, turn: 1.7, grip: 2.2, damage: 14, scrap: 4, halfLength: 2.2, halfWidth: 1.0, mass: 0.9 },
  rig: { kind: "rig", radius: 3.6, hp: 900, speed: 22, accel: 6, turn: 0.8, grip: 1.8, damage: 30, scrap: 45, halfLength: 5.4, halfWidth: 1.5, mass: 4 },
};

export interface Enemy {
  spec: EnemySpec;
  x: number;
  z: number;
  heading: number;
  vx: number;
  vz: number;
  hp: number;
  maxHp: number;
  hitCooldown: number;
  ramCooldown: number;
  blindTimer: number;
  slowTimer: number;
  emberTimer: number;
  toxicTimer: number;
  flinch: number;
  dustTimer: number;
  flank: number;
}

export interface EnemyContext {
  dt: number;
  time: number;
  car: CarBody;
  stats: Stats;
  world: World;
  smoke: SmokeSystem;
  damageScale: number;
  onPlayerHit: (enemy: Enemy, damage: number, closingSpeed: number) => void;
  onKill: (enemy: Enemy) => void;
}

export const MAX_ENEMIES = 200;
const SMOKE_THRESHOLD = 0.2;
const SMOKE_FULL_DENSITY = 3;
const SMOKE_DENSITY_CAP = 2.5;
const KIND_SHARE_THRESHOLD = 0.25;
const ASH_LINGER = 0.5;
const EMBER_LINGER = 1.2;
const TOXIC_LINGER = 3;
const HIT_COOLDOWN = 1;
const BLINDED_SPEED_FACTOR = 0.72;
const BLINDED_LINGER = 0.25;
const RAM_COOLDOWN = 0.4;
const RAM_MIN_SPEED = 8;
const CAR_CIRCLE_OFFSET = 1.05;
const CAR_CIRCLE_RADIUS = 1.15;
const DUST_INTERVAL = 0.3;
const DUST_VISIBLE_RANGE = 75;
const FLANK_DISTANCE = 16;
const STIR_RATE = 1.6;

export class EnemySystem {
  readonly active: Enemy[] = [];
  private readonly batches: Record<EnemyKind, InstanceBatch>;
  private readonly sample = createSmokeSample();
  private readonly contact: Contact = { hit: false, nx: 0, nz: 0 };
  private readonly slope: Slope = { height: 0, pitch: 0, roll: 0 };

  constructor(scene: Scene, material: Material, shadows: ShadowGenerator) {
    const models = buildEnemyModels(scene);
    const batches = {} as Record<EnemyKind, InstanceBatch>;
    for (const kind of Object.keys(models) as EnemyKind[]) {
      const mesh = models[kind];
      mesh.material = material;
      mesh.receiveShadows = true;
      shadows.addShadowCaster(mesh);
      batches[kind] = new InstanceBatch(mesh, MAX_ENEMIES);
    }
    this.batches = batches;
  }

  clear(): void {
    this.active.length = 0;
  }

  spawn(kind: EnemyKind, x: number, z: number, hpScale: number, facing: number): Enemy | null {
    if (this.active.length >= MAX_ENEMIES) return null;
    const spec = ENEMY_SPECS[kind];
    const enemy: Enemy = {
      spec,
      x,
      z,
      heading: facing,
      vx: Math.sin(facing) * spec.speed * 0.7,
      vz: Math.cos(facing) * spec.speed * 0.7,
      hp: spec.hp * hpScale,
      maxHp: spec.hp * hpScale,
      hitCooldown: 0,
      ramCooldown: 0,
      blindTimer: 0,
      slowTimer: 0,
      emberTimer: 0,
      toxicTimer: 0,
      flinch: 0,
      dustTimer: Math.random() * DUST_INTERVAL,
      flank: randSigned(1),
    };
    this.active.push(enemy);
    return enemy;
  }

  hurtArea(x: number, z: number, radius: number, damage: number): void {
    for (const enemy of this.active) {
      const reach = radius + enemy.spec.radius;
      const dx = enemy.x - x;
      const dz = enemy.z - z;
      if (dx * dx + dz * dz > reach * reach) continue;
      enemy.hp -= damage;
      enemy.flinch = 1;
    }
  }

  sweepDead(onKill: (enemy: Enemy) => void): void {
    for (let i = this.active.length - 1; i >= 0; i--) {
      const enemy = this.active[i];
      if (enemy.hp > 0) continue;
      this.active[i] = this.active[this.active.length - 1];
      this.active.pop();
      onKill(enemy);
    }
  }

  update(ctx: EnemyContext): void {
    const { dt, car, stats, smoke } = ctx;
    const stir = Math.min(1, STIR_RATE * dt);
    for (const enemy of this.active) {
      const spec = enemy.spec;
      enemy.hitCooldown -= dt;
      enemy.ramCooldown -= dt;
      enemy.blindTimer -= dt;
      enemy.slowTimer -= dt;
      enemy.emberTimer -= dt;
      enemy.toxicTimer -= dt;
      enemy.flinch = Math.max(0, enemy.flinch - dt * 4);

      const cloud = smoke.sample(enemy.x, enemy.z, this.sample, enemy.vx, enemy.vz, stir);
      if (cloud.total > SMOKE_THRESHOLD) {
        const density = Math.min(SMOKE_DENSITY_CAP, cloud.total / SMOKE_FULL_DENSITY);
        enemy.hp -= stats.smokeDamage * density * dt;
        enemy.flinch = Math.max(enemy.flinch, 0.6);
        enemy.blindTimer = BLINDED_LINGER;
        const share = cloud.total * KIND_SHARE_THRESHOLD;
        if (cloud.byKind[PUFF.ash] > share) enemy.slowTimer = ASH_LINGER;
        if (cloud.byKind[PUFF.ember] > share) enemy.emberTimer = EMBER_LINGER;
        if (cloud.byKind[PUFF.toxic] > share) enemy.toxicTimer = TOXIC_LINGER;
      }
      if (enemy.toxicTimer > 0) enemy.hp -= stats.toxicDps * dt;

      this.steer(enemy, ctx);
      enemy.x += enemy.vx * dt;
      enemy.z += enemy.vz * dt;

      if (ctx.world.resolve(enemy, spec.radius, this.contact).hit) {
        const into = enemy.vx * this.contact.nx + enemy.vz * this.contact.nz;
        if (into < 0) {
          enemy.vx -= into * this.contact.nx * 1.2;
          enemy.vz -= into * this.contact.nz * 1.2;
        }
      }
      this.collideWithCar(enemy, ctx);

      enemy.dustTimer -= dt;
      if (enemy.dustTimer <= 0) {
        enemy.dustTimer = DUST_INTERVAL;
        const speed = Math.hypot(enemy.vx, enemy.vz);
        if (speed > 6 && Math.abs(enemy.x - car.x) < DUST_VISIBLE_RANGE && Math.abs(enemy.z - car.z) < DUST_VISIBLE_RANGE) {
          const back = spec.halfLength;
          const x = enemy.x - Math.sin(enemy.heading) * back + randSigned(spec.halfWidth);
          const z = enemy.z - Math.cos(enemy.heading) * back + randSigned(spec.halfWidth);
          smoke.emit(PUFF.dust, x, this.groundAt(x, z) + 0.3, z, enemy.vx * 0.2, 0.8, enemy.vz * 0.2, 0.5 + spec.radius * 0.25, 0.9, 1.3, 0.4, 0.2);
        }
      }
    }
    this.separate();
    this.sweepDead(ctx.onKill);
  }

  render(time: number): void {
    for (const batch of Object.values(this.batches)) batch.begin();
    for (const enemy of this.active) {
      const spec = enemy.spec;
      const slope = sampleSlope(enemy.x, enemy.z, enemy.heading, spec.halfLength, spec.halfWidth, this.slope);
      const shake = enemy.flinch * 0.07 * Math.sin(time * 55 + enemy.flank * 9);
      const lean = clamp((enemy.vx * Math.cos(enemy.heading) - enemy.vz * Math.sin(enemy.heading)) * 0.02, -0.3, 0.3);
      this.batches[spec.kind].push(
        enemy.x,
        slope.height,
        enemy.z,
        enemy.heading,
        slope.pitch,
        slope.roll + lean + shake,
        1 + shake,
        1 - shake,
        1 + shake,
      );
    }
    for (const batch of Object.values(this.batches)) batch.commit();
  }

  private groundAt(x: number, z: number): number {
    return sampleSlope(x, z, 0, 0.5, 0.5, this.slope).height;
  }

  private steer(enemy: Enemy, ctx: EnemyContext): void {
    const { dt, car, stats } = ctx;
    const spec = enemy.spec;
    const toCarX = car.x - enemy.x;
    const toCarZ = car.z - enemy.z;
    const distance = Math.hypot(toCarX, toCarZ) + 0.001;
    const lead = Math.min(0.9, distance / 40);
    let targetX = car.x + car.vx * lead;
    let targetZ = car.z + car.vz * lead;
    if (distance > FLANK_DISTANCE) {
      const sideways = enemy.flank * Math.min(distance * 0.35, 22);
      targetX += (toCarZ / distance) * sideways;
      targetZ -= (toCarX / distance) * sideways;
    }
    const desired = Math.atan2(targetX - enemy.x, targetZ - enemy.z);
    const error = wrapAngle(desired - enemy.heading);
    enemy.heading += clamp(error, -spec.turn * dt, spec.turn * dt);

    const fx = Math.sin(enemy.heading);
    const fz = Math.cos(enemy.heading);
    let cap = spec.speed;
    if (enemy.blindTimer > 0) cap *= BLINDED_SPEED_FACTOR;
    if (enemy.slowTimer > 0) cap *= 1 - stats.ashSlow;
    if (Math.abs(error) > 1.2) cap *= 0.65;
    const forward = moveToward(enemy.vx * fx + enemy.vz * fz, cap, spec.accel * dt);
    const sideSlip = (enemy.vx * fz - enemy.vz * fx) * Math.exp(-spec.grip * dt);
    enemy.vx = fx * forward + fz * sideSlip;
    enemy.vz = fz * forward - fx * sideSlip;
  }

  private collideWithCar(enemy: Enemy, ctx: EnemyContext): void {
    const { car, stats } = ctx;
    const spec = enemy.spec;
    const fx = Math.sin(car.heading);
    const fz = Math.cos(car.heading);
    const reach = CAR_CIRCLE_RADIUS + spec.radius;
    let bestDepth = 0;
    let nx = 0;
    let nz = 0;
    for (const side of [-1, 1]) {
      const dx = enemy.x - (car.x + fx * CAR_CIRCLE_OFFSET * side);
      const dz = enemy.z - (car.z + fz * CAR_CIRCLE_OFFSET * side);
      const dist = Math.hypot(dx, dz) || 0.001;
      const depth = reach - dist;
      if (depth > bestDepth) {
        bestDepth = depth;
        nx = dx / dist;
        nz = dz / dist;
      }
    }
    if (bestDepth <= 0) return;

    enemy.x += nx * bestDepth;
    enemy.z += nz * bestDepth;
    const closing = Math.max(0, (car.vx - enemy.vx) * nx + (car.vz - enemy.vz) * nz);
    enemy.vx += nx * (3 + closing * 0.6);
    enemy.vz += nz * (3 + closing * 0.6);
    const shove = Math.min(closing * 0.25, 5) * spec.mass;
    car.vx -= nx * shove;
    car.vz -= nz * shove;
    car.yawRate += (nx * fz - nz * fx) * shove * 0.08;

    if (stats.ramDamage > 0 && car.speed > RAM_MIN_SPEED && enemy.ramCooldown <= 0) {
      enemy.ramCooldown = RAM_COOLDOWN;
      enemy.hp -= stats.ramDamage * (car.speed / 20);
      enemy.flinch = 1;
    }
    if (enemy.hitCooldown <= 0) {
      enemy.hitCooldown = HIT_COOLDOWN;
      ctx.onPlayerHit(enemy, spec.damage * ctx.damageScale * (1 - stats.ramGuard), closing);
    }
  }

  private separate(): void {
    const list = this.active;
    for (let i = 0; i < list.length; i++) {
      const a = list[i];
      for (let j = i + 1; j < list.length; j++) {
        const b = list[j];
        const reach = (a.spec.radius + b.spec.radius) * 0.9;
        const dx = b.x - a.x;
        if (dx > reach || dx < -reach) continue;
        const dz = b.z - a.z;
        const distSq = dx * dx + dz * dz;
        if (distSq >= reach * reach) continue;
        const dist = Math.sqrt(distSq) || 0.001;
        const overlap = (reach - dist) * 0.5;
        const total = a.spec.mass + b.spec.mass;
        const nx = dx / dist;
        const nz = dz / dist;
        a.x -= nx * overlap * (b.spec.mass / total) * 2;
        a.z -= nz * overlap * (b.spec.mass / total) * 2;
        b.x += nx * overlap * (a.spec.mass / total) * 2;
        b.z += nz * overlap * (a.spec.mass / total) * 2;
      }
    }
  }
}

interface SpawnWeights {
  kind: EnemyKind;
  from: number;
  weight: number;
}

const SPAWN_TABLE: SpawnWeights[] = [
  { kind: "bike", from: 0, weight: 3 },
  { kind: "buggy", from: 25, weight: 3 },
  { kind: "truck", from: 110, weight: 1.1 },
  { kind: "interceptor", from: 230, weight: 1.3 },
];

const SPAWN_RING_MIN = 85;
const SPAWN_RING_MAX = 105;
const RECYCLE_DISTANCE = 175;
const SPAWN_COOLDOWN = 0.1;
const WAR_PARTY_INTERVAL = 60;
const WAR_PARTY_WARNING = 4;
const WAR_PARTY_SPREAD = 0.22;
const BOSS_INTERVAL = 150;
const BOSS_WARNING = 6;
const THREAT_ARRIVAL_DISTANCE = 42;
const AHEAD_BIAS = 0.55;
const SCREEN_LEFT_BEARING = -Math.PI / 2;
const SCREEN_RIGHT_BEARING = Math.PI / 2;
const LEFT_SIDE_SHARE = 0.8;
const SIDE_SPREAD = 0.6;
const HP_GROWTH_SECONDS = 140;
const DAMAGE_GROWTH_SECONDS = 420;

export type ThreatKind = "party" | "boss";

export interface Threat {
  kind: ThreatKind;
  bearing: number;
  countdown: number;
  distance: number;
  size: number;
  members: Enemy[];
}

export class Spawner {
  readonly threats: Threat[] = [];
  onThreat: ((threat: Threat) => void) | null = null;
  private cooldown = 0;
  private nextWarParty = WAR_PARTY_INTERVAL;
  private nextBoss = BOSS_INTERVAL;

  reset(): void {
    this.threats.length = 0;
    this.cooldown = 0;
    this.nextWarParty = WAR_PARTY_INTERVAL;
    this.nextBoss = BOSS_INTERVAL;
  }

  damageScale(time: number): number {
    return 1 + time / DAMAGE_GROWTH_SECONDS;
  }

  update(dt: number, time: number, car: CarBody, enemies: EnemySystem): void {
    const hpScale = 1 + time / HP_GROWTH_SECONDS;
    const minutes = time / 60;
    const desired = Math.min(MAX_ENEMIES - 20, 3 + time * 0.19 + minutes * minutes * 1.2);

    for (const enemy of enemies.active) {
      if (Math.abs(enemy.x - car.x) < RECYCLE_DISTANCE && Math.abs(enemy.z - car.z) < RECYCLE_DISTANCE) continue;
      const angle = this.pickSideAngle();
      const distance = randRange(SPAWN_RING_MIN, SPAWN_RING_MAX);
      enemy.x = car.x + Math.sin(angle) * distance;
      enemy.z = car.z + Math.cos(angle) * distance;
      enemy.heading = angle + Math.PI;
    }

    this.cooldown -= dt;
    if (this.cooldown <= 0 && enemies.active.length < desired) {
      this.cooldown = SPAWN_COOLDOWN;
      this.spawnAt(enemies, this.pickKind(time), car, this.pickSideAngle(), hpScale);
    }
    if (time >= this.nextWarParty - WAR_PARTY_WARNING) {
      this.nextWarParty += WAR_PARTY_INTERVAL;
      this.announce("party", WAR_PARTY_WARNING, Math.min(26, 6 + Math.floor(time / 25)), car);
    }
    if (time >= this.nextBoss - BOSS_WARNING) {
      this.nextBoss += BOSS_INTERVAL;
      this.announce("boss", BOSS_WARNING, 1, car);
    }
    this.updateThreats(dt, car, enemies, hpScale);
  }

  private announce(kind: ThreatKind, warning: number, size: number, car: CarBody): void {
    const threat: Threat = { kind, bearing: this.pickWaveAngle(car), countdown: warning, distance: SPAWN_RING_MIN, size, members: [] };
    this.threats.push(threat);
    this.onThreat?.(threat);
  }

  private updateThreats(dt: number, car: CarBody, enemies: EnemySystem, hpScale: number): void {
    for (let i = this.threats.length - 1; i >= 0; i--) {
      const threat = this.threats[i];
      if (threat.countdown > 0) {
        threat.countdown -= dt;
        if (threat.countdown > 0) continue;
        this.release(threat, car, enemies, hpScale);
      }
      if (!this.track(threat, car)) this.threats.splice(i, 1);
    }
  }

  private release(threat: Threat, car: CarBody, enemies: EnemySystem, hpScale: number): void {
    const kind: EnemyKind = threat.kind === "boss" ? "rig" : "bike";
    const spread = threat.kind === "boss" ? 0 : WAR_PARTY_SPREAD;
    for (let i = 0; i < threat.size; i++) {
      const enemy = this.spawnAt(enemies, kind, car, threat.bearing + randSigned(spread), hpScale);
      if (enemy) threat.members.push(enemy);
    }
  }

  private track(threat: Threat, car: CarBody): boolean {
    let x = 0;
    let z = 0;
    let alive = 0;
    for (const enemy of threat.members) {
      if (enemy.hp <= 0) continue;
      x += enemy.x - car.x;
      z += enemy.z - car.z;
      alive++;
    }
    if (alive === 0) return false;
    x /= alive;
    z /= alive;
    threat.distance = Math.hypot(x, z);
    if (threat.distance < THREAT_ARRIVAL_DISTANCE) return false;
    threat.bearing = Math.atan2(x, z);
    return true;
  }

  private spawnAt(enemies: EnemySystem, kind: EnemyKind, car: CarBody, angle: number, hpScale: number): Enemy | null {
    const distance = randRange(SPAWN_RING_MIN, SPAWN_RING_MAX);
    return enemies.spawn(kind, car.x + Math.sin(angle) * distance, car.z + Math.cos(angle) * distance, hpScale, angle + Math.PI);
  }

  private pickSideAngle(): number {
    const side = Math.random() < LEFT_SIDE_SHARE ? SCREEN_LEFT_BEARING : SCREEN_RIGHT_BEARING;
    return side + randSigned(SIDE_SPREAD);
  }

  private pickWaveAngle(car: CarBody): number {
    if (car.speed > 8 && Math.random() < AHEAD_BIAS) return Math.atan2(car.vx, car.vz) + randSigned(1.0);
    return Math.random() * TAU;
  }

  private pickKind(time: number): EnemyKind {
    const open = SPAWN_TABLE.filter((entry) => time >= entry.from);
    let roll = Math.random() * open.reduce((sum, entry) => sum + entry.weight, 0);
    for (const entry of open) {
      roll -= entry.weight;
      if (roll <= 0) return entry.kind;
    }
    return "bike";
  }
}
