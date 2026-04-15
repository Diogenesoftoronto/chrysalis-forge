export type Provider = "anthropic";

export interface Settings {
  provider: Provider;
  apiKey: string;
  model: string;
}

const KEY = "chrysalis-pi-settings";

const DEFAULTS: Settings = {
  provider: "anthropic",
  apiKey: "",
  model: "claude-sonnet-4-5",
};

export function loadSettings(): Settings {
  if (typeof localStorage === "undefined") return DEFAULTS;
  try {
    const raw = localStorage.getItem(KEY);
    if (!raw) return DEFAULTS;
    return { ...DEFAULTS, ...JSON.parse(raw) };
  } catch {
    return DEFAULTS;
  }
}

export function saveSettings(s: Settings): void {
  localStorage.setItem(KEY, JSON.stringify(s));
}

export function hasKey(): boolean {
  return loadSettings().apiKey.trim().length > 0;
}
