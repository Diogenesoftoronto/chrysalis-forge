import { useEffect, useRef, useState } from "react";

/**
 * Hook that toggles an "revealed" class when the element enters the viewport.
 * Use with .reveal / .reveal-left / .reveal-right utility classes.
 *
 * @param threshold — how much of element must be visible (0-1)
 * @param once — if true, only triggers once (default)
 */
export function useReveal(threshold = 0.15, once = true) {
  const ref = useRef<HTMLDivElement>(null);
  const [isRevealed, setIsRevealed] = useState(false);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;

    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            setIsRevealed(true);
            if (once) observer.unobserve(el);
          } else if (!once) {
            setIsRevealed(false);
          }
        });
      },
      { threshold },
    );

    observer.observe(el);
    return () => observer.disconnect();
  }, [threshold, once]);

  return { ref, isRevealed };
}

/**
 * Parent ref for staggered children reveals.
 * When the parent enters viewport, it sets a "revealed" attribute
 * that children read for staggered delays.
 */
export function useStaggerReveal(
  _childCount: number,
  baseDelay = 80,
  threshold = 0.1,
) {
  const ref = useRef<HTMLDivElement>(null);
  const [revealed, setRevealed] = useState(false);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const observer = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) {
          setRevealed(true);
          observer.unobserve(el);
        }
      },
      { threshold },
    );
    observer.observe(el);
    return () => observer.disconnect();
  }, [threshold]);

  return { ref, revealed, getDelay: (i: number) => `${(i * baseDelay)}ms` };
}
