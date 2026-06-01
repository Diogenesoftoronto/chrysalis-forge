import { useState } from "react";
import { useForm } from "@tanstack/react-form";
import { Button } from "../components/ui/button";
import { Input } from "../components/ui/input";
import { Select } from "../components/ui/select";

import {
  loadSettings,
  saveSettings,
  type Provider,
  type Settings as S,
} from "../lib/settings";
import { listAnthropicModels } from "../lib/models";

const MODELS = listAnthropicModels();
const PROVIDERS: Provider[] = ["anthropic"];

export default function Settings() {
  const [savedAt, setSavedAt] = useState<number | null>(null);

  const form = useForm({
    defaultValues: loadSettings() as S,
    onSubmit: async ({ value }) => {
      saveSettings(value);
      setSavedAt(Date.now());
    },
  });

  return (
    <div className="mx-auto max-w-xl space-y-6 px-4 py-8">
      <header>
        <p className="mb-3 font-mono text-xs font-bold uppercase tracking-widest text-dim">
          // Settings
        </p>
        <h1 className="font-display text-5xl tracking-wide text-foreground">
          SETTINGS
        </h1>
        <p className="mt-3 text-sm text-dim">
          Bring your own key. Stored in{" "}
          <code className="text-gold">localStorage</code> on this device and
          sent directly to Anthropic from your browser. Nothing touches our
          servers.
        </p>
      </header>

      <div className="border border-border bg-bg3 p-6">
        <h2 className="mb-4 font-mono text-xs font-bold uppercase tracking-wider text-foreground">
          API credentials
        </h2>
        <form
          className="space-y-4"
          onSubmit={(e) => {
            e.preventDefault();
            setSavedAt(null);
            form.handleSubmit();
          }}
        >
          <form.Field name="provider">
            {(field) => (
              <Labeled id={field.name} label="Provider">
                <Select
                  id={field.name}
                  name={field.name}
                  value={field.state.value}
                  onBlur={field.handleBlur}
                  onChange={(e) =>
                    field.handleChange(e.target.value as Provider)
                  }
                >
                  {PROVIDERS.map((p) => (
                    <option key={p} value={p}>
                      {p}
                    </option>
                  ))}
                </Select>
              </Labeled>
            )}
          </form.Field>

          <form.Field name="model">
            {(field) => (
              <Labeled id={field.name} label="Model">
                <Select
                  id={field.name}
                  name={field.name}
                  value={field.state.value}
                  onBlur={field.handleBlur}
                  onChange={(e) => field.handleChange(e.target.value)}
                >
                  {MODELS.map((m) => (
                    <option key={m} value={m}>
                      {m}
                    </option>
                  ))}
                </Select>
              </Labeled>
            )}
          </form.Field>

          <form.Field
            name="apiKey"
            validators={{
              onChange: ({ value }) =>
                !value?.trim() ? "API key is required." : undefined,
            }}
          >
            {(field) => (
              <Labeled id={field.name} label="API key">
                <Input
                  id={field.name}
                  name={field.name}
                  type="password"
                  autoComplete="off"
                  spellCheck={false}
                  placeholder="sk-ant-..."
                  value={field.state.value}
                  onBlur={field.handleBlur}
                  onChange={(e) => field.handleChange(e.target.value)}
                />
                {field.state.meta.isTouched &&
                  field.state.meta.errors.length > 0 && (
                    <span className="text-xs text-red">
                      {field.state.meta.errors.join(", ")}
                    </span>
                  )}
              </Labeled>
            )}
          </form.Field>

          <form.Subscribe
            selector={(s) => ({
              canSubmit: s.canSubmit,
              isSubmitting: s.isSubmitting,
            })}
          >
            {({ canSubmit, isSubmitting }) => (
              <div className="flex items-center gap-3 pt-2">
                <Button
                  type="submit"
                  disabled={!canSubmit || isSubmitting}
                  className="border-2 border-gold font-mono text-xs font-bold uppercase tracking-wider text-gold hover:bg-gold hover:text-background"
                >
                  {isSubmitting ? "Saving…" : "Save"}
                </Button>
                {savedAt && !isSubmitting && (
                  <span className="text-sm text-green">Saved.</span>
                )}
              </div>
            )}
          </form.Subscribe>
        </form>
      </div>
    </div>
  );
}

function Labeled({
  id,
  label,
  children,
}: {
  id: string;
  label: string;
  children: React.ReactNode;
}) {
  return (
    <div className="space-y-1.5">
      <label
        htmlFor={id}
        className="font-mono text-xs font-bold uppercase tracking-wider text-dim"
      >
        {label}
      </label>
      {children}
    </div>
  );
}
