import { BASE_TUNING, CarBody, type CarInput } from "../src/vehicle";

type Phase = { until: number; input: CarInput };

function run(label: string, phases: Phase[], initialSpeed = 0): void {
  const car = new CarBody();
  car.vz = initialSpeed;
  const dt = 1 / 60;
  let t = 0;
  console.log(`\n== ${label}`);
  const end = phases[phases.length - 1].until;
  let nextReport = 0;
  while (t < end) {
    const phase = phases.find((p) => t < p.until)!;
    car.step(dt, phase.input, BASE_TUNING);
    t += dt;
    if (t >= nextReport) {
      nextReport += 0.5;
      const radius = Math.abs(car.yawRate) > 0.01 ? car.speed / Math.abs(car.yawRate) : Infinity;
      console.log(
        `t=${t.toFixed(1)} spd=${car.speed.toFixed(1)} fwd=${car.forwardSpeed.toFixed(1)} yaw=${car.yawRate.toFixed(2)} drift=${((car.driftAngle * 180) / Math.PI).toFixed(0)}deg rearSlip=${car.rearSlipSpeed.toFixed(1)} smoke=${car.smokeIntensity().toFixed(2)} R=${radius.toFixed(1)} steer=${car.steerAngle.toFixed(2)}`,
      );
    }
  }
}

const idle: CarInput = { throttle: 0, brake: 0, steer: 0, handbrake: false };
const gas: CarInput = { ...idle, throttle: 1 };

run("launch", [{ until: 8, input: gas }]);
run("donut from standstill", [{ until: 8, input: { ...gas, steer: 1 } }]);
run("power turn at speed", [{ until: 6, input: { ...gas, steer: 1 } }], 25);
run("half steer at speed", [{ until: 5, input: { ...gas, steer: 0.4 } }], 28);
run(
  "handbrake entry then hold",
  [
    { until: 0.6, input: { ...idle, steer: 1, handbrake: true } },
    { until: 6, input: { ...gas, steer: 1 } },
  ],
  26,
);
run(
  "flick then countersteer recover",
  [
    { until: 0.5, input: { ...idle, steer: 1, handbrake: true } },
    { until: 1.1, input: { ...gas, steer: -0.5 } },
    { until: 5, input: gas },
  ],
  26,
);
run("coast", [{ until: 4, input: idle }], 30);
run("brake", [{ until: 3, input: { ...idle, brake: 1 } }], 30);
run("reverse", [{ until: 3, input: { ...idle, brake: 1 } }], 0);
