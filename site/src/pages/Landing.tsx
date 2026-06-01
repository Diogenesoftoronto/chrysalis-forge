import { useEffect, useRef, useState } from "react";
import { Link } from "@tanstack/react-router";
import { useReveal, useStaggerReveal } from "../lib/useReveal";

/* ─────────────────────────────────────────
   Terminal demo data
   ───────────────────────────────────────── */
const DEMO_LINES = [
  { text: "$ chrysalis -i", cls: "t-cmd", delay: 400 },
  { text: "", delay: 150 },
  { text: "◆ CHRYSALIS FORGE — Evolution Engine Active", cls: "t-brand", delay: 250 },
  { text: "  Session [a7f3b2] · Model: gpt-5.4 · Budget: $5.00", cls: "t-dim", delay: 100 },
  { text: "", delay: 350 },
  { text: "[YOU]> analyze src/ — find performance bottlenecks", cls: "t-user", delay: 700, typing: true },
  { text: "", delay: 200 },
  { text: "[FORGE] Spawning 2 researcher sub-agents...", cls: "t-agent", delay: 500 },
  { text: "  ↳ [task:a1] researcher → src/core/", cls: "t-tool", delay: 200 },
  { text: "  ↳ [task:a2] researcher → src/llm/", cls: "t-tool", delay: 200 },
  { text: "", delay: 900 },
  { text: "[FORGE] Both agents returned. Synthesizing...", cls: "t-agent", delay: 600 },
  { text: "", delay: 200 },
  { text: "  ■ optimizer-gepa.rkt: redundant evaluations (lines 88–103)", cls: "", delay: 120 },
  { text: "  ■ openai-client.rkt: retry loop fires too aggressively", cls: "", delay: 120 },
  { text: "  ■ context compaction threshold too high (saves at 95%)", cls: "", delay: 120 },
  { text: "", delay: 500 },
  { text: "[FORGE] Propose patches? [y/N]: ", cls: "t-agent", delay: 400 },
  { text: "  patch_file optimizer-gepa.rkt (lines 88–103)", cls: "t-tool", delay: 300 },
  { text: "  ✓ Applied. Est. 18% cost reduction.", cls: "t-ok", delay: 200 },
  { text: "", delay: 200 },
  { text: "[YOU]> _", cls: "t-user t-prompt", delay: 400 },
];

/* ─────────────────────────────────────────
   Utility components
   ───────────────────────────────────────── */
function SectionLabel({ children }: { children: React.ReactNode }) {
  return (
    <p className="mb-4 font-mono text-xs font-bold uppercase tracking-widest text-dim">
      // {children}
    </p>
  );
}

function Btn({
  href,
  to,
  variant,
  children,
}: {
  href?: string;
  to?: string;
  variant: "gold" | "teal" | "ghost";
  children: React.ReactNode;
}) {
  const base =
    "inline-block border-2 font-mono text-xs font-bold uppercase tracking-wider px-5 py-2.5 transition-colors no-underline";
  const v = {
    gold: "border-gold text-gold hover:bg-gold hover:text-background",
    teal: "border-teal text-teal hover:bg-teal hover:text-background",
    ghost: "border-border2 text-dim hover:border-foreground hover:text-foreground",
  };
  if (to) {
    return (
      <Link to={to} className={`${base} ${v[variant]}`}>
        {children}
      </Link>
    );
  }
  return (
    <a href={href} className={`${base} ${v[variant]}`}>
      {children}
    </a>
  );
}

function Badge({
  color,
  children,
}: {
  color: "gold" | "teal" | "purple" | "orange" | "red";
  children: React.ReactNode;
}) {
  const colors = {
    gold: "text-gold",
    teal: "text-teal",
    purple: "text-purple",
    orange: "text-orange",
    red: "text-red",
  };
  return (
    <span
      className={`inline-block border border-current px-2 py-0.5 font-mono text-xs font-bold uppercase tracking-wider ${colors[color]}`}
    >
      {children}
    </span>
  );
}

/* ─────────────────────────────────────────
   Terminal
   ───────────────────────────────────────── */
function Terminal() {
  const ref = useRef<HTMLDivElement>(null);
  const [lines, setLines] = useState<
    Array<{ text: string; cls: string; typed: boolean }>
  >([]);

  useEffect(() => {
    let cancelled = false;
    const terminal = ref.current;
    if (!terminal) return;

    async function run() {
      for (const line of DEMO_LINES) {
        if (cancelled) return;
        await new Promise((r) => setTimeout(r, line.delay || 100));
        if (cancelled) return;

        if (line.typing) {
          setLines((prev) => [
            ...prev,
            { text: "", cls: line.cls ?? "", typed: true },
          ]);
          for (const ch of line.text) {
            if (cancelled) return;
            await new Promise((r) =>
              setTimeout(r, 28 + Math.random() * 22),
            );
            setLines((prev) => {
              const next = [...prev];
              next[next.length - 1] = {
                text: next[next.length - 1].text + ch,
                cls: line.cls ?? "",
                typed: true,
              };
              return next;
            });
          }
        } else {
          setLines((prev) => [
            ...prev,
            { text: line.text, cls: line.cls ?? "", typed: false },
          ]);
        }

        requestAnimationFrame(() => {
          if (ref.current) ref.current.scrollTop = ref.current.scrollHeight;
        });
      }
    }

    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            run();
            observer.disconnect();
          }
        });
      },
      { threshold: 0.3 },
    );

    observer.observe(terminal);
    return () => {
      cancelled = true;
      observer.disconnect();
    };
  }, []);

  return (
    <div className="overflow-hidden border border-border2 border-t-[3px] border-t-teal">
      <div className="flex items-center gap-2 border-b border-border bg-bg3 px-4 py-2">
        <span className="h-2.5 w-2.5 rounded-full bg-[#ff5f57]" />
        <span className="h-2.5 w-2.5 rounded-full bg-[#febc2e]" />
        <span className="h-2.5 w-2.5 rounded-full bg-[#28c840]" />
        <span className="ml-auto font-mono text-xs tracking-wider text-dim">
          chrysalis-forge
        </span>
      </div>
      <div
        ref={ref}
        className="min-h-[340px] overflow-hidden p-4 font-mono text-sm leading-relaxed"
      >
        {lines.map((l, i) => (
          <span key={i} className={`block whitespace-pre ${l.cls}`}>
            {l.cls.includes("t-prompt") && l.text.endsWith("_")
              ? l.text.slice(0, -1)
              : l.text}
            {l.cls.includes("t-prompt") && (
              <span className="animate-blink text-teal">▌</span>
            )}
          </span>
        ))}
      </div>
    </div>
  );
}

/* ─────────────────────────────────────────
   Copy block
   ───────────────────────────────────────── */
function CopyBlock({ text }: { text: string }) {
  const [copied, setCopied] = useState(false);
  return (
    <div className="mb-2 flex items-center justify-between gap-2 border border-border bg-background px-4 py-3">
      <code className="flex-1 font-mono text-sm text-green">{text}</code>
      <button
        onClick={() => {
          navigator.clipboard.writeText(text).then(() => {
            setCopied(true);
            setTimeout(() => setCopied(false), 2000);
          });
        }}
        className={`shrink-0 border px-2 py-1 font-mono text-xs font-bold uppercase tracking-wider transition-colors ${
          copied
            ? "border-teal text-teal"
            : "border-border2 text-dim hover:border-foreground hover:text-foreground"
        }`}
      >
        {copied ? "Copied!" : "Copy"}
      </button>
    </div>
  );
}

/* ─────────────────────────────────────────
   Main landing page
   ───────────────────────────────────────── */
export default function Landing() {
  const heroR = useReveal();
  const statsR = useReveal();
  const manifestoR = useReveal();
  const pillarsR = useReveal();
  const evolutionR = useReveal();
  const toolsR = useReveal();
  const securityR = useReveal();
  const modesR = useReveal();
  const installR = useReveal();
  const featuresR = useReveal();
  const demosR = useReveal();
  const piR = useReveal();
  const papersR = useReveal();

  const statsS = useStaggerReveal(4);
  const pillarsS = useStaggerReveal(3);
  const toolsS = useStaggerReveal(3);
  const securityS = useStaggerReveal(5);
  const modesS = useStaggerReveal(4);
  const featuresS = useStaggerReveal(6);
  const demosS = useStaggerReveal(6);
  const piS = useStaggerReveal(3);
  const papersS = useStaggerReveal(6);

  return (
    <div className="text-foreground">
      {/* ── HERO ───────────────────────── */}
      <div ref={heroR.ref} className={`reveal ${heroR.isRevealed ? "revealed" : ""}`}>
        <section className="border-b border-border bg-gradient-radial bg-dots px-4 py-16 md:py-24">
          <div className="mx-auto grid max-w-[1140px] items-center gap-10 md:grid-cols-2">
            <div>
              <p className="mb-4 font-mono text-sm uppercase tracking-[0.25em] text-teal">
                Self-Optimizing AI Agent Harness
              </p>
              <h1 className="mb-6 font-display leading-[0.92] tracking-wide">
                <span className="block text-gold md:text-[6rem] text-[4.5rem]">
                  NOT TRAINED.
                </span>
                <span className="block text-foreground md:text-[6rem] text-[4.5rem]">
                  EVOLVED.
                </span>
              </h1>
              <p className="mb-3 text-lg font-medium text-foreground">
                The agent that learns to be better at being an agent.
              </p>
              <p className="mb-8 max-w-md text-sm text-dim">
                MAP-Elites quality-diversity search. GEPA prompt evolution.
                Tiered sandboxing. Parallel sub-agents. Not trained on
                corpora — evolved through competition against itself.
              </p>
              <div className="flex flex-wrap gap-3">
                <Btn to="/chat" variant="gold">
                  Open Chat
                </Btn>
                <Btn to="/settings" variant="ghost">
                  Set API Key
                </Btn>
              </div>
              <p className="mt-10 font-mono text-xs tracking-wider text-dim">
                Made by{" "}
                <span className="text-gold">
                  <a href="https://dio.computer">Diogenesoftoronto</a>
                </span>
                . Free &amp; open source. GPL-3.0.
              </p>
            </div>
            <Terminal />
          </div>
        </section>
      </div>

      {/* ── STATS ───────────────────────── */}
      <div ref={statsR.ref} className={`reveal ${statsR.isRevealed ? "revealed" : ""}`}>
        <div className="border-b border-border bg-bg3 px-4 py-5">
          <div ref={statsS.ref} className="mx-auto flex max-w-[1140px] flex-wrap items-center justify-between gap-6">
            {[
              { num: "∞", label: "Agent Variants" },
              { num: "0", label: "Runtime Errors" },
              { num: "$0.00", label: "Locked-in Cost" },
              { num: "1-Click", label: "Evolve Prompts" },
            ].map((s, i) => (
              <div
                key={s.label}
                className={`reveal flex items-baseline gap-2 ${statsS.revealed ? "revealed" : ""}`}
                style={{ transitionDelay: statsS.getDelay(i) }}
              >
                <span className="font-display text-3xl text-gold tracking-wide">
                  {s.num}
                </span>
                <span className="font-mono text-xs font-bold uppercase tracking-wider text-dim">
                  {s.label}
                </span>
              </div>
            ))}
          </div>
        </div>
      </div>

      {/* ── MANIFESTO ───────────────────── */}
      <div ref={manifestoR.ref} className={`reveal ${manifestoR.isRevealed ? "revealed" : ""}`}>
        <div className="bg-gold px-4 py-8">
          <div className="mx-auto flex max-w-[1140px] flex-wrap items-center gap-8">
            <span className="shrink-0 font-mono text-6xl font-bold text-background">
              λ
            </span>
            <div>
              <h2 className="font-display text-3xl leading-tight tracking-wide text-background md:text-5xl">
                YOU DONT NEED MORE LLM WRAPPERS — YOU NEED AN ENGINE THAT
                GETS BETTER.
              </h2>
              <p className="mt-2 text-sm text-[#333344]">
                Every conversation is a breeding ground. Every tool call is a
                fitness signal. Every generation closes the loop.
              </p>
            </div>
          </div>
        </div>
      </div>

      {/* ── PILLARS ─────────────────────── */}
      <div ref={pillarsR.ref} className={`reveal ${pillarsR.isRevealed ? "revealed" : ""}`}>
        <section className="border-b border-border px-4 py-20">
          <div className="mx-auto max-w-[1140px]">
            <div ref={pillarsS.ref} className="grid border border-border md:grid-cols-3">
              {[
                {
                  icon: "🧬",
                  title: "EVOLVE",
                  text: "GEPA reflective prompt evolution outperforms RL-based methods. Prompts compete. Winners reproduce. Fitness improves.",
                  color: "text-teal",
                },
                {
                  icon: "🛡️",
                  title: "SANDBOX",
                  text: "Five-tier permission system. Every tool call is opt-in. The agent proposes, you approve. No surprises, ever.",
                  color: "text-gold",
                },
                {
                  icon: "⚡",
                  title: "ORCHESTRATE",
                  text: "Parallel sub-agents with shared memory. Map-reduce workflows. Tool chains that compose like functions.",
                  color: "text-orange",
                },
              ].map((p, i) => {
                const glow =
                  p.color === "text-gold" ? "hover-glow-gold" : "hover-glow";
                return (
                  <div
                    key={i}
                    className={`reveal relative overflow-hidden border-b border-border p-8 last:border-b-0 md:border-b-0 md:border-r md:last:border-r-0 hover-lift ${glow} transition-shadow transition-transform duration-200 ${pillarsS.revealed ? "revealed" : ""}`}
                    style={{ transitionDelay: pillarsS.getDelay(i) }}
                  >
                    <span className="pointer-events-none absolute bottom-[-1rem] right-2 select-none font-display text-[5rem] leading-none text-border">
                      {i + 1}
                    </span>
                    <span className={`mb-3 block text-2xl ${p.color}`}>
                      {p.icon}
                    </span>
                    <h3 className={`mb-3 font-display text-3xl tracking-wide ${p.color}`}>
                      {p.title}
                    </h3>
                    <p className="text-sm leading-relaxed text-dim">{p.text}</p>
                  </div>
                );
              })}
            </div>
          </div>
        </section>
      </div>

      {/* ── EVOLUTION ───────────────────── */}
      <div ref={evolutionR.ref} className={`reveal ${evolutionR.isRevealed ? "revealed" : ""}`}>
        <section
          id="evolution"
          className="border-b border-border bg-bg2 bg-grid px-4 py-20"
        >
          <div className="mx-auto grid max-w-[1140px] items-start gap-12 md:grid-cols-2">
            <div>
              <SectionLabel>How It Evolves</SectionLabel>
              <h2 className="mb-6 font-display text-5xl leading-[0.92] tracking-wide md:text-[5.5rem]">
                MUTATE. <span className="text-teal">STAGE.</span> SELECT.
              </h2>
              <p className="mb-4 text-sm leading-relaxed text-dim">
                Every prompt is a genome. Every response is a phenotype. We run
                MAP-Elites quality-diversity search over your prompts, scoring
                on latency, cost, accuracy, and diversity. The best prompts
                survive. The rest are archived for later rediscovery.
              </p>
              <p className="mb-6 text-sm leading-relaxed text-dim">
                GEPA (General Evolvable Prompting Architecture) uses reflective
                self-improvement: the agent evaluates its own outputs against a
                rubric, generates variants, and keeps the ones that score higher.
              </p>
              <div className="space-y-0">
                {[
                  { num: "1", title: "Mutate", desc: "Generate prompt variants via reflection and perturbation" },
                  { num: "2", title: "Stage", desc: "Test each variant against holdout problems with scoring" },
                  { num: "3", title: "Archive", desc: "Store in MAP-Elites niche map by latency/cost/accuracy" },
                  { num: "4", title: "Select", desc: "Choose the highest-scoring variant for live use" },
                  { num: "5", title: "Repeat", desc: "Continuous evolution — each session feeds the next" },
                ].map((step) => (
                  <div
                    key={step.num}
                    className="flex gap-4 border-b border-border py-3.5 last:border-b-0"
                  >
                    <span className="w-6 shrink-0 font-display text-2xl text-gold">
                      {step.num}
                    </span>
                    <div>
                      <h4 className="text-sm font-semibold text-foreground">
                        {step.title}
                      </h4>
                      <p className="text-xs text-dim">{step.desc}</p>
                    </div>
                  </div>
                ))}
              </div>
            </div>
            <div className="border border-border bg-bg3 p-6">
              <pre className="overflow-x-auto font-mono text-sm leading-relaxed">
                <span className="text-dim"># Run evolution on a prompt</span>
                {"\n"}
                <span className="text-gold">$</span> chrysalis{" "}
                <span className="text-teal">evolve</span> prompt.md{"\n\n"}
                <span className="text-dim"># Interactive — select best variant</span>
                {"\n"}
                <span className="text-gold">$</span> chrysalis{" "}
                <span className="text-teal">-i</span>{"\n"}
                <span className="text-dim">
                  [FORGE] 5 variants evaluated
                </span>
                {"\n"}
                <span className="text-green">
                  [FORGE] Variant #3 selected — 14% faster, same accuracy
                </span>
              </pre>
            </div>
          </div>
        </section>
      </div>

      {/* ── TOOL SYSTEM ─────────────────── */}
      <div ref={toolsR.ref} className={`reveal ${toolsR.isRevealed ? "revealed" : ""}`}>
        <section id="tools" className="border-b border-border px-4 py-20">
          <div className="mx-auto mb-10 flex max-w-[1140px] flex-wrap items-end justify-between gap-4">
            <div>
              <SectionLabel>Tool System</SectionLabel>
              <h2 className="font-display text-5xl tracking-wide md:text-[4rem]">
                EVERYTHING IS A TOOL
              </h2>
            </div>
            <Badge color="teal">Composable</Badge>
          </div>
          <div ref={toolsS.ref} className="mx-auto grid max-w-[1140px] gap-px border border-border bg-border md:grid-cols-3">
            {[
              {
                icon: "🔧",
                title: "Core Tools",
                desc: "Built-in primitives for agent operation",
                tools: [
                  "file_read / file_write",
                  "shell_exec (sandboxed)",
                  "web_search / web_fetch",
                  "think / plan / commit",
                ],
              },
              {
                icon: "📊",
                title: "Evolution Tools",
                desc: "Inspect and evolve the agent itself",
                tools: [
                  "evolve_system — evolve prompts",
                  "archive_variant — store candidate",
                  "judge_output — score responses",
                  "compare_variants — A/B test",
                ],
              },
              {
                icon: "🧠",
                title: "Memory Tools",
                desc: "Persistent knowledge across sessions",
                tools: [
                  "store_memory — save facts",
                  "recall_memory — retrieve context",
                  "vector_search — semantic lookup",
                  "rdf_query — graph traversal",
                ],
              },
            ].map((panel, i) => (
              <div
                key={i}
                className={`reveal relative overflow-hidden bg-background p-7 transition-colors hover:bg-bg3 hover-lift hover-glow ${toolsS.revealed ? "revealed" : ""}`}
                style={{ transitionDelay: toolsS.getDelay(i) }}
              >
                <span className="pointer-events-none absolute right-2 top-[-1rem] select-none font-display text-[4.5rem] leading-none text-bg3 transition-colors">
                  {i + 1}
                </span>
                <span className="mb-2 block text-xl">{panel.icon}</span>
                <h3 className="mb-2 font-display text-2xl tracking-wide">
                  {panel.title}
                </h3>
                <p className="mb-4 text-xs leading-relaxed text-dim">
                  {panel.desc}
                </p>
                <ul className="space-y-1">
                  {panel.tools.map((t) => (
                    <li
                      key={t}
                      className="font-mono text-xs text-teal before:pr-1 before:text-border2 before:content-['→_']"
                    >
                      {t}
                    </li>
                  ))}
                </ul>
              </div>
            ))}
          </div>
        </section>
      </div>

      {/* ── SECURITY ────────────────────── */}
      <div ref={securityR.ref} className={`reveal ${securityR.isRevealed ? "revealed" : ""}`}>
        <section
          id="security"
          className="border-b border-border bg-bg2 px-4 py-20"
        >
          <div className="mx-auto mb-10 max-w-[1140px]">
            <SectionLabel>Security Model</SectionLabel>
            <h2 className="mb-3 font-display text-5xl tracking-wide md:text-[4rem]">
              TIERED SANDBOXING
            </h2>
            <p className="max-w-md text-sm text-dim">
              Five permission levels. The agent cannot escalate without your
              explicit approval. Every tool call is logged. Every mutation is
              reversible.
            </p>
          </div>
          <div ref={securityS.ref} className="mx-auto grid max-w-[1140px] gap-4 sm:grid-cols-2 md:grid-cols-5">
            {[
              {
                level: "0",
                name: "Read-Only",
                color: "text-dim",
                border: "border-t-dim",
                perms: ["Read files", "Search web", "Query memory"],
              },
              {
                level: "1",
                name: "Write",
                color: "text-teal",
                border: "border-t-teal",
                perms: ["Write files", "Edit in-place", "Git commit"],
              },
              {
                level: "2",
                name: "Execute",
                color: "text-gold",
                border: "border-t-gold",
                perms: ["Shell commands", "Package install", "Build/run"],
              },
              {
                level: "3",
                name: "Network",
                color: "text-orange",
                border: "border-t-orange",
                perms: ["HTTP requests", "API calls", "Webhook POST"],
              },
              {
                level: "∞",
                name: "Admin",
                color: "text-red",
                border: "border-t-red",
                perms: ["System-level", "Env modify", "Irreversible"],
              },
            ].map((tier, i) => {
              const glow =
                tier.color === "text-gold"
                  ? "hover-glow-gold"
                  : tier.color === "text-red"
                    ? "hover-glow-red"
                    : "hover-glow";
              return (
                <div
                  key={tier.name}
                  className={`reveal border border-border ${tier.border} border-t-2 bg-bg3 p-5 hover-lift ${glow} transition-shadow transition-transform duration-200 ${securityS.revealed ? "revealed" : ""}`}
                  style={{ transitionDelay: securityS.getDelay(i) }}
                >
                  <div className={`mb-3 font-display text-5xl leading-none ${tier.color}`}>
                    {tier.level}
                  </div>
                  <div className={`mb-3 font-mono text-xs font-bold uppercase tracking-widest ${tier.color}`}>
                    {tier.name}
                  </div>
                  <ul className="space-y-1">
                    {tier.perms.map((p) => (
                      <li
                        key={p}
                        className="flex items-center gap-2 text-xs text-dim before:text-dim before:content-['·']"
                      >
                        {p}
                      </li>
                    ))}
                  </ul>
                </div>
              );
            })}
          </div>
        </section>
      </div>

      {/* ── MODES ───────────────────────── */}
      <div ref={modesR.ref} className={`reveal ${modesR.isRevealed ? "revealed" : ""}`}>
        <section id="modes" className="border-b border-border px-4 py-20">
          <div className="mx-auto max-w-[1140px]">
            <SectionLabel>Operating Modes</SectionLabel>
            <h2 className="font-display text-5xl tracking-wide md:text-[4rem]">
              FOUR MODES. ONE ENGINE.
            </h2>
            <div ref={modesS.ref} className="mt-8 grid gap-4 sm:grid-cols-2 md:grid-cols-4">
              {[
                {
                  name: "Ask",
                  color: "text-teal",
                  border: "border-l-teal",
                  cmd: "chrysalis ask <question>",
                  desc: "Direct conversational mode. No tools, no side effects. Just reasoning.",
                },
                {
                  name: "Architect",
                  color: "text-gold",
                  border: "border-l-gold",
                  cmd: "chrysalis architect <task>",
                  desc: "Design mode. Plans, diagrams, tradeoff analysis. Builds the blueprint.",
                },
                {
                  name: "Code",
                  color: "text-orange",
                  border: "border-l-orange",
                  cmd: "chrysalis code <task>",
                  desc: "Implementation mode. Writes, tests, and commits code with sandboxed execution.",
                },
                {
                  name: "Semantic",
                  color: "text-purple",
                  border: "border-l-purple",
                  cmd: "chrysalis semantic <query>",
                  desc: "Knowledge mode. Queries RDF stores, vector memory, and semantic graphs.",
                },
              ].map((mode, i) => {
                const glow =
                  mode.color === "text-gold"
                    ? "hover-glow-gold"
                    : mode.color === "text-purple"
                      ? "hover-glow-purple"
                      : "hover-glow";
                return (
                  <div
                    key={mode.name}
                    className={`reveal border border-border p-6 ${mode.border} border-l-[3px] hover-lift ${glow} transition-shadow transition-transform duration-200 ${modesS.revealed ? "revealed" : ""}`}
                    style={{ transitionDelay: modesS.getDelay(i) }}
                  >
                    <h3 className={`mb-1 font-display text-2xl tracking-wide ${mode.color}`}>
                      {mode.name}
                    </h3>
                    <code className="mb-4 block font-mono text-xs text-dim">
                      {mode.cmd}
                    </code>
                    <p className="text-xs leading-relaxed text-dim">
                      {mode.desc}
                    </p>
                  </div>
                );
              })}
            </div>
          </div>
        </section>
      </div>

      {/* ── INSTALL ─────────────────────── */}
      <div ref={installR.ref} className={`reveal ${installR.isRevealed ? "revealed" : ""}`}>
        <section
          id="install"
          className="border-b border-border bg-bg2 px-4 py-20"
        >
          <div className="mx-auto grid max-w-[1140px] items-start gap-12 md:grid-cols-[1.2fr_1fr]">
            <div>
              <SectionLabel>Installation</SectionLabel>
              <h2 className="mb-6 font-display text-5xl tracking-wide md:text-[4rem]">
                GET STARTED IN{" "}
                <span className="text-teal">30 SECONDS</span>
              </h2>
              <div className="space-y-6">
                <div className="flex gap-4">
                  <div className="flex h-8 w-8 shrink-0 items-center justify-center bg-gold font-mono text-sm font-bold text-background">
                    1
                  </div>
                  <div className="flex-1">
                    <h4 className="mb-2 font-mono text-xs font-bold uppercase tracking-wider text-foreground">
                      Install via npm
                    </h4>
                    <CopyBlock text="npm install -g chrysalis-forge" />
                  </div>
                </div>
                <div className="flex gap-4">
                  <div className="flex h-8 w-8 shrink-0 items-center justify-center bg-gold font-mono text-sm font-bold text-background">
                    2
                  </div>
                  <div className="flex-1">
                    <h4 className="mb-2 font-mono text-xs font-bold uppercase tracking-wider text-foreground">
                      Set your API key
                    </h4>
                    <CopyBlock text="export OPENAI_API_KEY=sk-..." />
                    <p className="text-xs text-dim">
                      Or use Anthropic, Google, Groq, or any OpenAI-compatible
                      endpoint.
                    </p>
                  </div>
                </div>
                <div className="flex gap-4">
                  <div className="flex h-8 w-8 shrink-0 items-center justify-center bg-gold font-mono text-sm font-bold text-background">
                    3
                  </div>
                  <div className="flex-1">
                    <h4 className="mb-2 font-mono text-xs font-bold uppercase tracking-wider text-foreground">
                      Run interactive mode
                    </h4>
                    <CopyBlock text="chrysalis -i" />
                    <p className="text-xs text-dim">
                      Start evolving. Every command feeds the learning loop.
                    </p>
                  </div>
                </div>
              </div>
            </div>
            <div className="border border-border bg-bg3 p-6">
              <h4 className="mb-4 font-display text-xl tracking-wide text-gold">
                Environment Variables
              </h4>
              <div className="space-y-0">
                {[
                  { key: "OPENAI_API_KEY", desc: "Your API key (required)", req: true },
                  { key: "MODEL", desc: "Model to use (default: gpt-5.4)", req: false },
                  { key: "OPENAI_API_BASE", desc: "Custom endpoint URL", req: false },
                  { key: "CHRYSALIS_TIER", desc: "Security tier 0-3 (default: 1)", req: false },
                  { key: "CHRYSALIS_EVOLVE", desc: "Enable evolution (default: true)", req: false },
                  { key: "CHRYSALIS_DEBUG", desc: "Debug mode with traces", req: false },
                ].map((env) => (
                  <div
                    key={env.key}
                    className="border-b border-border py-2 last:border-b-0"
                  >
                    <div className="font-mono text-xs text-teal">
                      {env.key}
                      {env.req && (
                        <span className="ml-2 font-mono text-[10px] font-bold uppercase tracking-wider text-red">
                          Required
                        </span>
                      )}
                      {!env.req && (
                        <span className="ml-2 font-mono text-[10px] font-bold uppercase tracking-wider text-dim">
                          Optional
                        </span>
                      )}
                    </div>
                    <div className="mt-0.5 text-xs text-dim">{env.desc}</div>
                  </div>
                ))}
              </div>
            </div>
          </div>
        </section>
      </div>

      {/* ── FEATURES ────────────────────── */}
      <div ref={featuresR.ref} className={`reveal ${featuresR.isRevealed ? "revealed" : ""}`}>
        <section className="border-b border-border px-4 py-20">
          <div className="mx-auto max-w-[1140px]">
            <SectionLabel>Features</SectionLabel>
            <h2 className="mb-10 font-display text-5xl tracking-wide md:text-[4rem]">
              WHAT MAKES IT DIFFERENT
            </h2>
            <div ref={featuresS.ref} className="grid gap-6 md:grid-cols-2">
              {[
                {
                  title: "Pi Terminal-First Agent",
                  desc: "The pi agent brings terminal-first workflows to your browser. Architect, review, and ship tasks with architect / review / ship prompts. Terminal skills keep work focused on the shell.",
                  badge: "Browser UI",
                  color: "text-teal",
                },
                {
                  title: "GEPA Prompt Evolution",
                  desc: "Reflective self-improvement that outperforms RL-based methods. The /evolve command and evolve_system tool mutate, stage, archive, and select prompt variants continuously.",
                  badge: "Evolution",
                  color: "text-gold",
                },
                {
                  title: "MAP-Elites Archive",
                  desc: "Quality-diversity optimization maintains a library of agent variants. Each niche maps latency, cost, and accuracy — so you always have the right tool for the job.",
                  badge: "Archive",
                  color: "text-purple",
                },
                {
                  title: "Tiered Sandboxing",
                  desc: "Five security levels from read-only to god-mode. Every tool call is opt-in and logged. No surprises, no unauthorized changes.",
                  badge: "Security",
                  color: "text-orange",
                },
                {
                  title: "Parallel Sub-Agents",
                  desc: "Spawn researcher, reviewer, and executor agents simultaneously. Shared memory means they collaborate without stepping on each other.",
                  badge: "Scale",
                  color: "text-teal",
                },
                {
                  title: "RDF Semantic Memory",
                  desc: "Knowledge graphs built on temporal RDF stores. Agents reason over time-structured information with vector-backed semantic search.",
                  badge: "Memory",
                  color: "text-red",
                },
              ].map((f, i) => {
                const glow =
                  f.badge === "Evolution"
                    ? "hover-glow-gold"
                    : f.badge === "Archive"
                      ? "hover-glow-purple"
                      : f.badge === "Memory"
                        ? "hover-glow-red"
                        : "hover-glow";
                return (
                  <div
                    key={f.title}
                    className={`reveal border border-border bg-bg3 p-6 hover-lift ${glow} transition-shadow transition-transform duration-200 ${featuresS.revealed ? "revealed" : ""}`}
                    style={{ transitionDelay: featuresS.getDelay(i) }}
                  >
                    <div className="mb-3 flex items-center gap-3">
                      <Badge
                        color={
                          f.badge === "Browser UI"
                            ? "teal"
                            : f.badge === "Evolution"
                              ? "gold"
                              : f.badge === "Archive"
                                ? "purple"
                                : f.badge === "Security"
                                  ? "orange"
                                  : f.badge === "Scale"
                                    ? "teal"
                                    : "red"
                        }
                      >
                        {f.badge}
                      </Badge>
                    </div>
                    <h3 className={`mb-2 font-display text-2xl tracking-wide ${f.color}`}>
                      {f.title}
                    </h3>
                    <p className="text-sm leading-relaxed text-dim">
                      {f.desc}
                    </p>
                  </div>
                );
              })}
            </div>
          </div>
        </section>
      </div>

      {/* ── DEMOS ───────────────────────── */}
      <div ref={demosR.ref} className={`reveal ${demosR.isRevealed ? "revealed" : ""}`}>
        <section className="border-b border-border bg-bg2 px-4 py-20">
          <div className="mx-auto max-w-[1140px]">
            <SectionLabel>Demos</SectionLabel>
            <h2 className="mb-10 font-display text-5xl tracking-wide md:text-[4rem]">
              SEE IT IN ACTION
            </h2>
            <div ref={demosS.ref} className="grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
              {[
                { file: "features-overview", title: "Feature Overview", desc: "Tour of the core features and capabilities" },
                { file: "cli-task", title: "CLI Task Execution", desc: "Running tasks from the terminal" },
                { file: "interactive-demo", title: "Interactive Mode", desc: "The -i flag in action" },
                { file: "evo-cycle", title: "Evolution Cycle", desc: "Mutate, stage, archive, select" },
                { file: "judge-eval", title: "Judge Evaluation", desc: "Scoring prompt variants" },
                { file: "priority-selection", title: "Priority Selection", desc: "Choosing the best candidate" },
              ].map((demo, i) => (
                <div
                  key={demo.file}
                  className={`reveal border border-border bg-background hover-lift hover-glow transition-shadow transition-transform duration-200 ${demosS.revealed ? "revealed" : ""}`}
                  style={{ transitionDelay: demosS.getDelay(i) }}
                >
                  <video
                    className="aspect-video w-full border-b border-border"
                    controls
                    preload="metadata"
                    poster={`/demos/${demo.file}.mp4`}
                  >
                    <source src={`/demos/${demo.file}.mp4`} type="video/mp4" />
                  </video>
                  <div className="p-4">
                    <h3 className="mb-1 font-display text-xl tracking-wide text-foreground">
                      {demo.title}
                    </h3>
                    <p className="text-xs text-dim">{demo.desc}</p>
                  </div>
                </div>
              ))}
            </div>
          </div>
        </section>
      </div>

      {/* ── WHAT IS PI ──────────────────── */}
      <div ref={piR.ref} className={`reveal ${piR.isRevealed ? "revealed" : ""}`}>
        <section className="border-b border-border px-4 py-20">
          <div className="mx-auto max-w-[1140px]">
            <SectionLabel>Pi Agent</SectionLabel>
            <h2 className="mb-6 font-display text-5xl tracking-wide md:text-[4rem]">
              THE PI AGENT
            </h2>
            <p className="mb-6 max-w-2xl text-sm leading-relaxed text-dim">
              Pi is the terminal-first sibling agent in Chrysalis Forge. It ships
              three task prompts —{" "}
              <code className="text-gold">architect</code>,{" "}
              <code className="text-gold">review</code>,{" "}
              <code className="text-gold">ship</code> — and skills that keep
              work focused on the shell.
            </p>
            <div ref={piS.ref} className="grid gap-6 md:grid-cols-3">
              {[
                { title: "Architect", desc: "Design concrete, migration-aware solutions. Thinks before it acts. Builds blueprints, not band-aids.", color: "border-l-gold" },
                { title: "Review", desc: "Surface severity-ordered findings. Catches issues before they ship. Formal review process, not gut feel.", color: "border-l-teal" },
                { title: "Ship", desc: "Implement minimal, verifiable changes. Tests pass before commit. No cowboy coding.", color: "border-l-orange" },
              ].map((item, i) => {
                const glow =
                  item.color === "border-l-gold" ? "hover-glow-gold" : "hover-glow";
                return (
                  <div
                    key={item.title}
                    className={`reveal border border-border bg-bg3 p-6 ${item.color} border-l-[3px] hover-lift ${glow} transition-shadow transition-transform duration-200 ${piS.revealed ? "revealed" : ""}`}
                    style={{ transitionDelay: piS.getDelay(i) }}
                  >
                    <h3 className="mb-2 font-display text-2xl tracking-wide text-foreground">
                      {item.title}
                    </h3>
                    <p className="text-sm leading-relaxed text-dim">
                      {item.desc}
                    </p>
                  </div>
                );
              })}
            </div>
            <div className="mt-8 flex flex-wrap gap-3">
              <Btn to="/chat" variant="gold">
                Open Chat
              </Btn>
              <Btn to="/prompts" variant="ghost">
                Browse Prompts
              </Btn>
              <Btn to="/skills" variant="ghost">
                View Skills
              </Btn>
            </div>
          </div>
        </section>
      </div>

      {/* ── PAPERS ──────────────────────── */}
      <div ref={papersR.ref} className={`reveal ${papersR.isRevealed ? "revealed" : ""}`}>
        <section id="papers" className="border-b border-border px-4 py-20">
          <div className="mx-auto max-w-[1140px]">
            <div className="mb-8">
              <SectionLabel>Theoretical Foundations</SectionLabel>
              <h2 className="font-display text-4xl tracking-wide md:text-[3rem]">
                BUILT ON REAL SCIENCE
              </h2>
              <p className="mt-2 text-sm text-dim">
                Not vibes. Not "inspired by." Direct implementations of
                peer-reviewed research.
              </p>
            </div>
            <div ref={papersS.ref} className="grid gap-px border border-border bg-border md:grid-cols-2">
              {[
                { title: "GEPA: General Evolvable Prompting Architecture", ref: "arXiv:2507.19457", url: "https://arxiv.org/abs/2507.19457", desc: "Reflective prompt evolution that outperforms RL-based methods on downstream tasks. The core of Chrysalis's evolve_system tool." },
                { title: "MAP-Elites: Illuminating Search Spaces through Quality Diversity", ref: "arXiv:1504.04909", url: "https://arxiv.org/abs/1504.04909", desc: "Quality-diversity optimization maintains a library of diverse high-performing candidates. Used for the agent variant archive." },
                { title: "MAKER: Million-Step Zero-Error Reasoning via Extreme Decomposition", ref: "arXiv:2511.09030", url: "https://arxiv.org/abs/2511.09030", desc: "Geometric task decomposition for zero-error reasoning at scale. Informs the decomposition system architecture." },
                { title: "Graphiti/Zep: Temporal Knowledge Graphs for Agent Memory", ref: "arXiv:2501.13956", url: "https://arxiv.org/abs/2501.13956", desc: "Temporal knowledge graphs enabling agents to reason over time-structured information. Informs RDF semantic memory design." },
                { title: "Grassmann Flows: Geometric Alternatives to Attention", ref: "arXiv:2512.19428", url: "https://arxiv.org/abs/2512.19428", desc: "Geometric alternatives to transformer attention mechanisms. Informs phenotype space design and KNN search." },
                { title: "Recursive LMs: Unbounded Context via Recursive Decomposition", ref: "arXiv:2512.24601", url: "https://arxiv.org/abs/2512.24601", desc: "Recursive decomposition enables unbounded context handling. Motivates context compaction and multi-tier management." },
              ].map((paper, i) => (
                <a
                  key={paper.ref}
                  href={paper.url}
                  target="_blank"
                  rel="noopener"
                  className={`reveal block bg-background p-6 transition-colors hover:bg-bg3 no-underline hover-lift hover-glow transition-shadow transition-transform duration-200 ${papersS.revealed ? "revealed" : ""}`}
                  style={{ transitionDelay: papersS.getDelay(i) }}
                >
                  <h3 className="mb-1 text-sm font-semibold text-foreground transition-colors hover:text-teal">
                    {paper.title}
                  </h3>
                  <div className="mb-2 font-mono text-xs text-teal">
                    {paper.ref}
                  </div>
                  <p className="text-xs leading-relaxed text-dim">
                    {paper.desc}
                  </p>
                </a>
              ))}
            </div>
            <div className="mt-6">
              <Btn
                href="https://github.com/Diogenesoftoronto/chrysalis-forge/blob/main/doc/THEORY.md"
                variant="ghost"
              >
                Read THEORY.md →
              </Btn>
            </div>
          </div>
        </section>
      </div>
    </div>
  );
}
