import { Material, Matrix, type Mesh, Scene, ShadowGenerator } from "@babylonjs/core";
import { composeTransform, InstanceBatch } from "./kit";
import type { Shove } from "./loose";
import { clamp, damp, lerp, moveToward, randRange, randSigned, smoothstep, TAU, wrapAngle } from "./math";
import { buildEnemyModels, buildRiderModels, type EnemyKind, RIDER_SEAT, RIDER_SHOULDER } from "./models";
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
  sway: number;
  wreckSeconds: number;
  wreckSpin: number;
}

export const ENEMY_SPECS: Record<EnemyKind, EnemySpec> = {
  bike: { kind: "bike", radius: 0.95, hp: 8, speed: 30, accel: 16, turn: 2.6, grip: 3.6, damage: 3, scrap: 1, halfLength: 0.9, halfWidth: 0.4, mass: 0.2, sway: 1, wreckSeconds: 0.9, wreckSpin: 4.5 },
  buggy: { kind: "buggy", radius: 1.55, hp: 26, speed: 26, accel: 12, turn: 1.9, grip: 2.6, damage: 7, scrap: 2, halfLength: 1.5, halfWidth: 0.95, mass: 0.6, sway: 0.85, wreckSeconds: 1.25, wreckSpin: 4.6 },
  truck: { kind: "truck", radius: 2.4, hp: 110, speed: 19, accel: 7, turn: 1.1, grip: 2.0, damage: 18, scrap: 7, halfLength: 2.8, halfWidth: 1.2, mass: 1.5, sway: 0.5, wreckSeconds: 1.6, wreckSpin: 2.4 },
  interceptor: { kind: "interceptor", radius: 1.7, hp: 60, speed: 35, accel: 15, turn: 1.7, grip: 2.2, damage: 14, scrap: 4, halfLength: 2.2, halfWidth: 1.0, mass: 0.9, sway: 0.75, wreckSeconds: 1.35, wreckSpin: 4 },
  rig: { kind: "rig", radius: 3.6, hp: 900, speed: 22, accel: 6, turn: 0.8, grip: 1.8, damage: 30, scrap: 45, halfLength: 5.4, halfWidth: 1.5, mass: 4, sway: 0.25, wreckSeconds: 2, wreckSpin: 1.1 },
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
  knockX: number;
  knockZ: number;
  blind: number;
  reel: number;
  spin: number;
  swayPhase: number;
  swayRate: number;
  bumpCooldown: number;
  wreck: number;
  wreckAge: number;
  wreckSide: number;
  tilt: number;
  fxTimer: number;
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
  onWreck: (enemy: Enemy) => void;
  onBump: (enemy: Enemy, strength: number) => void;
  onScrape: (enemy: Enemy) => void;
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
const BLAST_KNOCK = 11;
const KNOCK_FADE = 5;
const BLIND_RISE = 4;
const BLIND_FADE = 1.3;
const REEL_FADE = 1.1;
const REEL_STEER_LOSS = 0.85;
const SPIN_FADE = 2.5;
const SWAY_RATE_MIN = 5;
const SWAY_RATE_MAX = 7.5;
const SWAY_ANGLE = 0.6;
const SWAY_KICK = 16;
const SWAY_GRIP_LOSS = 0.82;
const SWAY_FISHTAIL = 0.17;
const BIKE_SWAY_ROLL = 0.3;
const CAR_SWAY_ROLL = 0.11;
const RIDER_WIGGLE_ROLL = 0.3;
const RIDER_WIGGLE_YAW = 0.38;
const RIDER_RECOIL = -0.24;
const ARM_GRIP = { yaw: 0.1, pitch: 0.48, length: 1.12 };
const ARM_COVER = { yaw: -0.86, pitch: -0.5, length: 0.75 };
const ARM_RUB = 0.09;
const WRECK_SECONDS_SPREAD = 0.25;
const WRECK_SPIN_UP = 6;
const WRECK_VEER = 1.1;
const WRECK_VEER_FADE = 1.6;
const WRECK_ROLL_DRAG = 0.45;
const WRECK_SLIDE_DRAG = 1.2;
const WRECK_TILT_PER_SLIP = 0.035;
const WRECK_TILT_MAX = 0.42;
const WRECK_CRASH_SPEED = 7;
const WRECK_FX_INTERVAL = 0.05;
const WRECK_FUSE = 0.35;
const BIKE_LAY_ANGLE = 1.38;
const BIKE_LAY_RATE = 8;
const BIKE_SPIN_FADE = 3.2;
const BIKE_SLIDE_DRAG = 1.5;
const BUMP_COOLDOWN = 0.5;
const BUMP_DAMAGE = 0.3;
const BUMP_SHOVE = 5;
const BUMP_SPIN = 5;

export class EnemySystem {
  readonly active: Enemy[] = [];
  readonly wrecks: Enemy[] = [];
  readonly meshes: Mesh[];
  private readonly batches: Record<EnemyKind, InstanceBatch>;
  private readonly riders: InstanceBatch;
  private readonly arms: InstanceBatch;
  private readonly mount = new Matrix();
  private readonly seat = new Matrix();
  private readonly sample = createSmokeSample();
  private harmDealt = 0;
  private readonly contact: Contact = { hit: false, nx: 0, nz: 0 };
  private readonly shove: Shove = { hit: false, impulse: 0, x: 0, z: 0, torn: 0 };
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
    const rider = buildRiderModels(scene);
    for (const mesh of [rider.body, rider.arm]) {
      mesh.material = material;
      mesh.receiveShadows = true;
      shadows.addShadowCaster(mesh);
    }
    this.riders = new InstanceBatch(rider.body, MAX_ENEMIES);
    this.arms = new InstanceBatch(rider.arm, MAX_ENEMIES * 2);
    this.meshes = [...Object.values(models), rider.body, rider.arm];
  }

  clear(): void {
    this.active.length = 0;
    this.wrecks.length = 0;
    this.harmDealt = 0;
  }

  hurt(enemy: Enemy, amount: number): void {
    const landed = Math.min(amount, enemy.hp);
    if (landed <= 0) return;
    enemy.hp -= amount;
    this.harmDealt += (landed * enemy.spec.hp) / enemy.maxHp;
  }

  takeHarmDealt(): number {
    const harm = this.harmDealt;
    this.harmDealt = 0;
    return harm;
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
      knockX: 0,
      knockZ: 0,
      blind: 0,
      reel: 0,
      spin: 0,
      swayPhase: Math.random() * TAU,
      swayRate: randRange(SWAY_RATE_MIN, SWAY_RATE_MAX),
      bumpCooldown: 0,
      wreck: 0,
      wreckAge: 0,
      wreckSide: 1,
      tilt: 0,
      fxTimer: 0,
    };
    this.active.push(enemy);
    return enemy;
  }

  hurtArea(x: number, z: number, radius: number, damage: number): void {
    for (const enemy of this.active) {
      const reach = radius + enemy.spec.radius;
      const dx = enemy.x - x;
      const dz = enemy.z - z;
      const distSq = dx * dx + dz * dz;
      if (distSq > reach * reach) continue;
      this.hurt(enemy, damage);
      enemy.flinch = 1;
      const dist = Math.sqrt(distSq) || 1;
      const knock = BLAST_KNOCK * (1 - (0.6 * dist) / reach);
      enemy.knockX = (dx / dist) * knock;
      enemy.knockZ = (dz / dist) * knock;
    }
  }

  sweepDead(onWreck: (enemy: Enemy) => void, onKill: (enemy: Enemy) => void): void {
    for (let i = this.active.length - 1; i >= 0; i--) {
      const enemy = this.active[i];
      if (enemy.hp > 0) continue;
      this.active[i] = this.active[this.active.length - 1];
      this.active.pop();
      if (enemy.blindTimer <= 0) {
        onKill(enemy);
        continue;
      }
      this.beginWreck(enemy);
      this.wrecks.push(enemy);
      onWreck(enemy);
    }
  }

  private beginWreck(enemy: Enemy): void {
    const spec = enemy.spec;
    const swing = enemy.spin + Math.sin(enemy.swayPhase) * Math.max(enemy.blind, enemy.reel);
    enemy.wreckSide = Math.abs(swing) > 0.2 ? Math.sign(swing) : Math.random() < 0.5 ? -1 : 1;
    enemy.wreck = spec.wreckSeconds * (1 + randSigned(WRECK_SECONDS_SPREAD));
    enemy.wreckAge = 0;
    enemy.fxTimer = 0;
    enemy.flinch = 1;
  }

  update(ctx: EnemyContext): void {
    const { dt, car, stats, smoke } = ctx;
    const stir = Math.min(1, STIR_RATE * dt);
    const knockFade = Math.exp(-KNOCK_FADE * dt);
    const spinFade = Math.exp(-SPIN_FADE * dt);
    for (const enemy of this.active) {
      const spec = enemy.spec;
      enemy.knockX *= knockFade;
      enemy.knockZ *= knockFade;
      enemy.hitCooldown -= dt;
      enemy.ramCooldown -= dt;
      enemy.blindTimer -= dt;
      enemy.slowTimer -= dt;
      enemy.emberTimer -= dt;
      enemy.toxicTimer -= dt;
      enemy.flinch = Math.max(0, enemy.flinch - dt * 4);
      enemy.bumpCooldown -= dt;
      enemy.reel = Math.max(0, enemy.reel - REEL_FADE * dt);
      enemy.spin *= spinFade;
      enemy.heading += enemy.spin * dt;
      enemy.swayPhase += enemy.swayRate * dt;

      const cloud = smoke.sample(enemy.x, enemy.z, this.sample, enemy.vx, enemy.vz, stir);
      if (cloud.total > SMOKE_THRESHOLD) {
        const density = Math.min(SMOKE_DENSITY_CAP, cloud.total / SMOKE_FULL_DENSITY);
        this.hurt(enemy, stats.smokeDamage * density * dt);
        enemy.flinch = Math.max(enemy.flinch, 0.6);
        enemy.blindTimer = BLINDED_LINGER;
        const share = cloud.total * KIND_SHARE_THRESHOLD;
        if (cloud.byKind[PUFF.ash] > share) enemy.slowTimer = ASH_LINGER;
        if (cloud.byKind[PUFF.ember] > share) enemy.emberTimer = EMBER_LINGER;
        if (cloud.byKind[PUFF.toxic] > share) enemy.toxicTimer = TOXIC_LINGER;
      }
      if (enemy.toxicTimer > 0) this.hurt(enemy, stats.toxicDps * dt);
      enemy.blind = enemy.blindTimer > 0 ? Math.min(1, enemy.blind + BLIND_RISE * dt) : Math.max(0, enemy.blind - BLIND_FADE * dt);

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
      ctx.world.shove(enemy, spec.radius, spec.mass, this.shove);
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
    this.sweepDead(ctx.onWreck, ctx.onKill);
    this.updateWrecks(ctx);
  }

  private updateWrecks(ctx: EnemyContext): void {
    const { dt, car, smoke } = ctx;
    for (let i = this.wrecks.length - 1; i >= 0; i--) {
      const enemy = this.wrecks[i];
      const spec = enemy.spec;
      const bike = spec.kind === "bike";
      enemy.wreck -= dt;
      enemy.wreckAge += dt;
      enemy.hitCooldown -= dt;
      enemy.flinch = Math.max(0, enemy.flinch - dt * 4, 1 - enemy.wreck / WRECK_FUSE);

      const spinTarget = enemy.wreckSide * spec.wreckSpin * (bike ? Math.exp(-BIKE_SPIN_FADE * enemy.wreckAge) : 1);
      enemy.spin = damp(enemy.spin, spinTarget, WRECK_SPIN_UP, dt);
      enemy.heading += enemy.spin * dt;

      const veer = enemy.wreckSide * WRECK_VEER * Math.exp(-WRECK_VEER_FADE * enemy.wreckAge) * dt;
      const cos = Math.cos(veer);
      const sin = Math.sin(veer);
      const vx = enemy.vx * cos + enemy.vz * sin;
      const vz = enemy.vz * cos - enemy.vx * sin;
      const fx = Math.sin(enemy.heading);
      const fz = Math.cos(enemy.heading);
      const forward = (vx * fx + vz * fz) * Math.exp(-(bike ? BIKE_SLIDE_DRAG : WRECK_ROLL_DRAG) * dt);
      const slip = (vx * fz - vz * fx) * Math.exp(-(bike ? BIKE_SLIDE_DRAG : WRECK_SLIDE_DRAG) * dt);
      enemy.vx = fx * forward + fz * slip;
      enemy.vz = fz * forward - fx * slip;
      enemy.x += enemy.vx * dt;
      enemy.z += enemy.vz * dt;
      enemy.tilt = bike
        ? damp(enemy.tilt, enemy.wreckSide * BIKE_LAY_ANGLE, BIKE_LAY_RATE, dt)
        : damp(enemy.tilt, clamp(-slip * WRECK_TILT_PER_SLIP, -WRECK_TILT_MAX, WRECK_TILT_MAX), 9, dt);

      if (ctx.world.resolve(enemy, spec.radius, this.contact).hit) {
        const into = enemy.vx * this.contact.nx + enemy.vz * this.contact.nz;
        if (into < 0) {
          enemy.vx -= into * this.contact.nx * 1.2;
          enemy.vz -= into * this.contact.nz * 1.2;
          if (into < -WRECK_CRASH_SPEED) enemy.wreck = 0;
        }
      }
      ctx.world.shove(enemy, spec.radius, spec.mass, this.shove);
      this.collideWithCar(enemy, ctx, true);
      this.bumpInto(enemy, ctx);

      enemy.fxTimer -= dt;
      if (enemy.fxTimer <= 0) {
        enemy.fxTimer = WRECK_FX_INTERVAL;
        if (Math.abs(enemy.x - car.x) < DUST_VISIBLE_RANGE && Math.abs(enemy.z - car.z) < DUST_VISIBLE_RANGE) {
          const speed = Math.hypot(enemy.vx, enemy.vz);
          const x = enemy.x + randSigned(spec.halfLength) * fx + randSigned(spec.halfWidth) * fz;
          const z = enemy.z + randSigned(spec.halfLength) * fz - randSigned(spec.halfWidth) * fx;
          const ground = this.groundAt(x, z);
          if (speed > 4) smoke.emit(PUFF.dust, x, ground + 0.3, z, enemy.vx * 0.15, 1, enemy.vz * 0.15, 0.5 + spec.radius * 0.3, 1.1, randRange(0.9, 1.5), 0.5, 0.2);
          const cooked = enemy.wreckAge / (enemy.wreckAge + Math.max(0, enemy.wreck));
          if (Math.random() < cooked) {
            const burning = enemy.wreck < WRECK_FUSE || Math.random() < cooked * 0.3;
            smoke.emit(burning ? PUFF.fire : PUFF.soot, enemy.x, ground + 0.6 + spec.radius * 0.3, enemy.z, enemy.vx * 0.3, randRange(1.5, 3.5), enemy.vz * 0.3, 0.3 + spec.radius * 0.18, 1.2, burning ? randRange(0.25, 0.45) : randRange(0.6, 1), 0.8, burning ? 1.5 : 0.8);
          }
          if (bike && speed > 3) ctx.onScrape(enemy);
        }
      }

      if (enemy.wreck > 0) continue;
      this.wrecks[i] = this.wrecks[this.wrecks.length - 1];
      this.wrecks.pop();
      ctx.onKill(enemy);
    }
  }

  private bumpInto(wreck: Enemy, ctx: EnemyContext): void {
    for (const other of this.active) {
      const reach = (wreck.spec.radius + other.spec.radius) * 0.9;
      const dx = other.x - wreck.x;
      if (dx > reach || dx < -reach) continue;
      const dz = other.z - wreck.z;
      const distSq = dx * dx + dz * dz;
      if (distSq >= reach * reach) continue;
      const dist = Math.sqrt(distSq) || 0.001;
      const nx = dx / dist;
      const nz = dz / dist;
      const share = wreck.spec.mass / (wreck.spec.mass + other.spec.mass);
      const overlap = reach - dist;
      other.x += nx * overlap * share;
      other.z += nz * overlap * share;
      wreck.x -= nx * overlap * (1 - share);
      wreck.z -= nz * overlap * (1 - share);
      if (other.bumpCooldown > 0) continue;
      other.bumpCooldown = BUMP_COOLDOWN;
      const closing = Math.max(0, (wreck.vx - other.vx) * nx + (wreck.vz - other.vz) * nz);
      const strength = Math.min(1, share * 2);
      const kick = (BUMP_SHOVE + closing) * strength;
      other.vx += nx * kick;
      other.vz += nz * kick;
      wreck.vx -= nx * closing * (1 - share);
      wreck.vz -= nz * closing * (1 - share);
      const side = Math.sign(nx * Math.cos(other.heading) - nz * Math.sin(other.heading)) || 1;
      other.spin = clamp(other.spin + side * BUMP_SPIN * strength, -BUMP_SPIN, BUMP_SPIN);
      other.reel = Math.max(other.reel, strength);
      other.flinch = 1;
      this.hurt(other, wreck.spec.damage * BUMP_DAMAGE);
      ctx.onBump(other, strength);
    }
  }

  render(time: number): void {
    for (const batch of Object.values(this.batches)) batch.begin();
    this.riders.begin();
    this.arms.begin();
    for (const enemy of this.active) this.draw(enemy, time);
    for (const enemy of this.wrecks) this.drawWreck(enemy, time);
    for (const batch of Object.values(this.batches)) batch.commit();
    this.riders.commit();
    this.arms.commit();
  }

  private draw(enemy: Enemy, time: number): void {
    const spec = enemy.spec;
    const bike = spec.kind === "bike";
    const loose = Math.max(enemy.blind, enemy.reel) * spec.sway;
    const yaw = enemy.heading + Math.sin(enemy.swayPhase + 1.3) * SWAY_FISHTAIL * loose;
    const slope = sampleSlope(enemy.x, enemy.z, yaw, spec.halfLength, spec.halfWidth, this.slope);
    const shake = enemy.flinch * 0.07 * Math.sin(time * 55 + enemy.flank * 9);
    const lean = clamp((enemy.vx * Math.cos(enemy.heading) - enemy.vz * Math.sin(enemy.heading)) * 0.02, -0.3, 0.3);
    const sway = Math.sin(enemy.swayPhase) * (bike ? BIKE_SWAY_ROLL : CAR_SWAY_ROLL) * loose;
    const roll = slope.roll + lean + sway + shake;
    this.batches[spec.kind].push(enemy.x, slope.height, enemy.z, yaw, slope.pitch, roll, 1 + shake, 1 - shake, 1 + shake);
    if (!bike) return;

    const blind = smoothstep(0, 1, enemy.blind);
    const wiggle = time * 11 + enemy.flank * 9;
    composeTransform(this.mount, enemy.x, slope.height, enemy.z, yaw, slope.pitch, roll, 1, 1, 1);
    this.riders.pushUnder(
      this.mount,
      RIDER_SEAT[0],
      RIDER_SEAT[1],
      RIDER_SEAT[2],
      Math.sin(wiggle * 0.73) * RIDER_WIGGLE_YAW * blind,
      RIDER_RECOIL * blind,
      Math.sin(wiggle) * RIDER_WIGGLE_ROLL * blind,
      1,
      1,
      1,
      this.seat,
    );
    for (const side of [-1, 1]) {
      this.arms.pushUnder(
        this.seat,
        side * RIDER_SHOULDER[0],
        RIDER_SHOULDER[1],
        RIDER_SHOULDER[2],
        side * lerp(ARM_GRIP.yaw, ARM_COVER.yaw, blind),
        lerp(ARM_GRIP.pitch, ARM_COVER.pitch, blind) + (Math.sin(wiggle * 1.7 + side) * ARM_RUB - side * 0.07) * blind,
        0,
        1,
        1,
        lerp(ARM_GRIP.length, ARM_COVER.length, blind),
      );
    }
  }

  private drawWreck(enemy: Enemy, time: number): void {
    const spec = enemy.spec;
    const slope = sampleSlope(enemy.x, enemy.z, enemy.heading, spec.halfLength, spec.halfWidth, this.slope);
    const shake = enemy.flinch * 0.07 * Math.sin(time * 55 + enemy.flank * 9);
    const lift = spec.halfWidth * Math.abs(Math.sin(enemy.tilt));
    this.batches[spec.kind].push(
      enemy.x,
      slope.height + lift,
      enemy.z,
      enemy.heading,
      slope.pitch,
      slope.roll + enemy.tilt + shake,
      1 + shake,
      1 - shake,
      1 + shake,
    );
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
    const loose = Math.max(enemy.blind, enemy.reel) * spec.sway;
    const desired = Math.atan2(targetX - enemy.x, targetZ - enemy.z) + Math.sin(enemy.swayPhase) * SWAY_ANGLE * loose;
    const error = wrapAngle(desired - enemy.heading);
    const turn = spec.turn * dt * (1 - REEL_STEER_LOSS * enemy.reel);
    enemy.heading += clamp(error, -turn, turn);

    const fx = Math.sin(enemy.heading);
    const fz = Math.cos(enemy.heading);
    let cap = spec.speed;
    if (enemy.blindTimer > 0) cap *= BLINDED_SPEED_FACTOR;
    if (enemy.slowTimer > 0) cap *= 1 - stats.ashSlow;
    if (Math.abs(error) > 1.2) cap *= 0.65;
    const forward = moveToward(enemy.vx * fx + enemy.vz * fz, cap, spec.accel * dt);
    const grip = spec.grip * (1 - SWAY_GRIP_LOSS * loose);
    const sideSlip = (enemy.vx * fz - enemy.vz * fx + Math.cos(enemy.swayPhase) * SWAY_KICK * loose * dt) * Math.exp(-grip * dt);
    enemy.vx = fx * forward + fz * sideSlip;
    enemy.vz = fz * forward - fx * sideSlip;
  }

  private collideWithCar(enemy: Enemy, ctx: EnemyContext, wrecked = false): void {
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
    if (wrecked) return;

    if (stats.ramDamage > 0 && car.speed > RAM_MIN_SPEED && enemy.ramCooldown <= 0) {
      enemy.ramCooldown = RAM_COOLDOWN;
      this.hurt(enemy, stats.ramDamage * (car.speed / 20));
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

const SPAWN_RING_MIN = 115;
const SPAWN_RING_MAX = 140;
const RECYCLE_DISTANCE = 215;
const WAVE_FIRST_DELAY = 0.6;
const WAVE_INTERVAL_START = 5.4;
const WAVE_INTERVAL_MIN = 3.0;
const WAVE_INTERVAL_RAMP = 300;
const WAVE_BURST_DURATION = 1.6;
const WAVE_MIN_STEP = 0.06;
const WAVE_MAX_STEP = 0.28;
const WAVE_TWO_SIDE_SHARE = 0.75;
const WAVE_STRAGGLER_CHANCE = 0.1;
const WAVE_MIN_SHIFT = 0.7;
const STRAY_INTERVAL_MIN = 7;
const STRAY_INTERVAL_MAX = 13;
const WAR_PARTY_INTERVAL = 60;
const WAR_PARTY_WARNING = 4;
const WAR_PARTY_SPREAD = 0.22;
const BOSS_INTERVAL = 150;
const BOSS_WARNING = 6;
const THREAT_ARRIVAL_DISTANCE = 42;
const AHEAD_BIAS = 0.55;
const HP_GROWTH_SECONDS = 140;
const DAMAGE_GROWTH_SECONDS = 420;

interface WaveSector {
  center: number;
  spread: number;
}

// Corner sectors span two adjacent sides plus the corner between them (e.g. bottom, bottom-left, left).
const CORNER_SECTORS: readonly WaveSector[] = [
  { center: Math.PI * 0.25, spread: Math.PI * 0.25 },
  { center: Math.PI * 0.75, spread: Math.PI * 0.25 },
  { center: -Math.PI * 0.75, spread: Math.PI * 0.25 },
  { center: -Math.PI * 0.25, spread: Math.PI * 0.25 },
];

// Single-side sectors focus a wave onto one edge of the screen.
const SIDE_SECTORS: readonly WaveSector[] = [
  { center: 0, spread: 0.42 },
  { center: Math.PI * 0.5, spread: 0.42 },
  { center: Math.PI, spread: 0.42 },
  { center: -Math.PI * 0.5, spread: 0.42 },
];

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
  private waveBearing = CORNER_SECTORS[0].center;
  private waveSpread = CORNER_SECTORS[0].spread;
  private waveTimer = WAVE_FIRST_DELAY;
  private waveSpawnTimer = 0;
  private waveStep = 0.2;
  private waveTotal = 0;
  private readonly waveAngles: number[] = [];
  private strayTimer = randRange(STRAY_INTERVAL_MIN, STRAY_INTERVAL_MAX);
  private nextWarParty = WAR_PARTY_INTERVAL;
  private nextBoss = BOSS_INTERVAL;

  reset(): void {
    this.threats.length = 0;
    const initial = CORNER_SECTORS[Math.floor(Math.random() * CORNER_SECTORS.length)];
    this.waveBearing = initial.center;
    this.waveSpread = initial.spread;
    this.waveTimer = WAVE_FIRST_DELAY;
    this.waveSpawnTimer = 0;
    this.waveStep = 0.2;
    this.waveTotal = 0;
    this.waveAngles.length = 0;
    this.strayTimer = randRange(STRAY_INTERVAL_MIN, STRAY_INTERVAL_MAX);
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
      const angle = this.waveBearing + randSigned(this.waveSpread);
      const distance = randRange(SPAWN_RING_MIN, SPAWN_RING_MAX);
      enemy.x = car.x + Math.sin(angle) * distance;
      enemy.z = car.z + Math.cos(angle) * distance;
      enemy.heading = angle + Math.PI;
    }

    this.updateWaves(dt, time, desired, car, enemies, hpScale);
    this.updateStragglers(dt, time, desired, car, enemies, hpScale);

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

  private updateWaves(dt: number, time: number, desired: number, car: CarBody, enemies: EnemySystem, hpScale: number): void {
    if (this.waveAngles.length > 0) {
      this.waveSpawnTimer -= dt;
      while (this.waveSpawnTimer <= 0 && this.waveAngles.length > 0) {
        this.waveSpawnTimer += this.waveStep;
        const baseAngle = this.waveAngles.pop()!;
        if (enemies.active.length >= MAX_ENEMIES - 15) continue;
        const straggler = this.waveTotal >= 4 && Math.random() < WAVE_STRAGGLER_CHANCE;
        const angle = straggler ? this.pickStragglerAngle() : baseAngle;
        this.spawnAt(enemies, this.pickKind(time), car, angle, hpScale);
      }
      return;
    }

    this.waveTimer -= dt;
    if (enemies.active.length <= Math.max(1, Math.floor(desired * 0.2))) {
      this.waveTimer = Math.min(this.waveTimer, 1.0);
    }
    if (this.waveTimer > 0) return;

    const deficit = Math.ceil(desired - enemies.active.length);
    const minWave = Math.min(3, Math.ceil(desired));
    if (deficit < minWave && enemies.active.length > 0) {
      this.waveTimer = 0.5;
      return;
    }

    const room = MAX_ENEMIES - 20 - enemies.active.length;
    if (room <= 0) {
      this.waveTimer = 0.6;
      return;
    }

    const sector = this.pickNextSector();
    this.waveBearing = sector.center;
    this.waveSpread = sector.spread;

    const targetWave = Math.max(minWave, Math.min(deficit, Math.ceil(desired * 0.65 + 1)));
    const count = clamp(targetWave, 1, Math.min(22, room));
    this.waveTotal = count;
    this.waveStep = clamp(WAVE_BURST_DURATION / count, WAVE_MIN_STEP, WAVE_MAX_STEP);
    this.waveSpawnTimer = 0;

    // Stratify across the 1-2 side sector so the wave spans its edges cleanly, then shuffle arrival order.
    this.waveAngles.length = 0;
    const jitter = 0.5 / count;
    for (let i = 0; i < count; i++) {
      const slot = clamp(((i + 0.5) / count) * 2 - 1 + randSigned(jitter), -1, 1);
      this.waveAngles.push(this.waveBearing + slot * this.waveSpread);
    }
    for (let i = this.waveAngles.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      const tmp = this.waveAngles[i];
      this.waveAngles[i] = this.waveAngles[j];
      this.waveAngles[j] = tmp;
    }

    const ramp = clamp(time / WAVE_INTERVAL_RAMP, 0, 1);
    this.waveTimer = lerp(WAVE_INTERVAL_START, WAVE_INTERVAL_MIN, ramp);
  }

  private updateStragglers(dt: number, time: number, desired: number, car: CarBody, enemies: EnemySystem, hpScale: number): void {
    this.strayTimer -= dt;
    if (this.strayTimer > 0) return;
    this.strayTimer = randRange(STRAY_INTERVAL_MIN, STRAY_INTERVAL_MAX);
    if (enemies.active.length >= desired) return;
    this.spawnAt(enemies, this.pickKind(time), car, this.pickStragglerAngle(), hpScale);
  }

  private pickNextSector(): WaveSector {
    const pool = Math.random() < WAVE_TWO_SIDE_SHARE ? CORNER_SECTORS : SIDE_SECTORS;
    const fresh = pool.filter((sector) => Math.abs(wrapAngle(sector.center - this.waveBearing)) > WAVE_MIN_SHIFT);
    const list = fresh.length > 0 ? fresh : pool;
    return list[Math.floor(Math.random() * list.length)];
  }

  private pickStragglerAngle(): number {
    const clearHalf = this.waveSpread + 0.65;
    const span = Math.max(0.4, TAU - clearHalf * 2);
    return wrapAngle(this.waveBearing + clearHalf + Math.random() * span);
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
