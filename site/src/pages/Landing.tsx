import { useEffect, useRef, useState } from "react";
import { Link } from "@tanstack/react-router";
import { prepare, layout } from "@chenglou/pretext";
import { Button } from "../components/ui/button";

const HERO = "The pi agent. In your browser.";
const SUB =
  "Architect, review, and ship tasks through a terminal-first agent. Bring your own key.";

export default function Landing() {
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

  return (
    <div className="space-y-16">
      <section>
        <h1
          ref={heroRef}
          className="font-bold tracking-tight"
          style={{
            fontSize,
            lineHeight: 1.08,
            height: heroHeight ?? undefined,
          }}
        >
          {HERO}
        </h1>
        <p className="mt-5 max-w-xl text-lg text-muted-foreground">{SUB}</p>
        <div className="mt-7 flex flex-wrap gap-3">
          <Button asChild size="lg">
            <Link to="/chat">Open chat</Link>
          </Button>
          <Button asChild variant="outline" size="lg">
            <Link to="/settings">Set API key</Link>
          </Button>
        </div>
      </section>

      <section className="max-w-2xl space-y-4">
        <h2 className="text-2xl font-semibold">What is pi?</h2>
        <p className="text-muted-foreground">
          Pi is the terminal-first sibling agent in Chrysalis Forge. It ships
          three task prompts —{" "}
          <code className="text-primary">architect</code>,{" "}
          <code className="text-primary">review</code>,{" "}
          <code className="text-primary">ship</code> — and two skills that keep
          work focused on the shell.
        </p>
        <ul className="space-y-2 text-muted-foreground">
          <li>
            <strong className="text-foreground">Architect</strong> — design
            concrete, migration-aware solutions.
          </li>
          <li>
            <strong className="text-foreground">Review</strong> — surface
            severity-ordered findings.
          </li>
          <li>
            <strong className="text-foreground">Ship</strong> — implement
            minimal, verifiable changes.
          </li>
        </ul>
      </section>
    </div>
  );
}
