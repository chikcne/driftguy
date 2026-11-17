export const TAU = Math.PI * 2;

export function clamp(value: number, min: number, max: number): number {
  return value < min ? min : value > max ? max : value;
}

export function saturate(value: number): number {
  return value < 0 ? 0 : value > 1 ? 1 : value;
}

export function lerp(from: number, to: number, t: number): number {
  return from + (to - from) * t;
}

export function smoothstep(edge0: number, edge1: number, value: number): number {
  const t = saturate((value - edge0) / (edge1 - edge0));
  return t * t * (3 - 2 * t);
}

export function damp(from: number, to: number, rate: number, dt: number): number {
  return lerp(from, to, 1 - Math.exp(-rate * dt));
}

export function moveToward(from: number, to: number, maxDelta: number): number {
  if (Math.abs(to - from) <= maxDelta) return to;
  return from + Math.sign(to - from) * maxDelta;
}

export function wrapAngle(angle: number): number {
  let wrapped = (angle + Math.PI) % TAU;
  if (wrapped < 0) wrapped += TAU;
  return wrapped - Math.PI;
}

export function randRange(min: number, max: number): number {
  return min + Math.random() * (max - min);
}

export function randSigned(magnitude: number): number {
  return (Math.random() * 2 - 1) * magnitude;
}

export function hash2(a: number, b: number): number {
  let h = (Math.imul(a | 0, 374761393) + Math.imul(b | 0, 668265263)) | 0;
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  return ((h ^ (h >>> 16)) >>> 0) / 4294967296;
}

export type Rng = () => number;

export function seededRng(seed: number): Rng {
  let state = seed | 0;
  return () => {
    state = (state + 0x6d2b79f5) | 0;
    let t = Math.imul(state ^ (state >>> 15), 1 | state);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
