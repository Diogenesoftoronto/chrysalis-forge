import ReactMarkdown from "react-markdown";

interface Post {
  slug: string;
  title: string;
  date: string;
  summary: string;
  body: string;
}

const POSTS: Post[] = [
  {
    slug: "modular-extensions",
    title: "A leaner core and optional @chrysalis/* extensions",
    date: "2026-06-02",
    summary:
      "Chrysalis Forge 0.5.0 splits the optional tool surface into installable packages that load from config, keeping the self-evolution core lean.",
    body: `Chrysalis Forge has always shipped a large tool surface — version control,
web access, a knowledge graph, sub-agent spawning, caching — all compiled into
one binary. That made the core heavier than its one real job: **self-evolution**.

**0.5.0 splits the optional tools into standalone \`@chrysalis/*\` packages** and
loads them from configuration, so the core stays focused while the extras become
opt-in.

## What moved out

Five tool groups now live in their own packages:

- \`@chrysalis/vcs-jj\` — Jujutsu version control
- \`@chrysalis/web\` — web fetch and search
- \`@chrysalis/cache\` — TTL cache with tag-based invalidation
- \`@chrysalis/rdf\` — RDF triplestore and vector search
- \`@chrysalis/concurrent\` — parallel sub-agent tasks

The core keeps everything that the evolution loop depends on: planning,
decomposition, priority/profile selection, the GEPA/MAP-Elites engine, the tool
evolution registry, dynamic stores, judging, test generation, git, and rollback.

## Turning extensions on

Each project opts in through an \`extensions\` array in \`chrysalis.config.json\`:

\`\`\`json
{
  "extensions": [
    "@chrysalis/vcs-jj",
    "@chrysalis/web",
    "@chrysalis/cache",
    "@chrysalis/rdf",
    "@chrysalis/concurrent"
  ]
}
\`\`\`

At startup the extension loader resolves each entry — first from the local
\`packages/\` workspace, then as a bare npm specifier when installed separately —
and registers its tools **and** slash commands. A disabled extension contributes
neither, and a missing or broken package never takes down the core agent.

## Coupling where it earns its keep

\`@chrysalis/web\` now depends on \`@chrysalis/cache\` instead of carrying a private
copy of the cache logic. Web fetches and searches share the same tagged,
TTL-bounded store as everything else — one cache, one format.

## Cleanup along the way

Enabling \`noUnusedLocals\` turned up a real bug hiding behind a "phantom" local:
the tool-evolution novelty score was computed against an empty array, so every
candidate looked maximally novel and **nothing was ever rejected as a duplicate**.
The fix wires the accumulated variants back into the score. We also consolidated a
\`ProviderConfig\` interface that had been copy-pasted into six files, and routed the
Thompson-sampling bandit update through its intended helper.

## Getting it

The packages publish under the \`@chrysalis/*\` scope and ship inside the
\`chrysalis-forge\` tarball for monorepo use. Add the ones you want to
\`extensions\`, or install them individually — the core no longer assumes any of
them are present.`
  }
];

export default function Blog() {
  return (
    <div className="mx-auto max-w-[1140px] space-y-6 px-4 py-8">
      <header>
        <p className="mb-3 font-mono text-xs font-bold uppercase tracking-widest text-dim">
          // Blog
        </p>
        <h1 className="font-display text-5xl tracking-wide text-foreground">
          BLOG
        </h1>
        <p className="mt-3 text-sm text-dim">
          Notes on the evolution of Chrysalis Forge.
        </p>
      </header>
      <div className="space-y-4">
        {POSTS.map((p) => (
          <article key={p.slug} className="border border-border bg-bg3 p-6">
            <p className="mb-2 font-mono text-xs uppercase tracking-widest text-dim">
              {p.date}
            </p>
            <h2 className="mb-3 font-display text-2xl tracking-wide text-foreground">
              {p.title}
            </h2>
            <div className="prose prose-invert max-w-none text-sm text-dim">
              <ReactMarkdown>{p.body}</ReactMarkdown>
            </div>
          </article>
        ))}
      </div>
    </div>
  );
}
