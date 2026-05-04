import { useState, type ChangeEvent } from "react";
import { useForm } from "@tanstack/react-form";
import { useStyletron } from "baseui";
import { Button } from "baseui/button";
import { Input } from "baseui/input";
import { Card } from "baseui/card";
import { LabelSmall, HeadingLarge, ParagraphSmall } from "baseui/typography";
import { NativeSelect } from "../components/NativeSelect";
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
  const [css, theme] = useStyletron();
  const [savedAt, setSavedAt] = useState<number | null>(null);

  const form = useForm({
    defaultValues: loadSettings() as S,
    onSubmit: async ({ value }) => {
      saveSettings(value);
      setSavedAt(Date.now());
    },
  });

  return (
    <div
      className={css({
        maxWidth: "36rem",
        marginLeft: "auto",
        marginRight: "auto",
        display: "flex",
        flexDirection: "column",
        gap: theme.sizing.scale600,
      })}
    >
      <header>
        <HeadingLarge marginTop={0} marginBottom={theme.sizing.scale300}>
          Settings
        </HeadingLarge>
        <ParagraphSmall marginTop={0} marginBottom={0} className={css({ color: theme.colors.contentSecondary })}>
          Bring your own key. Stored in <code className={css({ color: theme.colors.accent })}>localStorage</code> on this
          device and sent directly to Anthropic from your browser. Nothing touches our servers.
        </ParagraphSmall>
      </header>

      <Card overrides={{}} title="API credentials">
        <form
          onSubmit={(e) => {
            e.preventDefault();
            setSavedAt(null);
            form.handleSubmit();
          }}
          className={css({ display: "flex", flexDirection: "column", gap: theme.sizing.scale500 })}
        >
          <form.Field name="provider">
            {(field) => (
              <Labeled id={field.name} label="Provider">
                <NativeSelect
                  id={field.name}
                  name={field.name}
                  value={field.state.value}
                  onBlur={field.handleBlur}
                  onChange={(e) => field.handleChange(e.target.value as Provider)}
                >
                  {PROVIDERS.map((p) => (
                    <option key={p} value={p}>
                      {p}
                    </option>
                  ))}
                </NativeSelect>
              </Labeled>
            )}
          </form.Field>

          <form.Field name="model">
            {(field) => (
              <Labeled id={field.name} label="Model">
                <NativeSelect
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
                </NativeSelect>
              </Labeled>
            )}
          </form.Field>

          <form.Field
            name="apiKey"
            validators={{
              onChange: ({ value }) => (!value?.trim() ? "API key is required." : undefined),
            }}
          >
            {(field) => (
              <Labeled id={field.name} label="API key">
                <Input
                  id={field.name}
                  name={field.name}
                  type="password"
                  autoComplete="off"
                  placeholder="sk-ant-..."
                  value={field.state.value}
                  onBlur={field.handleBlur}
                  onChange={(e: ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) =>
                    field.handleChange(e.target.value)}
                  error={field.state.meta.isTouched && field.state.meta.errors.length > 0}
                />
                {field.state.meta.isTouched && field.state.meta.errors.length > 0 && (
                  <span className={css({ fontSize: theme.typography.font100.fontSize, color: theme.colors.contentNegative })}>
                    {field.state.meta.errors.join(", ")}
                  </span>
                )}
              </Labeled>
            )}
          </form.Field>

          <form.Subscribe selector={(s) => ({ canSubmit: s.canSubmit, isSubmitting: s.isSubmitting })}>
            {({ canSubmit, isSubmitting }) => (
              <div
                className={css({
                  display: "flex",
                  alignItems: "center",
                  gap: theme.sizing.scale400,
                  paddingTop: theme.sizing.scale300,
                })}
              >
                <Button type="submit" disabled={!canSubmit || isSubmitting}>
                  {isSubmitting ? "Saving…" : "Save"}
                </Button>
                {savedAt && !isSubmitting && (
                  <span className={css({ fontSize: theme.typography.font200.fontSize, color: theme.colors.contentPositive })}>
                    Saved.
                  </span>
                )}
              </div>
            )}
          </form.Subscribe>
        </form>
      </Card>
    </div>
  );
}

function Labeled({ id, label, children }: { id: string; label: string; children: React.ReactNode }) {
  const [css, theme] = useStyletron();
  return (
    <div className={css({ display: "flex", flexDirection: "column", gap: theme.sizing.scale300 })}>
      <LabelSmall
        as="label"
        htmlFor={id}
        marginBottom={0}
        marginTop={0}
        className={css({
          textTransform: "uppercase",
          letterSpacing: "0.04em",
          color: theme.colors.contentSecondary,
        })}
      >
        {label}
      </LabelSmall>
      {children}
    </div>
  );
}
