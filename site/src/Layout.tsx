import { useState, type ReactNode } from "react";
import { Link, useRouterState } from "@tanstack/react-router";
import { Menu, X } from "lucide-react";
import { Button } from "./components/ui/button";
import { cn } from "./lib/utils";

const LINKS = [
  { to: "/chat", label: "Chat" },
  { to: "/prompts", label: "Prompts" },
  { to: "/skills", label: "Skills" },
  { to: "/settings", label: "Settings" },
] as const;

export default function Layout({ children }: { children: ReactNode }) {
  const [open, setOpen] = useState(false);
  const { location } = useRouterState();

  return (
    <div className="flex min-h-screen flex-col">
      <header className="sticky top-0 z-20 border-b border-border bg-background/85 backdrop-blur">
        <div className="container flex h-14 items-center justify-between">
          <Link
            to="/"
            className="font-bold tracking-tight text-foreground"
            onClick={() => setOpen(false)}
          >
            chrysalis · pi
          </Link>

          <nav className="hidden gap-6 md:flex">
            {LINKS.map((l) => {
              const active = location.pathname === l.to;
              return (
                <Link
                  key={l.to}
                  to={l.to}
                  className={cn(
                    "text-sm transition-colors",
                    active
                      ? "text-foreground"
                      : "text-muted-foreground hover:text-foreground",
                  )}
                >
                  {l.label}
                </Link>
              );
            })}
          </nav>

          <Button
            variant="outline"
            size="icon"
            className="md:hidden"
            aria-label="Toggle menu"
            aria-expanded={open}
            onClick={() => setOpen((v) => !v)}
          >
            {open ? <X className="h-4 w-4" /> : <Menu className="h-4 w-4" />}
          </Button>
        </div>

        {open && (
          <nav className="container flex flex-col gap-1 border-t border-border pb-3 pt-2 md:hidden">
            {LINKS.map((l) => {
              const active = location.pathname === l.to;
              return (
                <Link
                  key={l.to}
                  to={l.to}
                  onClick={() => setOpen(false)}
                  className={cn(
                    "rounded-md px-3 py-2 text-base transition-colors",
                    active
                      ? "bg-accent text-foreground"
                      : "text-muted-foreground hover:bg-accent hover:text-foreground",
                  )}
                >
                  {l.label}
                </Link>
              );
            })}
          </nav>
        )}
      </header>

      <main className="container flex-1 py-8">{children}</main>
    </div>
  );
}
