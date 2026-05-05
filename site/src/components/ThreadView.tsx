import {
  ThreadPrimitive,
  ComposerPrimitive,
  MessagePrimitive,
} from "@assistant-ui/react";
import { SendHorizontal } from "lucide-react";

export default function ThreadView() {
  return (
    <ThreadPrimitive.Root className="flex h-full flex-col">
      <ThreadPrimitive.Viewport className="flex-1 space-y-5 overflow-y-auto p-5">
        <ThreadPrimitive.Empty>
          <div className="py-10 text-center text-sm text-muted-foreground">
            Describe the task. Pi will respond using the selected prompt style.
          </div>
        </ThreadPrimitive.Empty>

        <ThreadPrimitive.Messages
          components={{
            UserMessage,
            AssistantMessage,
          }}
        />
      </ThreadPrimitive.Viewport>

      <ComposerPrimitive.Root className="flex gap-2 border-t border-border bg-background p-3">
        <ComposerPrimitive.Input
          className="flex min-h-10 max-h-40 flex-1 resize-none rounded-md border border-border bg-card px-3 py-2 text-sm text-foreground placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background"
          placeholder="Ask pi to architect, review, or ship…"
          autoFocus
        />
        <ComposerPrimitive.Send className="inline-flex h-10 items-center justify-center gap-2 rounded-md bg-primary px-4 text-sm font-semibold text-primary-foreground transition-colors hover:bg-primary/90 disabled:pointer-events-none disabled:opacity-50">
          <SendHorizontal className="h-4 w-4" />
          Send
        </ComposerPrimitive.Send>
      </ComposerPrimitive.Root>
    </ThreadPrimitive.Root>
  );
}

function UserMessage() {
  return (
    <MessagePrimitive.Root className="flex gap-3">
      <div className="min-w-10 pt-1 text-[10px] font-semibold uppercase tracking-wider text-muted-foreground">
        you
      </div>
      <div className="flex-1 whitespace-pre-wrap leading-relaxed text-foreground">
        <MessagePrimitive.Parts />
      </div>
    </MessagePrimitive.Root>
  );
}

function AssistantMessage() {
  return (
    <MessagePrimitive.Root className="flex gap-3">
      <div className="min-w-10 pt-1 text-[10px] font-semibold uppercase tracking-wider text-muted-foreground">
        pi
      </div>
      <div className="flex-1 whitespace-pre-wrap border-l-2 border-primary pl-3 leading-relaxed text-foreground">
        <MessagePrimitive.Parts />
      </div>
    </MessagePrimitive.Root>
  );
}
