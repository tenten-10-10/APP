import {
  PanelSpecSchema,
  type PanelSpec,
  type PagePlan,
  type StoryBrief,
} from "../schemas/index.js";
import type { AIProvider } from "../providers/types.js";

/**
 * dialogueAgent — fills dialogue + sfx into a page's panels. Validates output
 * and ensures the panel set is preserved.
 */
export async function runDialogue(
  provider: AIProvider,
  brief: StoryBrief,
  page: PagePlan,
  panels: PanelSpec[],
): Promise<PanelSpec[]> {
  const out = await provider.generateDialogue({ brief, page, panels });
  const validated = out.map((p) => PanelSpecSchema.parse(p));
  if (validated.length !== panels.length) {
    throw new Error(
      `dialogueAgent: panel count changed on page ${page.page_number}`,
    );
  }
  return validated;
}

export const dialogueAgent = { run: runDialogue };
