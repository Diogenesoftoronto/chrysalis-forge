import { useMemo, useRef, useState } from "react";
import { Link } from "@tanstack/react-router";
import { AssistantRuntimeProvider, useLocalRuntime } from "@assistant-ui/react";
import { useStyletron } from "baseui";
import ThreadView from "../components/ThreadView";
import { NativeSelect } from "../components/NativeSelect";
import { makePiAdapter } from "../lib/runtime";
import { prompts } from "../lib/piContent";
import { hasKey } from "../lib/settings";

export default function Chat() {
  const [css, theme] = useStyletron();
  const [promptId, setPromptId] = useState(prompts[0].id);
  const systemRef = useRef(prompts[0].body);
  systemRef.current = prompts.find((p) => p.id === promptId)?.body ?? prompts[0].body;

  const runtime = useLocalRuntime(useMemo(() => makePiAdapter(() => systemRef.current), []));

  return (
    <section
      className={css({
        display: "flex",
        height: "calc(100vh - 10rem)",
        flexDirection: "column",
        gap: theme.sizing.scale400,
      })}
    >
      <div
        className={css({
          display: "flex",
          flexWrap: "wrap",
          alignItems: "center",
          gap: theme.sizing.scale500,
        })}
      >
        <label
          className={css({
            display: "flex",
            alignItems: "center",
            gap: theme.sizing.scale300,
            fontSize: theme.typography.font200.fontSize,
            color: theme.colors.contentSecondary,
          })}
        >
          Task prompt
          <NativeSelect
            value={promptId}
            onChange={(e) => setPromptId(e.target.value)}
            className={css({ height: theme.sizing.scale950 })}
          />
        </label>
        {!hasKey() && (
          <span
            className={css({
              fontSize: theme.typography.font200.fontSize,
              color: theme.colors.warning,
            })}
          >
            No API key —{" "}
            <Link
              to="/settings"
              className={css({
                color: theme.colors.warning,
                textDecoration: "underline",
              })}
            >
              add one in Settings
            </Link>
            .
          </span>
        )}
      </div>
      <div
        className={css({
          flex: 1,
          overflow: "hidden",
          borderRadius: theme.borders.radius300,
          borderWidth: "1px",
          borderStyle: "solid",
          borderColor: theme.colors.borderOpaque,
          backgroundColor: theme.colors.backgroundSecondary,
        })}
      >
        <AssistantRuntimeProvider runtime={runtime}>
          <ThreadView />
        </AssistantRuntimeProvider>
      </div>
    </section>
  );
}
