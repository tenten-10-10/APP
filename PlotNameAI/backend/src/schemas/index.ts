import { z } from "zod";

/**
 * Canonical data model for PlotName AI.
 *
 * These schemas are the single source of truth shared (by name) with the iOS
 * client. Do not rename fields without updating the client in lockstep.
 */

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

export const FormatSchema = z.enum([
  "manga",
  "webtoon",
  "film",
  "novel",
  "trpg",
]);
export type Format = z.infer<typeof FormatSchema>;

export const SaveTheCatTypeSchema = z.enum([
  "monster_in_the_house",
  "golden_fleece",
  "out_of_the_bottle",
  "dude_with_a_problem",
  "rites_of_passage",
  "buddy_love",
  "whydunit",
  "fool_triumphant",
  "institutionalized",
  "superhero",
]);
export type SaveTheCatType = z.infer<typeof SaveTheCatTypeSchema>;

/** The 13 narrative phases (phase_number 1..13) with their canonical Japanese names. */
export const PHASE_NAMES = [
  "日常", // 1
  "事件", // 2
  "決意", // 3
  "苦境", // 4
  "助け", // 5
  "成長", // 6
  "達成", // 7
  "試練", // 8
  "破滅", // 9
  "契機", // 10
  "対決", // 11
  "排除", // 12
  "満足", // 13
] as const;

export const PhaseNameSchema = z.enum(PHASE_NAMES);
export type PhaseName = z.infer<typeof PhaseNameSchema>;

/** Map phase_number (1..13) -> canonical Japanese phase_name. */
export function phaseNameFor(phaseNumber: number): PhaseName {
  const name = PHASE_NAMES[phaseNumber - 1];
  if (!name) {
    throw new Error(`Invalid phase_number: ${phaseNumber} (expected 1..13)`);
  }
  return name;
}

export const ProjectStatusSchema = z.enum([
  "draft",
  "generating",
  "ready",
  "archived",
]);
export type ProjectStatus = z.infer<typeof ProjectStatusSchema>;

export const DensitySchema = z.enum(["low", "medium", "high"]);
export type Density = z.infer<typeof DensitySchema>;

// ---------------------------------------------------------------------------
// Project
// ---------------------------------------------------------------------------

export const ProjectSchema = z.object({
  id: z.string(),
  user_id: z.string(),
  title: z.string(),
  format: FormatSchema,
  page_count: z.number().int().positive(),
  target_reader: z.string(),
  tone: z.array(z.string()),
  status: ProjectStatusSchema,
  created_at: z.string(),
  updated_at: z.string(),
});
export type Project = z.infer<typeof ProjectSchema>;

// ---------------------------------------------------------------------------
// StoryBrief
// ---------------------------------------------------------------------------

export const ProtagonistSchema = z.object({
  name: z.string(),
  want: z.string(),
  need: z.string(),
  flaw: z.string(),
});
export type Protagonist = z.infer<typeof ProtagonistSchema>;

export const AntagonistSchema = z.object({
  name: z.string(),
  goal: z.string(),
  method: z.string(),
});
export type Antagonist = z.infer<typeof AntagonistSchema>;

export const StoryBriefSchema = z.object({
  project_id: z.string(),
  logline: z.string(),
  theme: z.string(),
  save_the_cat_type: SaveTheCatTypeSchema,
  sub_type: z.string(),
  protagonist: ProtagonistSchema,
  antagonist: AntagonistSchema.optional(),
  world: z.string().optional(),
});
export type StoryBrief = z.infer<typeof StoryBriefSchema>;

// ---------------------------------------------------------------------------
// PhaseCard
// ---------------------------------------------------------------------------

export const PhaseCardSchema = z.object({
  phase_number: z.number().int().min(1).max(13),
  phase_name: PhaseNameSchema,
  summary: z.string(),
  function: z.string(),
  emotional_value: z.number().int().min(-3).max(3),
  pages: z.array(z.number().int().positive()),
  must_show: z.array(z.string()),
});
export type PhaseCard = z.infer<typeof PhaseCardSchema>;

// ---------------------------------------------------------------------------
// PagePlan
// ---------------------------------------------------------------------------

export const PagePlanSchema = z.object({
  page_number: z.number().int().positive(),
  phase: z.number().int().min(1).max(13),
  page_goal: z.string(),
  reader_emotion: z.string(),
  turning_point: z.boolean(),
  panel_count: z.number().int().positive(),
  last_panel_hook: z.string(),
  dialogue_density: DensitySchema,
  visual_density: DensitySchema,
  why_this_page_exists: z.string(),
});
export type PagePlan = z.infer<typeof PagePlanSchema>;

// ---------------------------------------------------------------------------
// PanelSpec
// ---------------------------------------------------------------------------

export const PanelLayoutSchema = z.object({
  x: z.number().min(0).max(1),
  y: z.number().min(0).max(1),
  w: z.number().min(0).max(1),
  h: z.number().min(0).max(1),
});
export type PanelLayout = z.infer<typeof PanelLayoutSchema>;

export const PanelSpecSchema = z.object({
  page_number: z.number().int().positive(),
  panel_number: z.number().int().positive(),
  layout: PanelLayoutSchema,
  shot: z.string(),
  camera: z.string(),
  description: z.string(),
  characters: z.array(z.string()),
  dialogue: z.string(),
  sfx: z.string(),
  emotion: z.string(),
  image_prompt: z.string(),
});
export type PanelSpec = z.infer<typeof PanelSpecSchema>;

// ---------------------------------------------------------------------------
// GenerationJob
// ---------------------------------------------------------------------------

export const JobStatusSchema = z.enum([
  "queued",
  "running",
  "succeeded",
  "failed",
]);
export type JobStatus = z.infer<typeof JobStatusSchema>;

export const GenerationJobSchema = z.object({
  id: z.string(),
  user_id: z.string(),
  project_id: z.string(),
  job_type: z.string(),
  status: JobStatusSchema,
  input: z.unknown(),
  output: z.unknown(),
  cost_estimate: z.number(),
  credits_used: z.number(),
  error: z.string().nullable(),
  created_at: z.string(),
  completed_at: z.string().nullable(),
});
export type GenerationJob = z.infer<typeof GenerationJobSchema>;

// ---------------------------------------------------------------------------
// UsageLedger entry
// ---------------------------------------------------------------------------

export const UsageLedgerEntrySchema = z.object({
  id: z.string(),
  user_id: z.string(),
  project_id: z.string(),
  action: z.string(),
  model: z.string(),
  input_tokens: z.number().int().nonnegative(),
  output_tokens: z.number().int().nonnegative(),
  image_count: z.number().int().nonnegative(),
  credits_delta: z.number(),
  estimated_cost_usd: z.number(),
  created_at: z.string(),
});
export type UsageLedgerEntry = z.infer<typeof UsageLedgerEntrySchema>;

// ---------------------------------------------------------------------------
// SubscriptionEntitlement
// ---------------------------------------------------------------------------

export const PlanSchema = z.enum(["free", "plus", "pro", "studio"]);
export type Plan = z.infer<typeof PlanSchema>;

export const EntitlementFeaturesSchema = z.object({
  openai_provider: z.boolean(),
  image_generation: z.boolean(),
  export_pdf: z.boolean(),
  team_seats: z.boolean(),
  priority_queue: z.boolean(),
});
export type EntitlementFeatures = z.infer<typeof EntitlementFeaturesSchema>;

export const EntitlementLimitsSchema = z.object({
  monthly_credits: z.number().int().nonnegative(),
  max_projects: z.number().int(), // -1 == unlimited
  max_pages_per_project: z.number().int().positive(),
  max_images_per_month: z.number().int().nonnegative(),
});
export type EntitlementLimits = z.infer<typeof EntitlementLimitsSchema>;

export const SubscriptionEntitlementSchema = z.object({
  plan: PlanSchema,
  features: EntitlementFeaturesSchema,
  limits: EntitlementLimitsSchema,
});
export type SubscriptionEntitlement = z.infer<
  typeof SubscriptionEntitlementSchema
>;

// ---------------------------------------------------------------------------
// Agent / pipeline support types
// ---------------------------------------------------------------------------

export const GenreVerdictSchema = z.object({
  save_the_cat_type: SaveTheCatTypeSchema,
  sub_type: z.string(),
  confidence: z.number().min(0).max(1),
  rationale: z.string(),
});
export type GenreVerdict = z.infer<typeof GenreVerdictSchema>;

export const CritiqueSchema = z.object({
  score: z.number().min(0).max(100),
  strengths: z.array(z.string()),
  issues: z.array(z.string()),
  suggestions: z.array(z.string()),
});
export type Critique = z.infer<typeof CritiqueSchema>;

export const SafetyVerdictSchema = z.object({
  allowed: z.boolean(),
  reason: z.string(),
});
export type SafetyVerdict = z.infer<typeof SafetyVerdictSchema>;

/** Aggregate output of the FABLE pipeline. */
export const PipelineResultSchema = z.object({
  project: ProjectSchema,
  brief: StoryBriefSchema,
  phases: z.array(PhaseCardSchema),
  pagePlan: z.array(PagePlanSchema),
  panels: z.array(PanelSpecSchema),
});
export type PipelineResult = z.infer<typeof PipelineResultSchema>;
