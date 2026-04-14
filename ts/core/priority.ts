import { type ChrysalisProfile } from "./types.js";

export function interpretProfilePhrase(input: string): { profile: ChrysalisProfile; reason: string } {
  const normalized = input.trim().toLowerCase();
  if (!normalized) {
    return { profile: "best", reason: "defaulted to best because no profile phrase was supplied" };
  }
  if (/\bfast|quick|urgent|speed|hurry\b/.test(normalized)) {
    return { profile: "fast", reason: "matched speed-oriented language" };
  }
  if (/\bcheap|budget|broke|cost|low[- ]?cost\b/.test(normalized)) {
    return { profile: "cheap", reason: "matched cost-sensitive language" };
  }
  if (/\bverbose|detailed|thorough|teach|explain\b/.test(normalized)) {
    return { profile: "verbose", reason: "matched high-explanation language" };
  }
  if (/\bbest|accurate|precision|careful|deep|quality\b/.test(normalized)) {
    return { profile: "best", reason: "matched quality-oriented language" };
  }
  return { profile: "best", reason: "used the safe default profile for an ambiguous phrase" };
}
