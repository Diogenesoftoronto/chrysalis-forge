import { getModels } from "@mariozechner/pi-ai";

export function listAnthropicModels(): string[] {
  try {
    const models = getModels("anthropic");
    const ids = Array.from(new Set(models.map((m) => m.id))).filter((id) =>
      /^claude-/.test(id) && !/-\d{8}$/.test(id),
    );
    ids.sort();
    return ids;
  } catch {
    return ["claude-opus-4-5", "claude-sonnet-4-5", "claude-haiku-4-5"];
  }
}
