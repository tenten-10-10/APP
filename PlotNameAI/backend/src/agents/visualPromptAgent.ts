import {
  PanelSpecSchema,
  type PanelSpec,
  type StoryBrief,
} from "../schemas/index.js";
import type { AIProvider } from "../providers/types.js";
import { checkSafety } from "./safetyAgent.js";

/**
 * visualPromptAgent — produces an image_prompt per panel. Every generated
 * prompt is re-checked by the safety gate to guarantee no IP-infringing
 * "in the style of <real artist>" leaks into the output. Zod-validated.
 */
export async function runVisualPrompt(
  provider: AIProvider,
  brief: StoryBrief,
  panels: PanelSpec[],
): Promise<PanelSpec[]> {
  const out: PanelSpec[] = [];
  for (const panel of panels) {
    const image_prompt = await provider.generatePanelImagePrompt({ brief, panel });
    const safety = checkSafety(image_prompt);
    if (!safety.allowed) {
      throw new Error(
        `visualPromptAgent: generated prompt failed safety check: ${safety.reason}`,
      );
    }
    out.push(PanelSpecSchema.parse({ ...panel, image_prompt }));
  }
  return out;
}

export const visualPromptAgent = { run: runVisualPrompt };
