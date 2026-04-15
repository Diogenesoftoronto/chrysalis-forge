import { useActionState } from "react";
import { useFormStatus } from "react-dom";
import { Button } from "../components/ui/button";
import { Input } from "../components/ui/input";
import { Select } from "../components/ui/select";
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
} from "../components/ui/card";
import {
  loadSettings,
  saveSettings,
  type Provider,
  type Settings as S,
} from "../lib/settings";
import { listAnthropicModels } from "../lib/models";

const MODELS = listAnthropicModels();

type SaveState = { ok: boolean; settings: S; error?: string };

async function saveAction(
  _prev: SaveState,
  formData: FormData,
): Promise<SaveState> {
  const next: S = {
    provider: (formData.get("provider") as Provider) ?? "anthropic",
    model: (formData.get("model") as string) ?? "",
    apiKey: (formData.get("apiKey") as string) ?? "",
  };
  if (!next.apiKey.trim()) {
    return { ok: false, settings: next, error: "API key is required." };
  }
  saveSettings(next);
  return { ok: true, settings: next };
}

export default function Settings() {
  const [state, formAction] = useActionState<SaveState, FormData>(saveAction, {
    ok: false,
    settings: loadSettings(),
  });

  return (
    <div className="mx-auto max-w-xl space-y-6">
      <header>
        <h1 className="text-3xl font-bold tracking-tight">Settings</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          Bring your own key. Stored in{" "}
          <code className="text-primary">localStorage</code> on this device and
          sent directly to Anthropic from your browser. Nothing touches our
          servers.
        </p>
      </header>

      <Card>
        <CardHeader>
          <CardTitle>API credentials</CardTitle>
        </CardHeader>
        <CardContent>
          <form action={formAction} className="space-y-4">
            <div className="space-y-1.5">
              <label
                htmlFor="provider"
                className="text-xs font-medium uppercase tracking-wide text-muted-foreground"
              >
                Provider
              </label>
              <Select
                id="provider"
                name="provider"
                defaultValue={state.settings.provider}
              >
                <option value="anthropic">Anthropic</option>
              </Select>
            </div>

            <div className="space-y-1.5">
              <label
                htmlFor="model"
                className="text-xs font-medium uppercase tracking-wide text-muted-foreground"
              >
                Model
              </label>
              <Select
                id="model"
                name="model"
                defaultValue={state.settings.model}
              >
                {MODELS.map((m) => (
                  <option key={m} value={m}>
                    {m}
                  </option>
                ))}
              </Select>
            </div>

            <div className="space-y-1.5">
              <label
                htmlFor="apiKey"
                className="text-xs font-medium uppercase tracking-wide text-muted-foreground"
              >
                API key
              </label>
              <Input
                id="apiKey"
                name="apiKey"
                type="password"
                autoComplete="off"
                spellCheck={false}
                placeholder="sk-ant-..."
                defaultValue={state.settings.apiKey}
              />
            </div>

            <SaveRow state={state} />
          </form>
        </CardContent>
      </Card>
    </div>
  );
}

function SaveRow({ state }: { state: SaveState }) {
  const { pending } = useFormStatus();
  return (
    <div className="flex items-center gap-3 pt-2">
      <Button type="submit" disabled={pending}>
        {pending ? "Saving…" : "Save"}
      </Button>
      {state.error && (
        <span className="text-sm text-destructive">{state.error}</span>
      )}
      {state.ok && !pending && (
        <span className="text-sm text-emerald-400">Saved.</span>
      )}
    </div>
  );
}
