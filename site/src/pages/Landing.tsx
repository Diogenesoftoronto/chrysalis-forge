import { useEffect, useRef, useState } from "react";
import { Link } from "@tanstack/react-router";
import { prepare, layout } from "@chenglou/pretext";
import { useStyletron } from "baseui";
import { Button } from "baseui/button";
import { HeadingMedium, ParagraphMedium, ParagraphSmall } from "baseui/typography";
import { InlineCode } from "../components/MarkdownBody";

const HERO = "The evolving pi agent.";
const SUB =
  "Architect, review, and ship tasks through a self-improving, terminal-first agent. 66+ built-in tools. Bring your own key.";

const PILLARS = [
  {
    title: "Evolutionary Harness",
    body: "Prompts, strategies, and tool definitions mutate autonomously. Novelty-gated variants are archived, scored, and selected at runtime — no restart required.",
    icon: "🧬",
    video: "/demos/evo-cycle.mp4",
  },
  {
    title: "66+ LLM Tools",
    body: "Git, Jujutsu, web search, RDF graphs, decomposition planning, LLM-as-judge evaluation, test generation, priority management, dynamic stores, and more — all callable by the agent.",
    icon: "🔧",
    video: "/demos/features-overview.mp4",
  },
  {
    title: "Evolvable Tools",
    body: "Tools themselves can be rewritten, reregistered, and evolved at runtime. The agent uses its own tools to improve its own tools — a self-referential improvement loop.",
    icon: "♾️",
    video: "/demos/tool-evolution.mp4",
  },
];

const DEMOS = [
  {
    title: "Interactive Shell",
    desc: "The REPL-based agent session with full tool access",
    src: "/demos/interactive-demo.mp4",
  },
  {
    title: "Priority Selection",
    desc: "Natural language priority: 'in a hurry' maps to the fast profile",
    src: "/demos/priority-selection.mp4",
  },
  { title: "CLI Tasks", desc: "One-shot task execution from the command line", src: "/demos/cli-task.mp4" },
  { title: "LLM-as-Judge", desc: "Quality evaluation with heuristic fallback", src: "/demos/judge-eval.mp4" },
  { title: "Test Generation", desc: "LLM-backed test generation with framework auto-detection", src: "/demos/test-generation.mp4" },
  { title: "Security Levels", desc: "Permission-gated execution with security levels", src: "/demos/security-levels.mp4" },
];

export default function Landing() {
  const [css, theme] = useStyletron();
  const heroRef = useRef<HTMLHeadingElement | null>(null);
  const [fontSize, setFontSize] = useState(64);
  const [heroHeight, setHeroHeight] = useState<number | null>(null);

  useEffect(() => {
    const el = heroRef.current;
    if (!el) return;

    const recompute = () => {
      const width = el.clientWidth;
      if (!width) return;
      const isMobile = window.innerWidth < 640;
      let size = isMobile ? 48 : 96;
      const minSize = isMobile ? 28 : 40;
      while (size > minSize) {
        try {
          const prepared = prepare(HERO, `${size}px system-ui, sans-serif`);
          const { lineCount, height } = layout(prepared, width, size * 1.1);
          if (lineCount <= 2) {
            setFontSize(size);
            setHeroHeight(height);
            return;
          }
        } catch {
          break;
        }
        size -= 4;
      }
      setFontSize(minSize);
    };

    recompute();
    const ro = new ResizeObserver(recompute);
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  const stack = css({ display: "flex", flexDirection: "column", gap: theme.sizing.scale1600 });
  const sectionGap = css({ display: "flex", flexDirection: "column", gap: theme.sizing.scale800 });
  const grid3 = css({
    display: "grid",
    gap: theme.sizing.scale600,
    [theme.mediaQuery.medium]: {
      gridTemplateColumns: "repeat(3, 1fr)",
    },
  });
  const gridDemos = css({
    display: "grid",
    gap: theme.sizing.scale600,
    [theme.mediaQuery.medium]: {
      gridTemplateColumns: "repeat(2, 1fr)",
    },
    [theme.mediaQuery.large]: {
      gridTemplateColumns: "repeat(3, 1fr)",
    },
  });
  const pillar = css({
    borderRadius: theme.borders.radius300,
    borderWidth: "1px",
    borderStyle: "solid",
    borderColor: theme.colors.borderOpaque,
    padding: theme.sizing.scale600,
    display: "flex",
    flexDirection: "column",
    gap: theme.sizing.scale400,
  });
  const video = css({
    width: "100%",
    borderRadius: theme.borders.radius200,
    borderWidth: "1px",
    borderStyle: "solid",
    borderColor: theme.colors.borderOpaque,
  });
  const btnRow = css({
    marginTop: theme.sizing.scale700,
    display: "flex",
    flexWrap: "wrap",
    gap: theme.sizing.scale400,
  });
  const dlGrid = css({
    display: "grid",
    gridTemplateColumns: "auto 1fr",
    columnGap: theme.sizing.scale600,
    rowGap: theme.sizing.scale300,
    fontSize: theme.typography.font200.fontSize,
  });
  const cmdGrid = css({
    display: "grid",
    gap: "4px",
    fontSize: theme.typography.font200.fontSize,
  });
  const cmdRow = css({
    display: "grid",
    gridTemplateColumns: "8rem 1fr",
    columnGap: theme.sizing.scale300,
  });

  return (
    <div className={stack}>
      <section>
        <h1
          ref={heroRef}
          style={{
            fontSize,
            lineHeight: 1.08,
            height: heroHeight ?? undefined,
            margin: 0,
            fontWeight: 700,
            letterSpacing: "-0.02em",
            color: theme.colors.contentPrimary,
          }}
        >
          {HERO}
        </h1>
        <ParagraphMedium className={css({ marginTop: theme.sizing.scale600, maxWidth: "36rem", color: theme.colors.contentSecondary })}>
          {SUB}
        </ParagraphMedium>
        <div className={btnRow}>
          <Button $as={Link} to="/chat" size="large">
            Open chat
          </Button>
          <Button $as={Link} to="/tools" kind="secondary" size="large">
            Browse tools
          </Button>
          <Button $as={Link} to="/settings" kind="secondary" size="large">
            Set API key
          </Button>
        </div>
      </section>

      <section className={sectionGap}>
        <HeadingMedium marginTop={0} marginBottom={0}>
          What is Chrysalis Forge?
        </HeadingMedium>
        <ParagraphMedium className={css({ margin: 0, maxWidth: "42rem", color: theme.colors.contentSecondary })}>
          Chrysalis Forge is a self-evolving agent framework. The core idea: every component — prompts,
          strategies, and even tool definitions — can mutate, be evaluated, and improve over time. The
          agent doesn&apos;t just execute tasks; it evolves how it executes tasks.
        </ParagraphMedium>

        <div className={grid3}>
          {PILLARS.map((p) => (
            <div key={p.title} className={pillar}>
              <div style={{ fontSize: "1.5rem" }}>{p.icon}</div>
              <ParagraphSmall marginTop={0} marginBottom={0} className={css({ fontWeight: 600, color: theme.colors.contentPrimary })}>
                {p.title}
              </ParagraphSmall>
              <ParagraphSmall marginTop={0} marginBottom={0} className={css({ color: theme.colors.contentSecondary })}>
                {p.body}
              </ParagraphSmall>
              <video muted loop autoPlay playsInline className={video}>
                <source src={p.video} type="video/mp4" />
              </video>
            </div>
          ))}
        </div>
      </section>

      <section className={sectionGap}>
        <HeadingMedium marginTop={0} marginBottom={0}>
          Demos
        </HeadingMedium>
        <div className={gridDemos}>
          {DEMOS.map((d) => (
            <div key={d.title} className={css({ display: "flex", flexDirection: "column", gap: theme.sizing.scale300 })}>
              <video muted loop autoPlay playsInline className={video}>
                <source src={d.src} type="video/mp4" />
              </video>
              <ParagraphSmall marginTop={0} marginBottom={0} className={css({ fontWeight: 500, color: theme.colors.contentPrimary })}>
                {d.title}
              </ParagraphSmall>
              <ParagraphSmall marginTop={0} marginBottom={0} className={css({ fontSize: theme.typography.font100.fontSize, color: theme.colors.contentSecondary })}>
                {d.desc}
              </ParagraphSmall>
            </div>
          ))}
        </div>
      </section>

      <section className={css({ maxWidth: "42rem", display: "flex", flexDirection: "column", gap: theme.sizing.scale500 })}>
        <HeadingMedium marginTop={0} marginBottom={0}>
          Built-in Profiles
        </HeadingMedium>
        <ParagraphMedium className={css({ margin: 0, color: theme.colors.contentSecondary })}>
          Execution profiles control the cost/accuracy trade-off. Set them explicitly or use natural language — the
          agent figures it out.
        </ParagraphMedium>
        <dl className={dlGrid}>
          <dt>
            <InlineCode>fast</InlineCode>
          </dt>
          <dd className={css({ margin: 0, color: theme.colors.contentSecondary })}>Quick, cheap responses. Good for debugging and research.</dd>
          <dt>
            <InlineCode>cheap</InlineCode>
          </dt>
          <dd className={css({ margin: 0, color: theme.colors.contentSecondary })}>Minimize cost. Good for documentation and exploration.</dd>
          <dt>
            <InlineCode>best</InlineCode>
          </dt>
          <dd className={css({ margin: 0, color: theme.colors.contentSecondary })}>Highest quality. Good for implementation and refactoring.</dd>
          <dt>
            <InlineCode>verbose</InlineCode>
          </dt>
          <dd className={css({ margin: 0, color: theme.colors.contentSecondary })}>Detailed output. Good for review and analysis.</dd>
        </dl>
      </section>

      <section className={css({ maxWidth: "42rem", display: "flex", flexDirection: "column", gap: theme.sizing.scale500 })}>
        <HeadingMedium marginTop={0} marginBottom={0}>
          Slash Commands
        </HeadingMedium>
        <ParagraphMedium className={css({ margin: 0, color: theme.colors.contentSecondary })}>
          Human-initiated shortcuts for the things you do most.
        </ParagraphMedium>
        <div className={cmdGrid}>
          {[
            ["/plan", "Generate a task plan artifact"],
            ["/profile", "Show or set the execution profile"],
            ["/evolve", "Evolve the system prompt from feedback"],
            ["/evolve-tool", "Evolve a tool's definition from feedback"],
            ["/meta-evolve", "Evolve the optimizer meta-prompt"],
            ["/harness", "Mutate the harness strategy"],
            ["/decomp", "Decompose a task into subtasks"],
            ["/stats", "Show evolution statistics"],
            ["/archive", "Browse archived evolution variants"],
            ["/stores", "Manage dynamic key-value stores"],
          ].map(([cmd, desc]) => (
            <div key={cmd} className={cmdRow}>
              <InlineCode>{cmd}</InlineCode>
              <span className={css({ color: theme.colors.contentSecondary })}>{desc}</span>
            </div>
          ))}
        </div>
      </section>
    </div>
  );
}
