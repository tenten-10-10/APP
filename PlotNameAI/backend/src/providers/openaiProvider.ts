import {
  PhaseCardSchema,
  PagePlanSchema,
  PanelSpecSchema,
  GenreVerdictSchema,
  CritiqueSchema,
  type PhaseCard,
  type PagePlan,
  type PanelSpec,
  type GenreVerdict,
  type Critique,
} from "../schemas/index.js";
import { z } from "zod";
import type {
  AIProvider,
  ClassifyGenreInput,
  GeneratePhasesInput,
  GeneratePagePlanInput,
  GenerateLayoutInput,
  GenerateDialogueInput,
  GeneratePanelImagePromptInput,
  CritiqueInput,
} from "./types.js";

/**
 * OpenAI-backed provider using the Responses API shape.
 *
 * NOTE: this is intentionally NOT required to run for the offline demo/tests.
 * The `openai` package is an OPTIONAL dependency and is loaded via dynamic
 * import only when a method is actually invoked, so installing/running the demo
 * never depends on it. Missing OPENAI_API_KEY throws a clear error.
 */
export class OpenAIProvider implements AIProvider {
  readonly name = "openai";
  private readonly model: string;

  constructor(opts?: { model?: string }) {
    this.model = opts?.model ?? process.env.OPENAI_MODEL ?? "gpt-4.1";
    if (!process.env.OPENAI_API_KEY) {
      throw new Error(
        "OpenAIProvider requires the OPENAI_API_KEY environment variable. " +
          "Set AI_PROVIDER=mock to run fully offline.",
      );
    }
  }

  /** Lazily construct the OpenAI client so `openai` stays an optional dep. */
  private async client(): Promise<any> {
    let mod: any;
    try {
      mod = await import("openai");
    } catch {
      throw new Error(
        "The 'openai' package is not installed. Run `npm install openai` to use AI_PROVIDER=openai.",
      );
    }
    const OpenAI = mod.default ?? mod.OpenAI;
    return new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
  }

  /**
   * Call the Responses API and parse a JSON object out of the output, then
   * validate it against the provided Zod schema.
   */
  private async structured<T>(
    schema: z.ZodType<T>,
    system: string,
    user: string,
  ): Promise<T> {
    const client = await this.client();
    const res = await client.responses.create({
      model: this.model,
      input: [
        { role: "system", content: system },
        { role: "user", content: user },
      ],
      text: { format: { type: "json_object" } },
    });
    const text: string =
      res.output_text ??
      res.output?.[0]?.content?.[0]?.text ??
      "";
    let json: unknown;
    try {
      json = JSON.parse(text);
    } catch {
      throw new Error(`OpenAI returned non-JSON output: ${text.slice(0, 200)}`);
    }
    return schema.parse(json);
  }

  async classifyGenre(input: ClassifyGenreInput): Promise<GenreVerdict> {
    return this.structured(
      GenreVerdictSchema,
      "You classify a story idea into a Save the Cat genre. Respond as JSON matching the schema.",
      JSON.stringify(input),
    );
  }

  async generatePhases(input: GeneratePhasesInput): Promise<PhaseCard[]> {
    const arr = await this.structured(
      z.object({ phases: z.array(PhaseCardSchema) }),
      "You generate exactly 13 PhaseCards (phase_number 1..13) for a manga. Respond as JSON {phases:[...]}.",
      JSON.stringify(input),
    );
    return arr.phases;
  }

  async generatePagePlan(input: GeneratePagePlanInput): Promise<PagePlan[]> {
    const arr = await this.structured(
      z.object({ pages: z.array(PagePlanSchema) }),
      `You generate a page-by-page plan of exactly ${input.page_count} pages. Respond as JSON {pages:[...]}.`,
      JSON.stringify(input),
    );
    return arr.pages;
  }

  async generateLayout(input: GenerateLayoutInput): Promise<PanelSpec[]> {
    const arr = await this.structured(
      z.object({ panels: z.array(PanelSpecSchema) }),
      "You generate panel layout for one manga page. Coords are 0..1 relative. Respond as JSON {panels:[...]}.",
      JSON.stringify(input),
    );
    return arr.panels;
  }

  async generateDialogue(input: GenerateDialogueInput): Promise<PanelSpec[]> {
    const arr = await this.structured(
      z.object({ panels: z.array(PanelSpecSchema) }),
      "You fill dialogue and sfx for each panel. Keep layout unchanged. Respond as JSON {panels:[...]}.",
      JSON.stringify(input),
    );
    return arr.panels;
  }

  async generatePanelImagePrompt(
    input: GeneratePanelImagePromptInput,
  ): Promise<string> {
    const out = await this.structured(
      z.object({ image_prompt: z.string() }),
      "You write an original, copyright-safe image generation prompt for one manga panel. " +
        "Never reference real authors, titles, or 'in the style of' a real artist. Respond as JSON {image_prompt:string}.",
      JSON.stringify(input),
    );
    return out.image_prompt;
  }

  async critique(input: CritiqueInput): Promise<Critique> {
    return this.structured(
      CritiqueSchema,
      "You critique a manga structure. Respond as JSON matching the schema.",
      JSON.stringify(input),
    );
  }
}
