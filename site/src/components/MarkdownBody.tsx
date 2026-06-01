import type { ReactNode } from "react";
import ReactMarkdown from "react-markdown";

export function MarkdownBody({ children }: { children: string }) {
  return (
    <div className="text-sm leading-relaxed text-dim">
      <ReactMarkdown>{children}</ReactMarkdown>
    </div>
  );
}

export function InlineCode({ children }: { children: ReactNode }) {
  return <code className="font-mono text-[0.9em] text-teal">{children}</code>;
}
