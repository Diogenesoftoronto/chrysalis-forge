import { type VotingConfig, type VotingResult } from "./types.js";

export const STAKES_PRESETS: Record<string, VotingConfig> = {
  NONE: { nVoters: 0, kThreshold: 0, timeoutMs: 0, decorrelate: false },
  LOW: { nVoters: 3, kThreshold: 2, timeoutMs: 5000, decorrelate: false },
  MEDIUM: { nVoters: 5, kThreshold: 3, timeoutMs: 10000, decorrelate: true },
  HIGH: { nVoters: 7, kThreshold: 5, timeoutMs: 15000, decorrelate: true },
  CRITICAL: { nVoters: 9, kThreshold: 7, timeoutMs: 20000, decorrelate: true }
};

function responsesEquivalent(a: string, b: string, threshold = 0.6): boolean {
  const aWords = new Set(a.toLowerCase().split(/\s+/));
  const bWords = new Set(b.toLowerCase().split(/\s+/));
  let intersection = 0;
  for (const w of aWords) { if (bWords.has(w)) intersection++; }
  const union = new Set([...aWords, ...bWords]).size;
  return union === 0 ? a === b : intersection / union >= threshold;
}

export function tallyVotes<T extends string>(
  votes: T[],
  config: VotingConfig
): VotingResult<T> {
  const tally = new Map<T, number>();
  for (const vote of votes) {
    let counted = false;
    for (const [key, count] of tally) {
      if (responsesEquivalent(String(key), String(vote))) {
        tally.set(key, count + 1);
        counted = true;
        break;
      }
    }
    if (!counted) {
      tally.set(vote, 1);
    }
  }

  let winner: T = votes[0];
  let maxVotes = 0;
  for (const [candidate, count] of tally) {
    if (count > maxVotes) {
      maxVotes = count;
      winner = candidate;
    }
  }

  const sortedCounts = [...tally.values()].sort((a, b) => b - a);
  const margin = sortedCounts.length >= 2 ? sortedCounts[0] - sortedCounts[1] : sortedCounts[0];

  return {
    consensus: maxVotes >= config.kThreshold,
    tally,
    winner,
    margin,
    votes
  };
}

export function decorrelatePrompt(base: string, index: number, total: number): string {
  const styles = [
    "Be concise and direct.",
    "Be thorough and detailed.",
    "Focus on edge cases and potential failures.",
    "Prioritize simplicity and readability.",
    "Consider performance implications.",
    "Think about maintainability and long-term impact.",
    "Challenge assumptions in the task.",
    "Approach from a testing perspective.",
    "Consider security implications.",
    "Focus on user experience."
  ];
  const styleHint = styles[index % styles.length];
  return `${base}\n\nApproach style: ${styleHint} (voter ${index + 1} of ${total})`;
}

export function selectStakes(taskDescription: string): keyof typeof STAKES_PRESETS {
  const lower = taskDescription.toLowerCase();
  if (/\bcritical|production|deploy|release|security|auth|payment|billing\b/.test(lower)) return "CRITICAL";
  if (/\breview|audit|judge|important|core\b/.test(lower)) return "HIGH";
  if (/\brefactor|migrate|port|rewrite\b/.test(lower)) return "MEDIUM";
  if (/\btest|check|verify|validate\b/.test(lower)) return "LOW";
  return "NONE";
}

export async function executeWithVoting<T extends string>(
  task: string,
  executeVote: (prompt: string, index: number) => Promise<T>,
  config?: VotingConfig
): Promise<VotingResult<T>> {
  const stakes = selectStakes(task);
  const votingConfig = config ?? STAKES_PRESETS[stakes];

  if (votingConfig.nVoters === 0) {
    const result = await executeVote(task, 0);
    return {
      consensus: true,
      tally: new Map([[result, 1]]),
      winner: result,
      margin: 1,
      votes: [result]
    };
  }

  const votes: T[] = [];
  const prompts = votingConfig.decorrelate
    ? Array.from({ length: votingConfig.nVoters }, (_, i) => decorrelatePrompt(task, i, votingConfig.nVoters))
    : Array.from({ length: votingConfig.nVoters }, () => task);

  const results = await Promise.allSettled(
    prompts.map((prompt, i) =>
      Promise.race([
        executeVote(prompt, i),
        new Promise<never>((_, reject) =>
          setTimeout(() => reject(new Error("Vote timeout")), votingConfig.timeoutMs)
        )
      ])
    )
  );

  for (const result of results) {
    if (result.status === "fulfilled") {
      votes.push(result.value);
    }
  }

  if (votes.length === 0) {
    throw new Error("All voters failed or timed out");
  }

  return tallyVotes(votes, votingConfig);
}
