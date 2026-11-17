import { clamp, lerp } from "./math";

const MASTER_VOLUME = 0.45;
const GEAR_COUNT = 4;

export class GameAudio {
  private context: AudioContext | null = null;
  private master: GainNode | null = null;
  private engineLow: OscillatorNode | null = null;
  private engineHigh: OscillatorNode | null = null;
  private engineGain: GainNode | null = null;
  private engineFilter: BiquadFilterNode | null = null;
  private skidGain: GainNode | null = null;
  private skidFilter: BiquadFilterNode | null = null;
  private noise: AudioBuffer | null = null;
  private muted = false;
  private lastShot = 0;

  unlock(): void {
    if (this.context) {
      if (this.context.state === "suspended") void this.context.resume();
      return;
    }
    const Context = window.AudioContext;
    if (!Context) return;
    const context = new Context();
    this.context = context;
    this.master = context.createGain();
    this.master.gain.value = MASTER_VOLUME;
    this.master.connect(context.destination);

    this.noise = context.createBuffer(1, context.sampleRate * 2, context.sampleRate);
    const samples = this.noise.getChannelData(0);
    for (let i = 0; i < samples.length; i++) samples[i] = Math.random() * 2 - 1;

    this.engineFilter = context.createBiquadFilter();
    this.engineFilter.type = "lowpass";
    this.engineFilter.frequency.value = 500;
    this.engineGain = context.createGain();
    this.engineGain.gain.value = 0;
    this.engineLow = context.createOscillator();
    this.engineLow.type = "sawtooth";
    this.engineHigh = context.createOscillator();
    this.engineHigh.type = "square";
    const highMix = context.createGain();
    highMix.gain.value = 0.35;
    this.engineLow.connect(this.engineFilter);
    this.engineHigh.connect(highMix).connect(this.engineFilter);
    this.engineFilter.connect(this.engineGain).connect(this.master);
    this.engineLow.start();
    this.engineHigh.start();

    const skidSource = context.createBufferSource();
    skidSource.buffer = this.noise;
    skidSource.loop = true;
    this.skidFilter = context.createBiquadFilter();
    this.skidFilter.type = "bandpass";
    this.skidFilter.frequency.value = 700;
    this.skidFilter.Q.value = 0.8;
    this.skidGain = context.createGain();
    this.skidGain.gain.value = 0;
    skidSource.connect(this.skidFilter).connect(this.skidGain).connect(this.master);
    skidSource.start();
  }

  toggleMute(): void {
    this.muted = !this.muted;
    if (this.master) this.master.gain.value = this.muted ? 0 : MASTER_VOLUME;
  }

  drive(speedFraction: number, throttle: number, slide: number, active: boolean): void {
    const context = this.context;
    if (!context || !this.engineLow || !this.engineHigh || !this.engineGain || !this.engineFilter || !this.skidGain || !this.skidFilter) return;
    const now = context.currentTime;
    const gearPosition = clamp(speedFraction, 0, 0.999) * GEAR_COUNT;
    const revs = clamp(0.25 + 0.6 * (gearPosition % 1) + 0.15 * speedFraction + slide * 0.25 * throttle, 0, 1.2);
    const frequency = lerp(42, 150, revs);
    this.engineLow.frequency.setTargetAtTime(frequency, now, 0.05);
    this.engineHigh.frequency.setTargetAtTime(frequency * 0.502, now, 0.05);
    this.engineFilter.frequency.setTargetAtTime(lerp(320, 1500, clamp(throttle * 0.7 + revs * 0.4, 0, 1)), now, 0.08);
    this.engineGain.gain.setTargetAtTime(active ? 0.1 + 0.1 * throttle : 0, now, 0.08);
    this.skidGain.gain.setTargetAtTime(active ? clamp(slide, 0, 1.2) * 0.2 : 0, now, 0.06);
    this.skidFilter.frequency.setTargetAtTime(lerp(500, 1100, speedFraction), now, 0.1);
  }

  thud(strength: number): void {
    this.burst(0.18, 220, clamp(strength, 0.1, 1) * 0.6, "lowpass");
  }

  explosion(): void {
    this.burst(0.5, 380, 0.55, "lowpass");
  }

  shot(): void {
    const context = this.context;
    if (!context || context.currentTime - this.lastShot < 0.05) return;
    this.lastShot = context.currentTime;
    this.burst(0.04, 2400, 0.07, "highpass");
  }

  pickup(pitch: number): void {
    this.tone(660 + pitch * 40, 0.07, 0.08, "triangle", 0);
  }

  levelUp(): void {
    [523, 659, 784, 1047].forEach((frequency, i) => this.tone(frequency, 0.16, 0.12, "triangle", i * 0.07));
  }

  defeat(): void {
    [392, 311, 233, 155].forEach((frequency, i) => this.tone(frequency, 0.3, 0.14, "sawtooth", i * 0.16));
  }

  private tone(frequency: number, duration: number, volume: number, type: OscillatorType, delay: number): void {
    const context = this.context;
    if (!context || !this.master) return;
    const start = context.currentTime + delay;
    const oscillator = context.createOscillator();
    oscillator.type = type;
    oscillator.frequency.value = frequency;
    const gain = context.createGain();
    gain.gain.setValueAtTime(volume, start);
    gain.gain.exponentialRampToValueAtTime(0.001, start + duration);
    oscillator.connect(gain).connect(this.master);
    oscillator.start(start);
    oscillator.stop(start + duration + 0.02);
  }

  private burst(duration: number, cutoff: number, volume: number, type: BiquadFilterType): void {
    const context = this.context;
    if (!context || !this.master || !this.noise) return;
    const source = context.createBufferSource();
    source.buffer = this.noise;
    const filter = context.createBiquadFilter();
    filter.type = type;
    filter.frequency.value = cutoff;
    const gain = context.createGain();
    gain.gain.setValueAtTime(volume, context.currentTime);
    gain.gain.exponentialRampToValueAtTime(0.001, context.currentTime + duration);
    source.connect(filter).connect(gain).connect(this.master);
    source.start(context.currentTime, Math.random());
    source.stop(context.currentTime + duration + 0.02);
  }
}
