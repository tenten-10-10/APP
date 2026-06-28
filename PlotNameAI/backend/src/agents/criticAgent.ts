import {
  CritiqueSchema,
  type Critique,
  type PhaseCard,
  type PagePlan,
  type StoryBrief,
} from "../schemas/index.js";
import type { AIProvider } from "../providers/types.js";

/**
 * criticAgent — evaluates the overall structure and returns a validated
 * Critique (score + strengths/issues/suggestions).
 */
export async function runCritic(
  provider: AIProvider,
  brief: StoryBrief,
  phases: PhaseCard[],
  pagePlan: PagePlan[],
): Promise<Critique> {
  const critique = await provider.critique({ brief, phases, pagePlan });
  return CritiqueSchema.parse(critique);
}

export const criticAgent = { run: runCritic };
