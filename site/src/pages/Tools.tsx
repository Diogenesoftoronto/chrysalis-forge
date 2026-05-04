import { useStyletron } from "baseui";
import { Card } from "baseui/card";
import { HeadingLarge, HeadingMedium, ParagraphSmall } from "baseui/typography";
import { InlineCode } from "../components/MarkdownBody";

interface ToolGroup {
  category: string;
  description: string;
  tools: Array<{ name: string; desc: string }>;
}

const TOOL_GROUPS: ToolGroup[] = [
  {
    category: "Evolution",
    description: "Self-improving prompts, strategies, and harness configuration",
    tools: [
      { name: "evolve_system", desc: "Evolve the system prompt from feedback" },
      { name: "evolve_meta", desc: "Evolve the optimizer meta-prompt" },
      { name: "evolve_harness", desc: "Mutate the harness strategy" },
      { name: "log_feedback", desc: "Record evaluation feedback" },
      { name: "suggest_profile", desc: "Suggest a profile from task context" },
      { name: "profile_stats", desc: "Show profile learning statistics" },
      { name: "archive_list", desc: "List archived evolution variants" },
      { name: "evolution_stats", desc: "Show evolution state summary" },
    ],
  },
  {
    category: "Tool Evolution",
    description: "Runtime tool mutation, variant management, and self-referential improvement",
    tools: [
      { name: "evolve_tool", desc: "Evolve a tool's definition from feedback" },
      { name: "list_tools", desc: "List registered tools with status" },
      { name: "tool_variants", desc: "List evolution variants for a tool" },
      { name: "select_tool_variant", desc: "Select a variant as the active version" },
      { name: "enable_tool", desc: "Enable a previously disabled tool" },
      { name: "disable_tool", desc: "Disable a tool at runtime" },
      { name: "tool_stats", desc: "Registry statistics" },
      { name: "tool_evolution_stats", desc: "Detailed evolution statistics" },
    ],
  },
  {
    category: "Judge & Evaluation",
    description: "LLM-as-judge quality scoring with heuristic fallback",
    tools: [
      { name: "use_llm_judge", desc: "Evaluate code/text across configurable criteria" },
      { name: "judge_quality", desc: "Judge code quality (correctness, maintainability)" },
    ],
  },
  {
    category: "Test Generation",
    description: "LLM-backed test generation with framework auto-detection",
    tools: [
      { name: "generate_tests", desc: "Generate unit tests for a source file" },
      { name: "generate_test_cases", desc: "Generate concrete inputs/outputs for a function" },
    ],
  },
  {
    category: "Priority & Profiles",
    description: "Natural language priority selection and profile management",
    tools: [
      { name: "set_priority", desc: "Set the active execution profile" },
      { name: "get_priority", desc: "Get the currently active profile" },
      { name: "suggest_priority", desc: "Suggest a profile from task description" },
    ],
  },
  {
    category: "Decomposition",
    description: "Task decomposition, classification, and voting",
    tools: [
      { name: "decompose_task", desc: "Decompose a task into subtasks" },
      { name: "classify_task", desc: "Classify task type from description" },
      { name: "decomp_vote", desc: "Vote on decomposition patterns" },
    ],
  },
  {
    category: "Git",
    description: "Version control operations",
    tools: [
      { name: "git_status", desc: "Working tree status" },
      { name: "git_diff", desc: "Show changes" },
      { name: "git_log", desc: "Commit history" },
      { name: "git_commit", desc: "Record changes" },
      { name: "git_checkout", desc: "Switch branches" },
      { name: "git_add", desc: "Stage changes" },
      { name: "git_branch", desc: "List, create, or delete branches" },
    ],
  },
  {
    category: "Jujutsu",
    description: "Jujutsu version control operations",
    tools: [
      { name: "jj_status", desc: "Working copy status" },
      { name: "jj_log", desc: "Revision history" },
      { name: "jj_diff", desc: "Show changes" },
      { name: "jj_undo", desc: "Undo the last operation" },
      { name: "jj_op_log", desc: "Operation log" },
      { name: "jj_op_restore", desc: "Restore to a previous operation" },
      { name: "jj_workspace_add", desc: "Add a workspace" },
      { name: "jj_workspace_list", desc: "List workspaces" },
      { name: "jj_describe", desc: "Describe a revision" },
      { name: "jj_new", desc: "Create a new change" },
    ],
  },
  {
    category: "Web",
    description: "Web search and fetch",
    tools: [
      { name: "web_fetch", desc: "Fetch a URL" },
      { name: "web_search", desc: "Search the web" },
    ],
  },
  {
    category: "Sub-Agents",
    description: "Spawn and manage concurrent sub-agent tasks",
    tools: [
      { name: "spawn_task", desc: "Spawn a sub-agent task" },
      { name: "await_task", desc: "Wait for a sub-agent to complete" },
      { name: "task_status", desc: "Check sub-agent status" },
    ],
  },
  {
    category: "Dynamic Stores",
    description: "Runtime key-value, log, set, and counter stores",
    tools: [
      { name: "store_create", desc: "Create a new store" },
      { name: "store_list", desc: "List stores" },
      { name: "store_get", desc: "Read a value" },
      { name: "store_set", desc: "Write a value" },
      { name: "store_rm", desc: "Remove a field" },
      { name: "store_dump", desc: "Dump store contents" },
      { name: "store_delete", desc: "Delete a store" },
    ],
  },
  {
    category: "RDF Knowledge Graph",
    description: "Load, query, and insert RDF triples",
    tools: [
      { name: "rdf_load", desc: "Load N-triples into a named graph" },
      { name: "rdf_query", desc: "Query the RDF store" },
      { name: "rdf_insert", desc: "Insert a triple" },
    ],
  },
  {
    category: "Cache",
    description: "HTTP response caching with tag-based invalidation",
    tools: [
      { name: "cache_get", desc: "Get cached response" },
      { name: "cache_set", desc: "Store a cached response" },
      { name: "cache_invalidate", desc: "Invalidate a cached entry" },
      { name: "cache_invalidate_tag", desc: "Invalidate by tag" },
      { name: "cache_stats", desc: "Cache statistics" },
      { name: "cache_cleanup", desc: "Remove expired entries" },
    ],
  },
  {
    category: "Rollback",
    description: "File-level backup and rollback",
    tools: [
      { name: "file_rollback", desc: "Roll back a file to a previous version" },
      { name: "file_rollback_list", desc: "List rollback history" },
    ],
  },
];

const totalTools = TOOL_GROUPS.reduce((n, g) => n + g.tools.length, 0);

export default function Tools() {
  const [css, theme] = useStyletron();

  const grid = css({
    display: "grid",
    gap: theme.sizing.scale600,
    [theme.mediaQuery.medium]: {
      gridTemplateColumns: "repeat(2, 1fr)",
    },
  });

  const titleRow = css({
    display: "flex",
    alignItems: "center",
    justifyContent: "space-between",
    gap: theme.sizing.scale400,
  });

  const dl = css({
    display: "flex",
    flexDirection: "column",
    gap: "6px",
    fontSize: theme.typography.font200.fontSize,
    margin: 0,
  });

  const toolRow = css({ display: "flex", gap: theme.sizing.scale300 });

  const callout = css({
    borderRadius: theme.borders.radius300,
    borderWidth: "1px",
    borderStyle: "solid",
    borderColor: theme.colors.borderOpaque,
    padding: theme.sizing.scale500,
    display: "flex",
    flexDirection: "column",
    gap: theme.sizing.scale300,
  });

  const video = css({
    width: "100%",
    borderRadius: theme.borders.radius300,
    borderWidth: "1px",
    borderStyle: "solid",
    borderColor: theme.colors.borderOpaque,
  });

  return (
    <div className={css({ display: "flex", flexDirection: "column", gap: theme.sizing.scale800 })}>
      <header>
        <HeadingLarge marginTop={0} marginBottom={theme.sizing.scale300}>
          Built-in Tools
        </HeadingLarge>
        <ParagraphSmall marginTop={0} marginBottom={0} className={css({ color: theme.colors.contentSecondary })}>
          {totalTools} LLM-callable tools across {TOOL_GROUPS.length} categories. Every tool can be evolved at runtime
          through the tool evolution system.
        </ParagraphSmall>
      </header>

      <div className={grid}>
        {TOOL_GROUPS.map((group) => (
          <Card
            key={group.category}
            overrides={{}}
            title={
              <div className={titleRow}>
                <span>{group.category}</span>
                <span className={css({ fontSize: theme.typography.font100.fontSize, fontWeight: 400, color: theme.colors.contentSecondary })}>
                  {group.tools.length} tool{group.tools.length !== 1 ? "s" : ""}
                </span>
              </div>
            }
          >
            <ParagraphSmall marginTop={0} marginBottom={theme.sizing.scale400} className={css({ color: theme.colors.contentSecondary })}>
              {group.description}
            </ParagraphSmall>
            <dl className={dl}>
              {group.tools.map((t) => (
                <div key={t.name} className={toolRow}>
                  <dt style={{ margin: 0 }}>
                    <InlineCode>{t.name}</InlineCode>
                  </dt>
                  <dd className={css({ margin: 0, color: theme.colors.contentSecondary })}>{t.desc}</dd>
                </div>
              ))}
            </dl>
          </Card>
        ))}
      </div>

      <section className={css({ maxWidth: "42rem", display: "flex", flexDirection: "column", gap: theme.sizing.scale400 })}>
        <HeadingMedium marginTop={0} marginBottom={0}>
          Evolvable Tool System
        </HeadingMedium>
        <video muted loop autoPlay playsInline className={video}>
          <source src="/demos/tool-evolution.mp4" type="video/mp4" />
        </video>
        <ParagraphSmall marginTop={0} marginBottom={0} className={css({ color: theme.colors.contentSecondary })}>
          Tools are not static definitions. Through the <InlineCode>evolve_tool</InlineCode> command (or the{" "}
          <InlineCode>/evolve-tool</InlineCode> slash command), the agent can mutate any tool&apos;s description or
          parameters. Mutations are gated by novelty scoring — only variants that differ significantly from existing ones
          are activated. Variants are persisted to{" "}
          <InlineCode>.chrysalis/state/tool-evolution.json</InlineCode> and can be selected, archived, or further evolved
          at runtime without restart.
        </ParagraphSmall>
        <div className={css({ display: "flex", flexDirection: "column", gap: theme.sizing.scale400 })}>
          <div className={callout}>
            <InlineCode>evolve_tool</InlineCode>
            <ParagraphSmall marginTop={0} marginBottom={0} className={css({ color: theme.colors.contentSecondary })}>
              Given a tool name and feedback, mutates the tool description and/or parameters via LLM (heuristic fallback
              when no provider). Gates by novelty threshold (default 0.25).
            </ParagraphSmall>
          </div>
          <div className={callout}>
            <InlineCode>select_tool_variant</InlineCode>
            <ParagraphSmall marginTop={0} marginBottom={0} className={css({ color: theme.colors.contentSecondary })}>
              Switches the active variant for a tool. Only one variant is active at a time. The highest-scoring active
              variant is used when the agent calls the tool.
            </ParagraphSmall>
          </div>
          <div className={callout}>
            <InlineCode>enable_tool / disable_tool</InlineCode>
            <ParagraphSmall marginTop={0} marginBottom={0} className={css({ color: theme.colors.contentSecondary })}>
              Toggle tool availability at runtime. Disabled tools cannot be called by the agent. Events are emitted so the
              UI can reflect the change.
            </ParagraphSmall>
          </div>
        </div>
      </section>
    </div>
  );
}
