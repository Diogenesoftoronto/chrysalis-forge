import { useState } from "react";
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
  type Settings as S,
} from "../lib/settings";
import { listAnthropicModels } from "../lib/models";

const MODELS = listAnthropicModels();

export default function Settings() {
  const [s, setS] = useState<S>(loadSettings);
  const [saved, setSaved] = useState(false);

  const update = (patch: Partial<S>) => {
    setS((prev) => ({ ...prev, ...patch }));
    setSaved(false);
  };

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
        <CardContent className="space-y-4">
          <div className="space-y-1.5">
            <label className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
              Provider
            </label>
            <Select
              value={s.provider}
              onChange={(e) =>
                update({ provider: e.target.value as "anthropic" })
              }
            >
              <option value="anthropic">Anthropic</option>
            </Select>
          </div>

          <div className="space-y-1.5">
            <label className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
              Model
            </label>
            <Select
              value={s.model}
              onChange={(e) => update({ model: e.target.value })}
            >
              {MODELS.map((m) => (
                <option key={m} value={m}>
                  {m}
                </option>
              ))}
            </Select>
          </div>

          <div className="space-y-1.5">
            <label className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
              API key
            </label>
            <Input
              type="password"
              autoComplete="off"
              spellCheck={false}
              placeholder="sk-ant-..."
              value={s.apiKey}
              onChange={(e) => update({ apiKey: e.target.value })}
            />
          </div>

          <div className="flex items-center gap-3 pt-2">
            <Button
              onClick={() => {
                saveSettings(s);
                setSaved(true);
              }}
            >
              Save
            </Button>
            {saved && (
              <span className="text-sm text-emerald-400">Saved.</span>
            )}
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
