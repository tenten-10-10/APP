import { z } from "zod";
import {
  FormatSchema,
  StoryBriefSchema,
  PagePlanSchema,
  PanelSpecSchema,
} from "../schemas/index.js";

/**
 * Small request-body schemas for the REST handler layer. These wrap/relax the
 * canonical schemas where a request supplies only a subset of fields (the
 * handler fills the rest from the pipeline / store).
 */

export const CreateProjectRequestSchema = z.object({
  title: z.string().min(1),
  idea: z.string().min(1),
  format: FormatSchema.default("manga"),
  page_count: z.number().int().positive().default(35),
  target_reader: z.string().default("少年・青年"),
  tone: z.array(z.string()).default(["エモーショナル", "冒険", "ノスタルジック"]),
  protagonist_name: z.string().optional(),
});
export type CreateProjectRequest = z.infer<typeof CreateProjectRequestSchema>;

export const UpdateProjectRequestSchema = z
  .object({
    title: z.string().min(1).optional(),
    target_reader: z.string().optional(),
    tone: z.array(z.string()).optional(),
    status: z
      .enum(["draft", "generating", "ready", "archived"])
      .optional(),
    page_count: z.number().int().positive().optional(),
  })
  .strict();
export type UpdateProjectRequest = z.infer<typeof UpdateProjectRequestSchema>;

/** Optional override body for story-brief; defaults are derived from the idea. */
export const StoryBriefRequestSchema = StoryBriefSchema.partial().optional();

/** PATCH a page plan — partial update of an existing PagePlan. */
export const UpdatePageRequestSchema = PagePlanSchema.partial().strict();
export type UpdatePageRequest = z.infer<typeof UpdatePageRequestSchema>;

/** PATCH a panel — partial update of an existing PanelSpec. */
export const UpdatePanelRequestSchema = PanelSpecSchema.partial().strict();
export type UpdatePanelRequest = z.infer<typeof UpdatePanelRequestSchema>;

export const AdsRewardRequestSchema = z.object({
  /** Credits to grant for watching a rewarded ad. Defaults to 10. */
  credits: z.number().int().positive().max(100).default(10),
  project_id: z.string().optional(),
});
export type AdsRewardRequest = z.infer<typeof AdsRewardRequestSchema>;

export const GeneratePanelImageRequestSchema = z.object({
  panel_id: z.string().min(1),
});
export type GeneratePanelImageRequest = z.infer<
  typeof GeneratePanelImageRequestSchema
>;

/** A panel id is "<page_number>:<panel_number>". */
export function panelId(pageNumber: number, panelNumber: number): string {
  return `${pageNumber}:${panelNumber}`;
}
