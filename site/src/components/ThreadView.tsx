import {
  ThreadPrimitive,
  ComposerPrimitive,
  MessagePrimitive,
} from "@assistant-ui/react";
import { SendHorizontal } from "lucide-react";
import { useStyletron } from "baseui";

export default function ThreadView() {
  const [css, theme] = useStyletron();

  const root = css({
    display: "flex",
    height: "100%",
    flexDirection: "column",
  });

  const viewport = css({
    flex: 1,
    display: "flex",
    flexDirection: "column",
    gap: theme.sizing.scale600,
    overflowY: "auto",
    padding: theme.sizing.scale600,
  });

  const empty = css({
    paddingTop: "2.5rem",
    paddingBottom: "2.5rem",
    textAlign: "center",
    fontSize: theme.typography.font200.fontSize,
    color: theme.colors.contentSecondary,
  });

  const composerRoot = css({
    display: "flex",
    gap: theme.sizing.scale300,
    borderTopWidth: "1px",
    borderTopStyle: "solid",
    borderTopColor: theme.colors.borderOpaque,
    backgroundColor: theme.colors.backgroundPrimary,
    padding: theme.sizing.scale400,
  });

  const input = css({
    flex: 1,
    minHeight: theme.sizing.scale800,
    maxHeight: "10rem",
    resize: "none",
    borderRadius: theme.borders.radius200,
    borderWidth: "1px",
    borderStyle: "solid",
    borderColor: theme.colors.borderOpaque,
    backgroundColor: theme.colors.backgroundSecondary,
    paddingLeft: theme.sizing.scale400,
    paddingRight: theme.sizing.scale400,
    paddingTop: theme.sizing.scale300,
    paddingBottom: theme.sizing.scale300,
    fontSize: theme.typography.font200.fontSize,
    color: theme.colors.contentPrimary,
    outline: "none",
    "::placeholder": {
      color: theme.colors.contentSecondary,
    },
  });

  const sendBtn = css({
    display: "inline-flex",
    height: theme.sizing.scale800,
    alignItems: "center",
    justifyContent: "center",
    gap: theme.sizing.scale300,
    borderRadius: theme.borders.radius200,
    border: "none",
    paddingLeft: theme.sizing.scale500,
    paddingRight: theme.sizing.scale500,
    fontSize: theme.typography.font200.fontSize,
    fontWeight: 600,
    backgroundColor: theme.colors.buttonPrimaryFill,
    color: theme.colors.buttonPrimaryText,
    cursor: "pointer",
    transition: "opacity 0.15s ease",
    ":disabled": {
      opacity: 0.5,
      cursor: "not-allowed",
    },
    ":hover:not(:disabled)": {
      backgroundColor: theme.colors.buttonPrimaryHover,
    },
  });

  return (
    <ThreadPrimitive.Root className={root}>
      <ThreadPrimitive.Viewport className={viewport}>
        <ThreadPrimitive.Empty>
          <div className={empty}>Describe the task. Pi will respond using the selected prompt style.</div>
        </ThreadPrimitive.Empty>

        <ThreadPrimitive.Messages
          components={{
            UserMessage,
            AssistantMessage,
          }}
        />
      </ThreadPrimitive.Viewport>

      <ComposerPrimitive.Root className={composerRoot}>
        <ComposerPrimitive.Input
          className={input}
          placeholder="Ask pi to architect, review, or ship…"
          autoFocus
        />
        <ComposerPrimitive.Send className={sendBtn}>
          <SendHorizontal size={16} />
          Send
        </ComposerPrimitive.Send>
      </ComposerPrimitive.Root>
    </ThreadPrimitive.Root>
  );
}

function UserMessage() {
  const [css, theme] = useStyletron();
  const msgRow = css({ display: "flex", gap: theme.sizing.scale400 });
  const role = css({
    minWidth: "2.5rem",
    paddingTop: "4px",
    fontSize: "10px",
    fontWeight: 600,
    textTransform: "uppercase",
    letterSpacing: "0.06em",
    color: theme.colors.contentSecondary,
  });
  const userBody = css({
    flex: 1,
    whiteSpace: "pre-wrap",
    lineHeight: 1.6,
    color: theme.colors.contentPrimary,
  });
  return (
    <MessagePrimitive.Root className={msgRow}>
      <div className={role}>you</div>
      <div className={userBody}>
        <MessagePrimitive.Parts />
      </div>
    </MessagePrimitive.Root>
  );
}

function AssistantMessage() {
  const [css, theme] = useStyletron();
  const msgRow = css({ display: "flex", gap: theme.sizing.scale400 });
  const role = css({
    minWidth: "2.5rem",
    paddingTop: "4px",
    fontSize: "10px",
    fontWeight: 600,
    textTransform: "uppercase",
    letterSpacing: "0.06em",
    color: theme.colors.contentSecondary,
  });
  const asstBody = css({
    flex: 1,
    whiteSpace: "pre-wrap",
    lineHeight: 1.6,
    color: theme.colors.contentPrimary,
    borderLeftWidth: "2px",
    borderLeftStyle: "solid",
    borderLeftColor: theme.colors.accent,
    paddingLeft: theme.sizing.scale400,
  });
  return (
    <MessagePrimitive.Root className={msgRow}>
      <div className={role}>pi</div>
      <div className={asstBody}>
        <MessagePrimitive.Parts />
      </div>
    </MessagePrimitive.Root>
  );
}
