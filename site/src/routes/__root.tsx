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
import { useStyletron } from "baseui";
import { Button } from "baseui/button";
import { AppProviders } from "../components/AppProviders";
import appCss from "../styles.css?url";

const LINKS = [
  { to: "/chat", label: "Chat" },
  { to: "/tools", label: "Tools" },
  { to: "/prompts", label: "Prompts" },
  { to: "/skills", label: "Skills" },
  { to: "/settings", label: "Settings" },
] as const;

export const Route = createRootRoute({
  head: () => ({
    meta: [
      { charSet: "utf-8" },
      { name: "viewport", content: "width=device-width, initial-scale=1.0" },
      { title: "Chrysalis Forge — Self-Evolving Pi Agent" },
      {
        name: "description",
        content:
          "The self-evolving agent framework: 66+ built-in tools, runtime tool evolution, novelty-gated mutations, and LLM-as-judge evaluation. Bring your own key.",
      },
      { name: "theme-color", content: "#080810" },
      { property: "og:type", content: "website" },
      { property: "og:title", content: "Chrysalis Forge — Self-Evolving Pi Agent" },
      {
        property: "og:description",
        content:
          "66+ built-in tools, runtime tool evolution, novelty-gated mutations, and LLM-as-judge evaluation.",
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
  return (
    <AppProviders>
      <RootLayoutInner />
    </AppProviders>
  );
}

function RootLayoutInner() {
  const [open, setOpen] = useState(false);
  const { location } = useRouterState();
  const [css, theme] = useStyletron();

  const shell = css({
    display: "flex",
    flexDirection: "column",
    minHeight: "100vh",
    backgroundColor: theme.colors.backgroundPrimary,
    color: theme.colors.contentPrimary,
  });

  const header = css({
    position: "sticky",
    top: 0,
    zIndex: 20,
    borderBottomWidth: "1px",
    borderBottomStyle: "solid",
    borderBottomColor: theme.colors.borderOpaque,
    backgroundColor: `color-mix(in srgb, ${theme.colors.backgroundPrimary} 85%, transparent)`,
    backdropFilter: "blur(8px)",
  });

  const headerInner = css({
    maxWidth: "1100px",
    marginLeft: "auto",
    marginRight: "auto",
    paddingLeft: "1rem",
    paddingRight: "1rem",
    display: "flex",
    height: "56px",
    alignItems: "center",
    justifyContent: "space-between",
  });

  const brand = css({
    fontWeight: 700,
    letterSpacing: "-0.02em",
    color: theme.colors.contentPrimary,
    textDecoration: "none",
  });

  const desktopNav = css({
    display: "none",
    gap: "1.5rem",
    [theme.mediaQuery.medium]: {
      display: "flex",
    },
  });

  const mobileToggle = css({
    [theme.mediaQuery.medium]: {
      display: "none",
    },
  });

  const mobileNav = css({
    display: "flex",
    flexDirection: "column",
    gap: "4px",
    borderTopWidth: "1px",
    borderTopStyle: "solid",
    borderTopColor: theme.colors.borderOpaque,
    paddingBottom: "12px",
    paddingTop: "8px",
    paddingLeft: "1rem",
    paddingRight: "1rem",
    maxWidth: "1100px",
    marginLeft: "auto",
    marginRight: "auto",
    [theme.mediaQuery.medium]: {
      display: "none",
    },
  });

  const main = css({
    flex: 1,
    maxWidth: "1100px",
    marginLeft: "auto",
    marginRight: "auto",
    width: "100%",
    boxSizing: "border-box",
    paddingLeft: "1rem",
    paddingRight: "1rem",
    paddingTop: "2rem",
    paddingBottom: "2rem",
  });

  const linkStyle = (active: boolean) =>
    css({
      fontSize: theme.typography.font150.fontSize,
      color: active ? theme.colors.contentPrimary : theme.colors.contentSecondary,
      textDecoration: "none",
      transition: "color 0.15s ease",
      ":hover": {
        color: theme.colors.contentPrimary,
      },
    });

  const mobileLinkStyle = (active: boolean) =>
    css({
      fontSize: "1rem",
      borderRadius: theme.borders.radius200,
      padding: "8px 12px",
      color: active ? theme.colors.contentPrimary : theme.colors.contentSecondary,
      backgroundColor: active ? theme.colors.backgroundTertiary : "transparent",
      textDecoration: "none",
      ":hover": {
        backgroundColor: theme.colors.backgroundTertiary,
        color: theme.colors.contentPrimary,
      },
    });

  return (
    <div className={shell}>
      <header className={header}>
        <div className={headerInner}>
          <Link to="/" className={brand} onClick={() => setOpen(false)}>
            chrysalis forge
          </Link>

          <nav className={desktopNav}>
            {LINKS.map((l) => {
              const active = location.pathname === l.to;
              return (
                <Link key={l.to} to={l.to} className={linkStyle(active)}>
                  {l.label}
                </Link>
              );
            })}
          </nav>

          <div className={mobileToggle}>
            <Button
              kind="secondary"
              shape="square"
              size="compact"
              aria-label="Toggle menu"
              aria-expanded={open}
              onClick={() => setOpen((v) => !v)}
            >
              {open ? <X size={16} /> : <Menu size={16} />}
            </Button>
          </div>
        </div>

        {open && (
          <nav className={mobileNav}>
            {LINKS.map((l) => {
              const active = location.pathname === l.to;
              return (
                <Link
                  key={l.to}
                  to={l.to}
                  onClick={() => setOpen(false)}
                  className={mobileLinkStyle(active)}
                >
                  {l.label}
                </Link>
              );
            })}
          </nav>
        )}
      </header>

      <main className={main}>
        <Outlet />
      </main>
    </div>
  );
}
