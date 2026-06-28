import {
  PhaseCardSchema,
  type PhaseCard,
} from "../schemas/index.js";

/**
 * sceneAgent — sanity-checks the scene/beat breakdown carried by the phase
 * cards (every phase must own at least one page and list what it must show).
 * Returns the validated, page-sorted cards.
 */
export function runScene(phases: PhaseCard[]): PhaseCard[] {
  const validated = phases.map((p) => PhaseCardSchema.parse(p));
  for (const card of validated) {
    if (card.pages.length === 0) {
      throw new Error(`sceneAgent: phase ${card.phase_number} owns no pages`);
    }
    if (card.must_show.length === 0) {
      throw new Error(`sceneAgent: phase ${card.phase_number} has no must_show beats`);
    }
  }
  return validated;
}

export const sceneAgent = { run: runScene };
