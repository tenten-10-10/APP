import {
  PagePlanSchema,
  type PagePlan,
  type PhaseCard,
  type StoryBrief,
} from "../schemas/index.js";
import type { AIProvider } from "../providers/types.js";

/**
 * pagePlannerAgent — produces the page-by-page plan and enforces invariants:
 * exactly page_count pages, numbered 1..N, each tied to a valid phase, each
 * with >=1 panel.
 */
export async function runPagePlanner(
  provider: AIProvider,
  brief: StoryBrief,
  phases: PhaseCard[],
  page_count: number,
): Promise<PagePlan[]> {
  const plans = await provider.generatePagePlan({ brief, phases, page_count });
  const validated = plans.map((p) => PagePlanSchema.parse(p));

  if (validated.length !== page_count) {
    throw new Error(
      `pagePlannerAgent expected ${page_count} pages, got ${validated.length}`,
    );
  }
  validated.sort((a, b) => a.page_number - b.page_number);
  validated.forEach((p, i) => {
    if (p.page_number !== i + 1) {
      throw new Error(`pagePlannerAgent: page_number out of sequence at index ${i}`);
    }
    if (p.panel_count < 1) {
      throw new Error(`pagePlannerAgent: page ${p.page_number} has < 1 panel`);
    }
  });
  return validated;
}

export const pagePlannerAgent = { run: runPagePlanner };
