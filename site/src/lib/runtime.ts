import Anthropic from "@anthropic-ai/sdk";
import { getModel, stream } from "@mariozechner/pi-ai";
import type {
  Context,
  Message,
  UserMessage,
} from "@mariozechner/pi-ai";
import type {
  ChatModelAdapter,
  ChatModelRunOptions,
  ChatModelRunResult,
} from "@assistant-ui/react";
import { loadSettings } from "./settings";

function extractText(content: unknown): string {
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return "";
  return content
    .map((part: any) => (part?.type === "text" ? part.text ?? "" : ""))
    .join("");
}

function toPiMessages(messages: readonly any[]): Message[] {
  const out: Message[] = [];
  for (const m of messages) {
    if (m.role === "user") {
      const text = extractText(m.content);
      const msg: UserMessage = {
        role: "user",
        content: text,
        timestamp: Date.now(),
      };
      out.push(msg);
    } else if (m.role === "assistant") {
      out.push({
        role: "assistant",
        content: [{ type: "text", text: extractText(m.content) }],
        api: "anthropic-messages",
        provider: "anthropic",
        model: "",
        usage: {
          input: 0,
          output: 0,
          cacheRead: 0,
          cacheWrite: 0,
          totalTokens: 0,
          cost: {
            input: 0,
            output: 0,
            cacheRead: 0,
            cacheWrite: 0,
            total: 0,
          },
        },
        stopReason: "stop",
        timestamp: Date.now(),
      } as any);
    }
  }
  return out;
}

export function makePiAdapter(getSystemPrompt: () => string): ChatModelAdapter {
  return {
    async *run({
      messages,
      abortSignal,
    }: ChatModelRunOptions): AsyncGenerator<ChatModelRunResult, void> {
      const { apiKey, model: modelId } = loadSettings();
      if (!apiKey) {
        yield {
          content: [
            {
              type: "text",
              text: "No API key set. Open **Settings** and paste your Anthropic key.",
            },
          ],
        };
        return;
      }

      const client = new Anthropic({
        apiKey,
        dangerouslyAllowBrowser: true,
      });

      const model = getModel("anthropic", modelId as any);

      const context: Context = {
        systemPrompt: getSystemPrompt(),
        messages: toPiMessages(messages),
      };

      const events = stream(model, context, {
        client,
        signal: abortSignal,
      } as any);

      let text = "";
      try {
        for await (const event of events) {
          if (event.type === "text_delta") {
            text += event.delta;
            yield { content: [{ type: "text", text }] };
          } else if (event.type === "done") {
            const finalText = event.message.content.find(
              (c): c is { type: "text"; text: string } & typeof c =>
                c.type === "text",
            );
            const final = finalText?.text ?? text;
            yield { content: [{ type: "text", text: final }] };
            return;
          } else if (event.type === "error") {
            yield {
              content: [
                {
                  type: "text",
                  text: `Error: ${event.error.errorMessage ?? "stream failed"}`,
                },
              ],
            };
            return;
          }
        }
      } catch (err) {
        yield {
          content: [
            {
              type: "text",
              text: `Error: ${err instanceof Error ? err.message : String(err)}`,
            },
          ],
        };
      }
    },
  };
}
