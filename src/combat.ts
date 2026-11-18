import { Color3, Material, Scene, StandardMaterial } from "@babylonjs/core";
import type { GameAudio } from "./audio";
import type { EnemySystem } from "./enemies";
import { InstanceBatch } from "./kit";
import { randRange, TAU } from "./math";
import { buildBulletModel, buildRepairModel, buildScrapModel } from "./models";
import { PALETTE } from "./palette";
import { groundHeight } from "./terrain";
import type { Stats } from "./upgrades";
import type { CarBody } from "./vehicle";

const MAX_BULLETS = 400;
const BULLET_SPEED = 58;
const BULLET_LIFE = 0.8;
const BULLET_RADIUS = 0.35;
const SPIRAL_STEP = 0.41;
const MUZZLE_HEIGHT = 1.9;
const MUZZLE_OFFSET = 1.2;

interface Bullet {
  x: number;
  y: number;
  z: number;
  vx: number;
  vz: number;
  life: number;
  damage: number;
}

export class GunSystem {
  angle = 0;
  private readonly bullets: Bullet[] = [];
  private readonly batch: InstanceBatch;
  private cooldown = 0;

  constructor(scene: Scene) {
    const mesh = buildBulletModel(scene);
    const material = new StandardMaterial("bullet", scene);
    material.disableLighting = true;
    material.emissiveColor = new Color3(1, 0.86, 0.4);
    mesh.material = material;
    this.batch = new InstanceBatch(mesh, MAX_BULLETS);
  }

  clear(): void {
    this.bullets.length = 0;
    this.cooldown = 0;
  }

  update(dt: number, car: CarBody, stats: Stats, enemies: EnemySystem, audio: GameAudio): void {
    if (stats.gunBarrels > 0) {
      this.cooldown -= dt;
      while (this.cooldown <= 0) {
        this.cooldown += 1 / stats.gunFireRate;
        this.angle = (this.angle + SPIRAL_STEP) % TAU;
        const baseHeight = groundHeight(car.x, car.z) + MUZZLE_HEIGHT;
        for (let barrel = 0; barrel < stats.gunBarrels; barrel++) {
          if (this.bullets.length >= MAX_BULLETS) break;
          const direction = this.angle + (barrel * TAU) / stats.gunBarrels;
          const dx = Math.sin(direction);
          const dz = Math.cos(direction);
          this.bullets.push({
            x: car.x + dx * MUZZLE_OFFSET,
            y: baseHeight,
            z: car.z + dz * MUZZLE_OFFSET,
            vx: dx * BULLET_SPEED + car.vx * 0.5,
            vz: dz * BULLET_SPEED + car.vz * 0.5,
            life: BULLET_LIFE,
            damage: stats.gunDamage,
          });
        }
        audio.shot();
      }
    }

    for (let i = this.bullets.length - 1; i >= 0; i--) {
      const bullet = this.bullets[i];
      bullet.life -= dt;
      bullet.x += bullet.vx * dt;
      bullet.z += bullet.vz * dt;
      let spent = bullet.life <= 0;
      if (!spent) {
        for (const enemy of enemies.active) {
          const reach = enemy.spec.radius + BULLET_RADIUS;
          const dx = enemy.x - bullet.x;
          const dz = enemy.z - bullet.z;
          if (dx * dx + dz * dz > reach * reach) continue;
          enemies.hurt(enemy, bullet.damage);
          enemy.flinch = 1;
          spent = true;
          break;
        }
      }
      if (spent) {
        this.bullets[i] = this.bullets[this.bullets.length - 1];
        this.bullets.pop();
      }
    }
  }

  render(): void {
    this.batch.begin();
    for (const bullet of this.bullets) {
      this.batch.push(bullet.x, bullet.y, bullet.z, Math.atan2(bullet.vx, bullet.vz), 0, 0, 1, 1, 1);
    }
    this.batch.commit();
  }
}

export type PickupKind = "scrap" | "repair";

interface Pickup {
  kind: PickupKind;
  x: number;
  z: number;
  vx: number;
  vz: number;
  value: number;
  phase: number;
  attracted: boolean;
}

export const REPAIR_DROP_VALUE = 20;
export const REPAIR_CRATE_VALUE = 35;
const MAX_PICKUPS = 500;
const COLLECT_RADIUS = 2.2;
const MAGNET_ACCEL = 90;
const MAGNET_TOP_SPEED = 55;
const SCATTER_FRICTION = 3.5;
const HOVER_HEIGHT = 0.7;

export class PickupSystem {
  private readonly items: Pickup[] = [];
  private readonly scrapBatch: InstanceBatch;
  private readonly repairBatch: InstanceBatch;

  constructor(scene: Scene, material: Material) {
    const scrap = buildScrapModel(scene);
    const scrapMaterial = new StandardMaterial("scrap", scene);
    scrapMaterial.emissiveColor = PALETTE.scrap.scale(0.45);
    scrapMaterial.specularColor = Color3.Black();
    scrap.material = scrapMaterial;
    this.scrapBatch = new InstanceBatch(scrap, MAX_PICKUPS);
    const repair = buildRepairModel(scene);
    repair.material = material;
    this.repairBatch = new InstanceBatch(repair, 32);
  }

  clear(): void {
    this.items.length = 0;
  }

  drop(kind: PickupKind, x: number, z: number, pieces: number, valueEach: number): void {
    for (let i = 0; i < pieces; i++) {
      if (this.items.length >= MAX_PICKUPS) {
        const merged = this.items.find((item) => item.kind === kind);
        if (merged) merged.value += valueEach;
        continue;
      }
      const angle = Math.random() * TAU;
      const speed = randRange(2, 9);
      this.items.push({
        kind,
        x,
        z,
        vx: Math.sin(angle) * speed,
        vz: Math.cos(angle) * speed,
        value: valueEach,
        phase: Math.random() * TAU,
        attracted: false,
      });
    }
  }

  place(kind: PickupKind, x: number, z: number, value: number): void {
    if (this.items.length >= MAX_PICKUPS) return;
    this.items.push({ kind, x, z, vx: 0, vz: 0, value, phase: Math.random() * TAU, attracted: false });
  }

  update(dt: number, car: CarBody, magnetRadius: number, onCollect: (kind: PickupKind, value: number) => void): void {
    const friction = Math.exp(-SCATTER_FRICTION * dt);
    for (let i = this.items.length - 1; i >= 0; i--) {
      const item = this.items[i];
      const dx = car.x - item.x;
      const dz = car.z - item.z;
      const distance = Math.hypot(dx, dz) || 0.001;
      if (distance < COLLECT_RADIUS) {
        onCollect(item.kind, item.value);
        this.items[i] = this.items[this.items.length - 1];
        this.items.pop();
        continue;
      }
      if (distance < magnetRadius) item.attracted = true;
      if (item.attracted) {
        item.vx += (dx / distance) * MAGNET_ACCEL * dt;
        item.vz += (dz / distance) * MAGNET_ACCEL * dt;
        const speed = Math.hypot(item.vx, item.vz);
        const along = (item.vx * dx + item.vz * dz) / distance;
        const steerToCar = Math.min(1, 6 * dt);
        item.vx += ((dx / distance) * Math.max(along, speed) - item.vx) * steerToCar;
        item.vz += ((dz / distance) * Math.max(along, speed) - item.vz) * steerToCar;
        if (speed > MAGNET_TOP_SPEED + car.speed) {
          item.vx *= (MAGNET_TOP_SPEED + car.speed) / speed;
          item.vz *= (MAGNET_TOP_SPEED + car.speed) / speed;
        }
      } else {
        item.vx *= friction;
        item.vz *= friction;
      }
      item.x += item.vx * dt;
      item.z += item.vz * dt;
    }
  }

  render(time: number): void {
    this.scrapBatch.begin();
    this.repairBatch.begin();
    for (const item of this.items) {
      const y = groundHeight(item.x, item.z) + HOVER_HEIGHT + Math.sin(time * 3 + item.phase) * 0.15;
      const spin = time * 2.4 + item.phase;
      if (item.kind === "scrap") {
        const size = item.value >= 5 ? 1.5 : item.value >= 2 ? 1.15 : 0.9;
        this.scrapBatch.push(item.x, y, item.z, spin, 0.4, 0, size, size, size);
      } else {
        const size = item.value > REPAIR_DROP_VALUE ? 2 : 1.2;
        this.repairBatch.push(item.x, y + 0.2, item.z, spin, 0, 0, size, size, size);
      }
    }
    this.scrapBatch.commit();
    this.repairBatch.commit();
  }
}
