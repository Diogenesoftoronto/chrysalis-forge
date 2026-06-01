import ReactMarkdown from "react-markdown";
import { skills, stripFrontmatter } from "../lib/piContent";

export default function Skills() {
  return (
    <div className="mx-auto max-w-[1140px] space-y-6 px-4 py-8">
      <header>
        <p className="mb-3 font-mono text-xs font-bold uppercase tracking-widest text-dim">
          // Skills
        </p>
        <h1 className="font-display text-5xl tracking-wide text-foreground">
          SKILLS
        </h1>
        <p className="mt-3 text-sm text-dim">
          Source of truth lives in{" "}
          <code className="text-gold">pi/skills/</code>.
        </p>
      </header>
      <div className="space-y-4">
        {skills.map((s) => (
          <div key={s.id} className="border border-border bg-bg3 p-6">
            <h2 className="mb-3 font-display text-2xl tracking-wide text-foreground">
              {s.title}
            </h2>
            <div className="prose prose-invert max-w-none text-sm text-dim">
              <ReactMarkdown>{stripFrontmatter(s.body)}</ReactMarkdown>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
