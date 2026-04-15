import { useMemo, useRef, useState } from "react";
import { Link } from "@tanstack/react-router";
import {
  AssistantRuntimeProvider,
  useLocalRuntime,
} from "@assistant-ui/react";
import ThreadView from "../components/ThreadView";
import { Select } from "../components/ui/select";
import { makePiAdapter } from "../lib/runtime";
import { prompts } from "../lib/piContent";
import { hasKey } from "../lib/settings";

export default function Chat() {
  const [promptId, setPromptId] = useState(prompts[0].id);
  const systemRef = useRef(prompts[0].body);
  systemRef.current =
    prompts.find((p) => p.id === promptId)?.body ?? prompts[0].body;

  const runtime = useLocalRuntime(
    useMemo(() => makePiAdapter(() => systemRef.current), []),
  );

  return (
    <section className="flex h-[calc(100vh-10rem)] flex-col gap-3">
      <div className="flex flex-wrap items-center gap-4">
        <label className="flex items-center gap-2 text-sm text-muted-foreground">
          Task prompt
          <Select
            value={promptId}
            onChange={(e) => setPromptId(e.target.value)}
            className="h-9"
          >
            {prompts.map((p) => (
              <option key={p.id} value={p.id}>
                {p.title}
              </option>
            ))}
          </Select>
        </label>
        {!hasKey() && (
          <span className="text-sm text-amber-400">
            No API key —{" "}
            <Link to="/settings" className="underline">
              add one in Settings
            </Link>
            .
          </span>
        )}
      </div>
      <div className="flex-1 overflow-hidden rounded-lg border border-border bg-card">
        <AssistantRuntimeProvider runtime={runtime}>
          <ThreadView />
        </AssistantRuntimeProvider>
      </div>
    </section>
  );
}
