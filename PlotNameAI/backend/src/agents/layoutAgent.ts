import {
  PanelSpecSchema,
  type PanelSpec,
  type PagePlan,
  type StoryBrief,
} from "../schemas/index.js";
import type { AIProvider } from "../providers/types.js";

/**
 * layoutAgent — generates panel layout for a single page. Validates each panel
 * and checks the panel count matches the page plan.
 */
export async function runLayout(
  provider: AIProvider,
  brief: StoryBrief,
  page: PagePlan,
): Promise<PanelSpec[]> {
  const panels = await provider.generateLayout({ brief, page });
  const validated = panels.map((p) => PanelSpecSchema.parse(p));
  if (validated.length !== page.panel_count) {
    throw new Error(
      `layoutAgent: page ${page.page_number} expected ${page.panel_count} panels, got ${validated.length}`,
    );
  }
  return validated;
}

export const layoutAgent = { run: runLayout };
