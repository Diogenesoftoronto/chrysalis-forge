import type { ReactNode } from "react";
import ReactMarkdown from "react-markdown";
import { useStyletron } from "baseui";

export function MarkdownBody({ children }: { children: string }) {
  const [css, theme] = useStyletron();
  const body = css({
    fontSize: theme.typography.font200.fontSize,
    lineHeight: theme.typography.font200.lineHeight,
    color: theme.colors.contentSecondary,
    maxWidth: "none",
    " p": {
      marginTop: "0.5em",
      marginBottom: "0.5em",
    },
    " ul": {
      marginTop: "0.5em",
      marginBottom: "0.5em",
      paddingLeft: "1.25rem",
    },
    " code": {
      fontFamily:
        'ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, monospace',
      fontSize: "0.9em",
      color: theme.colors.accent,
    },
    " pre": {
      padding: theme.sizing.scale400,
      borderRadius: theme.borders.radius200,
      backgroundColor: theme.colors.backgroundTertiary,
      overflow: "auto",
    },
    " a": {
      color: theme.colors.accent,
    },
  });
  return (
    <div className={body}>
      <ReactMarkdown>{children}</ReactMarkdown>
    </div>
  );
}

export function InlineCode({ children }: { children: ReactNode }) {
  const [css, theme] = useStyletron();
  return (
    <code
      className={css({
        fontFamily:
          'ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, monospace',
        fontSize: "0.9em",
        color: theme.colors.accent,
      })}
    >
      {children}
    </code>
  );
}
