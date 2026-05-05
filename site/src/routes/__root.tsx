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
import { Button } from "../components/ui/button";
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
      { title: "Chrysalis Forge — Pi Agent" },
      {
        name: "description",
        content:
          "Browser UI for the pi agent: architect, review, and ship tasks with your own API key.",
      },
      { name: "theme-color", content: "#080810" },
      { property: "og:type", content: "website" },
      { property: "og:title", content: "Chrysalis Forge — Pi Agent" },
      {
        property: "og:description",
        content: "Browser UI for the pi agent. Bring your own key.",
      },
      { property: "og:image", content: "/og-image.svg" },
    ],
    links: [
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

      <main className="container flex-1 py-8">
        <Outlet />
      </main>
    </div>
  );
}
