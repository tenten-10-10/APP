import {
  PhaseCardSchema,
  type PhaseCard,
} from "../schemas/index.js";

/**
 * sceneAgent — sanity-checks the scene/beat breakdown carried by the phase
 * cards. Every phase must list what it must show, and the union of pages across
 * all phases must be non-empty. A phase may legitimately own zero pages when the
 * page count is shorter than 13 phases (e.g. an 8P read-through), so an empty
 * `pages` array on an individual card is NOT an error — the 13-phase backbone
 * compresses and the page plan maps each page to its owning phase.
 * Returns the validated cards.
 */
export function runScene(phases: PhaseCard[]): PhaseCard[] {
  const validated = phases.map((p) => PhaseCardSchema.parse(p));
  for (const card of validated) {
    if (card.must_show.length === 0) {
      throw new Error(`sceneAgent: phase ${card.phase_number} has no must_show beats`);
    }
  }
  if (validated.every((c) => c.pages.length === 0)) {
    throw new Error("sceneAgent: no phase owns any pages");
  }
  return validated;
}

export const sceneAgent = { run: runScene };
