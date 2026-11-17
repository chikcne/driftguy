import { clamp } from "./math";

const STICK_DEADZONE = 0.14;
const TRIGGER_DEADZONE = 0.04;
const MENU_STICK_THRESHOLD = 0.55;
const STEER_CURVE = 1.4;

const PAD = {
  a: 0,
  b: 1,
  x: 2,
  y: 3,
  leftBumper: 4,
  rightBumper: 5,
  leftTrigger: 6,
  rightTrigger: 7,
  start: 9,
  dpadLeft: 14,
  dpadRight: 15,
};

function applyDeadzone(value: number, deadzone: number): number {
  const magnitude = Math.abs(value);
  if (magnitude < deadzone) return 0;
  return (Math.sign(value) * (magnitude - deadzone)) / (1 - deadzone);
}

export class Input {
  throttle = 0;
  brake = 0;
  steer = 0;
  handbrake = false;
  menuMove = 0;
  confirm = false;
  pause = false;
  mute = false;
  usingGamepad = false;
  onFirstGesture: (() => void) | null = null;

  private readonly keys = new Set<string>();
  private readonly pressedThisFrame = new Set<string>();
  private previousPadButtons: boolean[] = [];
  private previousMenuAxis = 0;
  private padIndex = -1;

  constructor() {
    window.addEventListener("keydown", (event) => {
      if (["Space", "ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight"].includes(event.code)) event.preventDefault();
      if (!event.repeat) this.pressedThisFrame.add(event.code);
      this.keys.add(event.code);
      this.usingGamepad = false;
      this.onFirstGesture?.();
    });
    window.addEventListener("keyup", (event) => this.keys.delete(event.code));
    window.addEventListener("blur", () => this.keys.clear());
    window.addEventListener("pointerdown", () => this.onFirstGesture?.());
    window.addEventListener("gamepadconnected", (event) => {
      this.padIndex = event.gamepad.index;
    });
    window.addEventListener("gamepaddisconnected", (event) => {
      if (event.gamepad.index === this.padIndex) this.padIndex = -1;
    });
  }

  get padConnected(): boolean {
    return this.activePad() !== null;
  }

  poll(): void {
    const down = (code: string): boolean => this.keys.has(code);
    const pressed = (code: string): boolean => this.pressedThisFrame.has(code);

    let throttle = down("KeyW") || down("ArrowUp") ? 1 : 0;
    let brake = down("KeyS") || down("ArrowDown") ? 1 : 0;
    let steer = (down("KeyD") || down("ArrowRight") ? 1 : 0) - (down("KeyA") || down("ArrowLeft") ? 1 : 0);
    let handbrake = down("Space") || down("ShiftLeft") || down("ShiftRight");
    let menuMove = (pressed("KeyD") || pressed("ArrowRight") ? 1 : 0) - (pressed("KeyA") || pressed("ArrowLeft") ? 1 : 0);
    let confirm = pressed("Enter");
    let pause = pressed("Escape") || pressed("KeyP");
    this.mute = pressed("KeyM");

    const pad = this.activePad();
    if (pad) {
      const buttons = pad.buttons.map((button) => button.pressed);
      const edge = (index: number): boolean => Boolean(buttons[index]) && !this.previousPadButtons[index];
      const stick = applyDeadzone(pad.axes[0] ?? 0, STICK_DEADZONE);
      const padThrottle = applyDeadzone(pad.buttons[PAD.rightTrigger]?.value ?? 0, TRIGGER_DEADZONE);
      const padBrake = applyDeadzone(pad.buttons[PAD.leftTrigger]?.value ?? 0, TRIGGER_DEADZONE);
      const padSteer = Math.sign(stick) * Math.pow(Math.abs(stick), STEER_CURVE);
      const padHandbrake = Boolean(buttons[PAD.b] || buttons[PAD.x] || buttons[PAD.rightBumper]);

      if (padThrottle > 0 || padBrake > 0 || stick !== 0 || buttons.some(Boolean)) this.usingGamepad = true;
      throttle = Math.max(throttle, padThrottle);
      brake = Math.max(brake, padBrake);
      if (Math.abs(padSteer) > Math.abs(steer)) steer = padSteer;
      handbrake = handbrake || padHandbrake;

      const menuAxis = (buttons[PAD.dpadRight] ? 1 : 0) - (buttons[PAD.dpadLeft] ? 1 : 0) || (Math.abs(stick) > MENU_STICK_THRESHOLD ? Math.sign(stick) : 0);
      if (menuAxis !== 0 && menuAxis !== this.previousMenuAxis) menuMove = menuAxis;
      this.previousMenuAxis = menuAxis;
      confirm = confirm || edge(PAD.a);
      pause = pause || edge(PAD.start);
      this.previousPadButtons = buttons;
    }

    this.throttle = throttle;
    this.brake = brake;
    this.steer = clamp(steer, -1, 1);
    this.handbrake = handbrake;
    this.menuMove = menuMove;
    this.confirm = confirm;
    this.pause = pause;
    this.pressedThisFrame.clear();
  }

  rumble(strong: number, weak: number, milliseconds: number): void {
    if (!this.usingGamepad) return;
    const actuator = this.activePad()?.vibrationActuator;
    if (!actuator) return;
    actuator
      .playEffect("dual-rumble", { duration: milliseconds, strongMagnitude: clamp(strong, 0, 1), weakMagnitude: clamp(weak, 0, 1) })
      .catch(() => undefined);
  }

  private activePad(): Gamepad | null {
    if (typeof navigator.getGamepads !== "function") return null;
    const pads = navigator.getGamepads();
    const preferred = this.padIndex >= 0 ? pads[this.padIndex] : null;
    if (preferred?.connected) return preferred;
    for (const pad of pads) {
      if (pad?.connected) {
        this.padIndex = pad.index;
        return pad;
      }
    }
    return null;
  }
}
