import { clamp, lerp, moveToward, saturate } from "./math";

export interface CarTuning {
  engineAccel: number;
  topSpeed: number;
  gripFront: number;
  gripRear: number;
  steerLockLow: number;
  steerLockHigh: number;
  steerSpeed: number;
  yawResponse: number;
}

export interface CarInput {
  throttle: number;
  brake: number;
  steer: number;
  handbrake: boolean;
  boost: number;
}

export const BASE_TUNING: CarTuning = {
  engineAccel: 13,
  topSpeed: 33,
  gripFront: 12.5,
  gripRear: 11,
  steerLockLow: 0.6,
  steerLockHigh: 0.26,
  steerSpeed: 4.2,
  yawResponse: 1,
};

export const AXLE_FRONT = 1.25;
export const AXLE_REAR = 1.35;
export const HALF_TRACK = 0.8;

const WHEELBASE = AXLE_FRONT + AXLE_REAR;
const WEIGHT_FRONT = AXLE_REAR / WHEELBASE;
const WEIGHT_REAR = AXLE_FRONT / WHEELBASE;
const SUBSTEP = 1 / 240;
const LOW_SPEED_SOFTENING = 1.5;
const TYRE_STIFFNESS = 6;
const TYRE_SHAPE = 1.6;
const TRACTION_LIMIT = 15;
const BRAKE_DECEL = 17;
const LOCKED_REAR_FRICTION = 0.7;
const SELF_ALIGN = 1;
const MAX_STEER_ANGLE = 1.1;
const YAW_DAMPING = 0.9;
const REVERSE_SPEED_FRACTION = 0.3;
const BRAKE_REAR_UNLOAD = 0.3;
const LIFT_OFF_REAR_UNLOAD = 0.1;
const ROLLING_DRAG = 0.5;
const LINEAR_DRAG = 0.012;
const ENGINE_BRAKING = 1.2;
const DRIFT_ANGLE_LIMIT = 0.8;
const SLIDE_SCRUB = 0.38;
const HANDBRAKE_DRIFT_ANGLE_LIMIT = 1.25;
const DRIFT_CATCH_STIFFNESS = 16;
const DRIFT_CATCH_DAMPING = 3;
const NITROUS_THRUST = 21;
const NITROUS_TOP_SPEED = 0.45;
const OVERSPEED_DRAG = 1.6;

function tyreCurve(slipAngle: number): number {
  return Math.sin(TYRE_SHAPE * Math.atan(TYRE_STIFFNESS * slipAngle));
}

export class CarBody {
  x = 0;
  z = 0;
  heading = 0;
  vx = 0;
  vz = 0;
  yawRate = 0;
  steerAngle = 0;

  speed = 0;
  forwardSpeed = 0;
  lateralSpeed = 0;
  rearSlipSpeed = 0;
  frontSlipSpeed = 0;
  burnout = 0;
  longAccel = 0;
  latAccel = 0;
  private leftover = 0;

  reset(): void {
    this.x = this.z = this.heading = this.vx = this.vz = this.yawRate = this.steerAngle = 0;
    this.speed = this.forwardSpeed = this.lateralSpeed = 0;
    this.rearSlipSpeed = this.frontSlipSpeed = this.burnout = this.longAccel = this.latAccel = 0;
    this.leftover = 0;
  }

  get driftAngle(): number {
    return Math.atan2(this.lateralSpeed, Math.abs(this.forwardSpeed) + 0.5);
  }

  step(dt: number, input: CarInput, tuning: CarTuning): void {
    this.leftover += dt;
    while (this.leftover >= SUBSTEP) {
      this.substep(SUBSTEP, input, tuning);
      this.leftover -= SUBSTEP;
    }
  }

  private substep(dt: number, input: CarInput, tuning: CarTuning): void {
    const fx = Math.sin(this.heading);
    const fz = Math.cos(this.heading);
    const rx = fz;
    const rz = -fx;
    const vF = this.vx * fx + this.vz * fz;
    const vR = this.vx * rx + this.vz * rz;
    const w = this.yawRate;
    const absF = Math.abs(vF);
    const direction = vF >= 0 ? 1 : -1;

    const frontLat = vR + AXLE_FRONT * w;
    const rearLat = vR - AXLE_REAR * w;

    const speedFraction = saturate(absF / tuning.topSpeed);
    const lock = lerp(tuning.steerLockLow, tuning.steerLockHigh, speedFraction);
    const alignAngle = vF > 2 ? Math.atan2(frontLat, absF + 1) : 0;
    const steerTarget = clamp(input.steer * lock + SELF_ALIGN * alignAngle, -MAX_STEER_ANGLE, MAX_STEER_ANGLE);
    this.steerAngle = moveToward(this.steerAngle, steerTarget, tuning.steerSpeed * dt);

    const cd = Math.cos(this.steerAngle);
    const sd = Math.sin(this.steerAngle);
    const wheelLat = -sd * vF + cd * frontLat;
    const wheelLong = cd * vF + sd * frontLat;
    const frontSlipAngle = Math.atan2(wheelLat, Math.abs(wheelLong) + LOW_SPEED_SOFTENING);
    const frontForce = -tuning.gripFront * WEIGHT_FRONT * tyreCurve(frontSlipAngle);

    const boost = saturate(input.boost);
    const throttle = Math.max(input.throttle, boost);
    const speedLimit = tuning.topSpeed * (1 + NITROUS_TOP_SPEED * boost);
    const headroom = vF > 0 ? Math.max(0, 1 - (vF / speedLimit) ** 2) : 1;
    const reversing = input.brake > 0 && throttle <= 0 && vF < 1.5;
    let engine = 0;
    let brake = 0;
    if (reversing) {
      const reverseLimit = tuning.topSpeed * REVERSE_SPEED_FRACTION;
      engine = -input.brake * tuning.engineAccel * 0.6 * saturate(1 + vF / reverseLimit);
    } else {
      engine = throttle * tuning.engineAccel * headroom;
      brake = input.brake;
    }
    if (input.handbrake) engine = 0;

    const tractionUse = Math.min(0.97, Math.abs(engine) / TRACTION_LIMIT);
    let rearGripFactor = Math.sqrt(1 - tractionUse * tractionUse);
    rearGripFactor *= 1 - BRAKE_REAR_UNLOAD * brake * saturate(absF / 6);
    if (throttle <= 0.05 && !reversing) rearGripFactor *= 1 - LIFT_OFF_REAR_UNLOAD;

    let rearLatForce: number;
    let rearLongForce = 0;
    if (input.handbrake) {
      const rearSpeed = Math.hypot(vF, rearLat);
      const scale = (LOCKED_REAR_FRICTION * tuning.gripRear * WEIGHT_REAR * saturate(rearSpeed / 1.5)) / (rearSpeed + 1e-4);
      rearLatForce = -rearLat * scale;
      rearLongForce = -vF * scale;
    } else {
      const rearSlipAngle = Math.atan2(rearLat, absF + LOW_SPEED_SOFTENING);
      rearLatForce = -tuning.gripRear * WEIGHT_REAR * rearGripFactor * tyreCurve(rearSlipAngle);
    }

    const brakeForce = -direction * brake * BRAKE_DECEL * saturate(absF);
    const coasting = throttle <= 0.05 && !reversing ? ENGINE_BRAKING : 0;
    const dragForce = -((ROLLING_DRAG + coasting) * Math.tanh(vF) + LINEAR_DRAG * vF + OVERSPEED_DRAG * Math.max(0, vF - speedLimit));
    const forceLong = engine + boost * NITROUS_THRUST * headroom + brakeForce + dragForce + rearLongForce - frontForce * sd;
    const forceLat = frontForce * cd + rearLatForce;

    const yawAccel =
      ((AXLE_FRONT * frontForce * cd - AXLE_REAR * rearLatForce) / (AXLE_FRONT * AXLE_REAR)) * tuning.yawResponse -
      w * YAW_DAMPING +
      this.driftCatch(vF, vR, w, input.handbrake);

    const scrub = input.handbrake ? 0 : (SLIDE_SCRUB * Math.max(0, Math.abs(rearLat) - 2)) / (Math.hypot(vF, vR) + 0.5);
    this.vx += (fx * forceLong + rx * forceLat - this.vx * scrub) * dt;
    this.vz += (fz * forceLong + rz * forceLat - this.vz * scrub) * dt;
    this.yawRate += yawAccel * dt;
    this.heading += this.yawRate * dt;
    this.x += this.vx * dt;
    this.z += this.vz * dt;

    this.speed = Math.hypot(this.vx, this.vz);
    this.forwardSpeed = vF;
    this.lateralSpeed = vR;
    this.rearSlipSpeed = input.handbrake ? Math.hypot(vF, rearLat) : Math.abs(rearLat);
    this.frontSlipSpeed = Math.abs(wheelLat);
    this.burnout = input.handbrake ? 0 : tractionUse * throttle * saturate(1 - absF / (tuning.topSpeed * 0.6));
    this.longAccel = lerp(this.longAccel, forceLong, 0.02);
    this.latAccel = lerp(this.latAccel, forceLat, 0.02);
  }

  private driftCatch(vF: number, vR: number, yawRate: number, handbrake: boolean): number {
    const speed = Math.hypot(vF, vR);
    if (speed < 3) return 0;
    const slipAngle = Math.atan2(vR, vF);
    const limit = handbrake ? HANDBRAKE_DRIFT_ANGLE_LIMIT : DRIFT_ANGLE_LIMIT;
    const excess = Math.abs(slipAngle) - limit;
    if (excess <= 0 || Math.abs(slipAngle) > Math.PI * 0.75) return 0;
    const authority = saturate(speed / 8);
    const swingingOut = Math.sign(slipAngle) * yawRate < 0 ? 1 : 0;
    return authority * (Math.sign(slipAngle) * excess * DRIFT_CATCH_STIFFNESS - yawRate * DRIFT_CATCH_DAMPING * swingingOut * saturate(excess * 4));
  }

  smokeIntensity(): number {
    const slide = saturate((this.rearSlipSpeed - 2) / 7);
    const spin = 0.7 * this.burnout * this.burnout;
    return Math.min(1.5, slide + spin);
  }
}
