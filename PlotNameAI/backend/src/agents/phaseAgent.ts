import {
  PhaseCardSchema,
  phaseNameFor,
  type PhaseCard,
  type StoryBrief,
} from "../schemas/index.js";
import type { AIProvider } from "../providers/types.js";

/**
 * phaseAgent — builds the 13-phase structure. Validates each card AND enforces
 * the structural invariant: exactly 13 phases, numbered 1..13, with the
 * canonical Japanese phase names.
 */
export async function runPhases(
  provider: AIProvider,
  brief: StoryBrief,
  page_count: number,
): Promise<PhaseCard[]> {
  const cards = await provider.generatePhases({ brief, page_count });
  const validated = cards.map((c) => PhaseCardSchema.parse(c));

  if (validated.length !== 13) {
    throw new Error(`phaseAgent expected 13 phases, got ${validated.length}`);
  }
  validated.sort((a, b) => a.phase_number - b.phase_number);
  validated.forEach((c, i) => {
    if (c.phase_number !== i + 1) {
      throw new Error(`phaseAgent: phase_number out of sequence at index ${i}`);
    }
    if (c.phase_name !== phaseNameFor(c.phase_number)) {
      throw new Error(
        `phaseAgent: phase ${c.phase_number} has wrong name "${c.phase_name}"`,
      );
    }
  });
  return validated;
}

export const phaseAgent = { run: runPhases };
