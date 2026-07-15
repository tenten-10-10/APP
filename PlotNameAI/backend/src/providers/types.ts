import type {
  StoryBrief,
  PhaseCard,
  PagePlan,
  PanelSpec,
  GenreVerdict,
  Critique,
  Format,
} from "../schemas/index.js";

/**
 * Inputs shared across provider calls. The provider receives already-structured
 * context and must return schema-valid, validated data.
 */

export interface ClassifyGenreInput {
  idea: string;
  format: Format;
  target_reader: string;
  tone: string[];
}

export interface GeneratePhasesInput {
  brief: StoryBrief;
  page_count: number;
}

export interface GeneratePagePlanInput {
  brief: StoryBrief;
  phases: PhaseCard[];
  page_count: number;
}

export interface GenerateLayoutInput {
  brief: StoryBrief;
  page: PagePlan;
}

export interface GenerateDialogueInput {
  brief: StoryBrief;
  page: PagePlan;
  panels: PanelSpec[];
}

export interface GeneratePanelImagePromptInput {
  brief: StoryBrief;
  panel: PanelSpec;
}

export interface CritiqueInput {
  brief: StoryBrief;
  phases: PhaseCard[];
  pagePlan: PagePlan[];
}

/**
 * The single interface every AI backend implements. Each method MUST return
 * data that has already been validated against the canonical Zod schemas.
 */
export interface AIProvider {
  readonly name: string;

  classifyGenre(input: ClassifyGenreInput): Promise<GenreVerdict>;

  generatePhases(input: GeneratePhasesInput): Promise<PhaseCard[]>;

  generatePagePlan(input: GeneratePagePlanInput): Promise<PagePlan[]>;

  /** Layout for a single page (panels without finalized dialogue/image prompt). */
  generateLayout(input: GenerateLayoutInput): Promise<PanelSpec[]>;

  /** Fill dialogue for a page's panels. */
  generateDialogue(input: GenerateDialogueInput): Promise<PanelSpec[]>;

  /** Produce an image_prompt for a single panel. */
  generatePanelImagePrompt(
    input: GeneratePanelImagePromptInput,
  ): Promise<string>;

  critique(input: CritiqueInput): Promise<Critique>;
}
