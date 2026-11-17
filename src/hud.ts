import { type UpgradeCategory, type UpgradeDef, type UpgradeLevels, UPGRADES } from "./upgrades";

const CATEGORY_COLOR: Record<UpgradeCategory, string> = {
  car: "#f2a03a",
  smoke: "#f4ecdc",
  compound: "#e2452f",
  weapon: "#ffd45e",
  repair: "#6fe08a",
};

const CATEGORY_LABEL: Record<UpgradeCategory, string> = {
  car: "Chassis",
  smoke: "Smoke",
  compound: "Compound",
  weapon: "Weapon",
  repair: "Repair",
};

function element<T extends HTMLElement>(id: string): T {
  const found = document.getElementById(id);
  if (!found) throw new Error(`Missing #${id}`);
  return found as T;
}

function formatTime(seconds: number): string {
  const whole = Math.floor(seconds);
  return `${String(Math.floor(whole / 60)).padStart(2, "0")}:${String(whole % 60).padStart(2, "0")}`;
}

export interface RunSummary {
  seconds: number;
  kills: number;
  level: number;
}

export class Hud {
  onStart: (() => void) | null = null;
  onRetry: (() => void) | null = null;
  onPick: ((upgrade: UpgradeDef) => void) | null = null;

  private readonly root = element<HTMLDivElement>("hud");
  private readonly title = element("title");
  private readonly levelUp = element("levelup");
  private readonly pause = element("pause");
  private readonly gameOver = element("gameover");
  private readonly cards = element("cards");
  private readonly xpFill = element("xp-fill");
  private readonly hullFill = element("hull-fill");
  private readonly hullLabel = element("hull-label");
  private readonly smokeFill = element("smoke-fill");
  private readonly level = element("level");
  private readonly timer = element("timer");
  private readonly kills = element("kills");
  private readonly speed = element("speed");
  private readonly loadout = element("loadout");
  private readonly results = element("results");
  private readonly hitVignette = element("vignette-hit");
  private readonly padStatus = element("pad-status");
  private readonly padControls = element("pad-controls");
  private readonly keyControls = element("key-controls");
  private choices: UpgradeDef[] = [];
  private selected = 0;
  private shown = { timer: "", kills: -1, speed: -1, level: -1, hull: "" };

  constructor() {
    element("start-button").addEventListener("click", () => this.onStart?.());
    element("retry-button").addEventListener("click", () => this.onRetry?.());
  }

  showPlaying(visible: boolean): void {
    this.root.hidden = !visible;
  }

  showTitle(visible: boolean): void {
    this.title.hidden = !visible;
  }

  showPause(visible: boolean): void {
    this.pause.hidden = !visible;
  }

  showGameOver(summary: RunSummary | null): void {
    this.gameOver.hidden = summary === null;
    if (!summary) return;
    this.results.replaceChildren(
      this.resultCell("Survived", formatTime(summary.seconds)),
      this.resultCell("Wrecked", String(summary.kills)),
      this.resultCell("Level", String(summary.level)),
    );
  }

  setInputMode(usingGamepad: boolean, padConnected: boolean): void {
    this.padControls.classList.toggle("live", usingGamepad);
    this.keyControls.classList.toggle("live", !usingGamepad);
    this.padStatus.textContent = padConnected ? "Controller connected" : "No controller detected — press any button on it";
  }

  setFrame(hp: number, maxHp: number, xpFraction: number, level: number, seconds: number, kills: number, kmh: number, smoke: number): void {
    const time = formatTime(seconds);
    if (time !== this.shown.timer) this.timer.textContent = this.shown.timer = time;
    if (kills !== this.shown.kills) this.kills.textContent = String((this.shown.kills = kills));
    if (level !== this.shown.level) this.level.textContent = String((this.shown.level = level));
    const roundedSpeed = Math.round(kmh);
    if (roundedSpeed !== this.shown.speed) this.speed.textContent = String((this.shown.speed = roundedSpeed));
    const hull = `Hull ${Math.max(0, Math.ceil(hp))} / ${maxHp}`;
    if (hull !== this.shown.hull) this.hullLabel.textContent = this.shown.hull = hull;
    this.hullFill.style.transform = `scaleX(${Math.max(0, hp / maxHp)})`;
    this.smokeFill.style.transform = `scaleX(${Math.min(1, smoke)})`;
    this.xpFill.style.width = `${Math.min(100, xpFraction * 100)}%`;
  }

  setLoadout(levels: UpgradeLevels): void {
    const items = UPGRADES.filter((upgrade) => levels[upgrade.id] > 0).map((upgrade) => {
      const item = document.createElement("div");
      item.className = "loadout-item";
      item.style.setProperty("--accent", CATEGORY_COLOR[upgrade.category]);
      const name = document.createElement("span");
      name.textContent = upgrade.name;
      const pips = document.createElement("span");
      pips.className = "pips";
      pips.textContent = "●".repeat(levels[upgrade.id]) + "○".repeat(upgrade.maxLevel - levels[upgrade.id]);
      item.append(name, pips);
      return item;
    });
    this.loadout.replaceChildren(...items);
  }

  flashDamage(): void {
    this.hitVignette.classList.add("flash");
    requestAnimationFrame(() => requestAnimationFrame(() => this.hitVignette.classList.remove("flash")));
  }

  openLevelUp(choices: UpgradeDef[], levels: UpgradeLevels): void {
    this.choices = choices;
    this.selected = Math.min(1, choices.length - 1);
    const cards = choices.map((upgrade, index) => {
      const next = levels[upgrade.id] + 1;
      const card = document.createElement("button");
      card.type = "button";
      card.className = "card";
      card.style.setProperty("--accent", CATEGORY_COLOR[upgrade.category]);
      const tier = Number.isFinite(upgrade.maxLevel) ? (next === 1 ? "New" : `Tier ${next} of ${upgrade.maxLevel}`) : "";
      card.append(
        this.cardLine("glyph", upgrade.glyph),
        this.cardLine("category", CATEGORY_LABEL[upgrade.category]),
        this.cardLine("name", upgrade.name),
        this.cardLine("detail", upgrade.describe(next)),
        this.cardLine("tier", tier),
      );
      card.addEventListener("pointerenter", () => this.select(index));
      card.addEventListener("click", () => this.onPick?.(upgrade));
      return card;
    });
    this.cards.replaceChildren(...cards);
    this.select(this.selected);
    this.levelUp.hidden = false;
  }

  closeLevelUp(): void {
    this.levelUp.hidden = true;
  }

  moveSelection(direction: number): void {
    if (this.choices.length === 0) return;
    this.select((this.selected + direction + this.choices.length) % this.choices.length);
  }

  confirmSelection(): void {
    const choice = this.choices[this.selected];
    if (choice) this.onPick?.(choice);
  }

  private select(index: number): void {
    this.selected = index;
    Array.from(this.cards.children).forEach((card, i) => card.classList.toggle("selected", i === index));
  }

  private cardLine(className: string, text: string): HTMLElement {
    const line = document.createElement("span");
    line.className = className;
    line.textContent = text;
    return line;
  }

  private resultCell(label: string, value: string): HTMLElement {
    const cell = document.createElement("div");
    const caption = document.createElement("small");
    caption.textContent = label;
    cell.append(caption, value);
    return cell;
  }
}
