import {
  StoryBriefSchema,
  type StoryBrief,
  type GenreVerdict,
  type Format,
} from "../schemas/index.js";

/**
 * intakeAgent — turns a raw one-line idea (+ a genre verdict) into a validated
 * StoryBrief. In the mock path this is deterministic; in production the
 * provider would enrich the protagonist/theme. Output is Zod-validated.
 */

export interface IntakeInput {
  project_id: string;
  idea: string;
  format: Format;
  genre: GenreVerdict;
  protagonist_name?: string;
}

export function runIntake(input: IntakeInput): StoryBrief {
  const protoName = input.protagonist_name ?? "主人公";
  const brief = {
    project_id: input.project_id,
    logline: input.idea.trim(),
    theme: "失われたものを受け継ぎ、自分の道を見つける",
    save_the_cat_type: input.genre.save_the_cat_type,
    sub_type: input.genre.sub_type,
    protagonist: {
      name: protoName,
      want: "目的の対象を見つけ出すこと",
      need: "過去と向き合い、自分の足で前へ進むこと",
      flaw: "他者に頼れず、過去に縛られている",
    },
    antagonist: {
      name: "立ちはだかる現実",
      goal: "主人公の歩みを止める",
      method: "喪失・障害・自己不信を突きつける",
    },
    world: "現代日本を基調とした、ささやかな非日常が混じる世界",
  };
  return StoryBriefSchema.parse(brief);
}

export const intakeAgent = { run: runIntake };
