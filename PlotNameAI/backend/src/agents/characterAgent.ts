import {
  StoryBriefSchema,
  type StoryBrief,
} from "../schemas/index.js";

/**
 * characterAgent — refines/validates the cast inside a StoryBrief (protagonist
 * want/need/flaw, antagonist). Deterministic enrichment; Zod-validated.
 */
export function runCharacter(brief: StoryBrief): StoryBrief {
  const enriched: StoryBrief = {
    ...brief,
    antagonist:
      brief.antagonist ?? {
        name: "立ちはだかる現実",
        goal: "主人公の歩みを止める",
        method: "喪失と自己不信を突きつける",
      },
  };
  return StoryBriefSchema.parse(enriched);
}

export const characterAgent = { run: runCharacter };
