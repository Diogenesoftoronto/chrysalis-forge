import { useState } from "react";
import {
  createRootRoute,
  HeadContent,
  Link,
  Outlet,
  Scripts,
  useRouterState,
} from "@tanstack/react-router";
import { Menu, X } from "lucide-react";
import { cn } from "../lib/utils";
import appCss from "../styles.css?url";

const LINKS = [
  { to: "/chat", label: "Chat" },
  { to: "/prompts", label: "Prompts" },
  { to: "/skills", label: "Skills" },
  { to: "/settings", label: "Settings" },
] as const;

export const Route = createRootRoute({
  head: () => ({
    meta: [
      { charSet: "utf-8" },
      { name: "viewport", content: "width=device-width, initial-scale=1.0" },
      {
        title: "Chrysalis Forge — The Agent That Evolves",
      },
      {
        name: "description",
        content:
          "A self-optimizing AI agent harness. MAP-Elites evolutionary search, tiered sandboxing, parallel sub-agents. The agent that learns to be better at being an agent.",
      },
      { name: "theme-color", content: "#080810" },
      { property: "og:type", content: "website" },
      {
        property: "og:title",
        content: "Chrysalis Forge — The Agent That Evolves",
      },
      {
        property: "og:description",
        content:
          "A self-optimizing AI agent harness. MAP-Elites evolutionary search, tiered sandboxing, parallel sub-agents. Not trained. Evolved.",
      },
      { property: "og:image", content: "/og-image.svg" },
    ],
    links: [
      { rel: "preconnect", href: "https://fonts.googleapis.com" },
      {
        rel: "preconnect",
        href: "https://fonts.gstatic.com",
        crossOrigin: "anonymous",
      },
      {
        rel: "stylesheet",
        href: "https://fonts.googleapis.com/css2?family=Bebas+Neue&family=Space+Grotesk:wght@300;400;500;600;700&family=JetBrains+Mono:ital,wght@0,400;0,700;1,400&display=swap",
      },
      { rel: "icon", type: "image/svg+xml", href: "/og-image.svg" },
      { rel: "stylesheet", href: appCss },
    ],
  }),
  shellComponent: RootDocument,
  component: RootLayout,
});

function RootDocument({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <head>
        <HeadContent />
      </head>
      <body>
        {children}
        <Scripts />
      </body>
    </html>
  );
}

function RootLayout() {
  const [open, setOpen] = useState(false);
  const { location } = useRouterState();

  return (
    <div className="flex min-h-screen flex-col bg-background text-foreground">
      <header className="sticky top-0 z-20 border-b border-border bg-background/95">
        <div className="mx-auto flex h-14 max-w-[1140px] items-center justify-between px-4">
          <Link
            to="/"
            className="font-display text-2xl tracking-wide text-foreground no-underline"
            onClick={() => setOpen(false)}
          >
            <span className="text-gold">CHRYSALIS</span>{" "}
            <span className="text-teal">FORGE</span>
          </Link>

          <nav className="hidden items-center gap-1 md:flex">
            {LINKS.map((l) => {
              const active = location.pathname === l.to;
              return (
                <Link
                  key={l.to}
                  to={l.to}
                  className={cn(
                    "px-3 py-1.5 font-mono text-xs font-bold uppercase tracking-wider transition-colors no-underline",
                    active
                      ? "text-teal"
                      : "text-dim hover:text-foreground",
                  )}
                >
                  {l.label}
                </Link>
              );
            })}
          </nav>

          <button
            className="flex h-10 w-10 items-center justify-center border border-border2 bg-transparent md:hidden"
            aria-label="Toggle menu"
            aria-expanded={open}
            onClick={() => setOpen((v) => !v)}
          >
            {open ? (
              <X className="h-4 w-4" />
            ) : (
              <Menu className="h-4 w-4" />
            )}
          </button>
        </div>

        {open && (
          <nav className="flex flex-col gap-1 border-t border-border pb-3 pt-2 md:hidden">
            {LINKS.map((l) => {
              const active = location.pathname === l.to;
              return (
                <Link
                  key={l.to}
                  to={l.to}
                  onClick={() => setOpen(false)}
                  className={cn(
                    "px-4 py-2.5 font-mono text-sm font-bold uppercase tracking-wider transition-colors no-underline",
                    active
                      ? "text-teal"
                      : "text-dim hover:text-foreground",
                  )}
                >
                  {l.label}
                </Link>
              );
            })}
          </nav>
        )}
      </header>

      <main className="flex-1">
        <Outlet />
      </main>

      <footer className="border-t border-border bg-bg3">
        <div className="mx-auto grid max-w-[1140px] grid-cols-1 gap-8 px-4 py-12 md:grid-cols-[2fr_1fr_1fr]">
          <div>
            <div className="mb-3 font-display text-2xl tracking-wide">
              <span className="text-gold">CHRYSALIS</span>{" "}
              <span className="text-teal">FORGE</span>
            </div>
            <p className="max-w-xs text-sm leading-relaxed text-dim">
              A self-evolving agent harness. MAP-Elites optimization. GEPA
              prompt evolution. Tiered sandboxing. The agent that gets better at
              being an agent.
            </p>
            <p className="mt-4 font-mono text-xs text-dim">
              Built by{" "}
              <a href="https://dio.computer" className="text-purple">
                Diogenesoftoronto
              </a>{" "}
              with λ and unreasonable ambition.
            </p>
          </div>
          <div>
            <h4 className="mb-4 font-mono text-xs font-bold uppercase tracking-widest text-dim">
              Documentation
            </h4>
            <ul className="space-y-2 text-sm text-dim">
              <li>
                <a
                  href="https://github.com/Diogenesoftoronto/chrysalis-forge/blob/main/doc/USAGE.md"
                  target="_blank"
                  rel="noopener"
                  className="transition-colors hover:text-foreground"
                >
                  Usage Guide
                </a>
              </li>
              <li>
                <a
                  href="https://github.com/Diogenesoftoronto/chrysalis-forge/blob/main/doc/ARCHITECTURE.md"
                  target="_blank"
                  rel="noopener"
                  className="transition-colors hover:text-foreground"
                >
                  Architecture
                </a>
              </li>
              <li>
                <a
                  href="https://github.com/Diogenesoftoronto/chrysalis-forge/blob/main/doc/API.md"
                  target="_blank"
                  rel="noopener"
                  className="transition-colors hover:text-foreground"
                >
                  API Reference
                </a>
              </li>
              <li>
                <a
                  href="https://github.com/Diogenesoftoronto/chrysalis-forge/blob/main/doc/THEORY.md"
                  target="_blank"
                  rel="noopener"
                  className="transition-colors hover:text-foreground"
                >
                  Theory
                </a>
              </li>
            </ul>
          </div>
          <div>
            <h4 className="mb-4 font-mono text-xs font-bold uppercase tracking-widest text-dim">
              Project
            </h4>
            <ul className="space-y-2 text-sm text-dim">
              <li>
                <a
                  href="https://github.com/Diogenesoftoronto/chrysalis-forge"
                  target="_blank"
                  rel="noopener"
                  className="transition-colors hover:text-foreground"
                >
                  GitHub
                </a>
              </li>
              <li>
                <a
                  href="https://github.com/Diogenesoftoronto/chrysalis-forge/issues"
                  target="_blank"
                  rel="noopener"
                  className="transition-colors hover:text-foreground"
                >
                  Issues
                </a>
              </li>
              <li>
                <a
                  href="https://github.com/Diogenesoftoronto/chrysalis-forge/blob/main/LICENSE"
                  target="_blank"
                  rel="noopener"
                  className="transition-colors hover:text-foreground"
                >
                  License (GPL-3.0)
                </a>
              </li>
            </ul>
          </div>
        </div>
        <div className="border-t border-border">
          <div className="mx-auto flex max-w-[1140px] flex-wrap items-center justify-between gap-4 px-4 py-5">
            <p className="font-mono text-xs text-dim">
              GPL-3.0 · Chrysalis Forge ·{" "}
              <a
                href="https://nodejs.org"
                target="_blank"
                rel="noopener"
                className="text-teal"
              >
                Node.js
              </a>{" "}
              + TypeScript
            </p>
            <p className="font-mono text-sm text-border2">
              λ{" "}
              <span className="text-teal">
                mutate → stage → archive → select → repeat
              </span>
            </p>
          </div>
        </div>
      </footer>
    </div>
  );
}
