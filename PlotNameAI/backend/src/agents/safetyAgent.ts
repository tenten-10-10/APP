import { SafetyVerdictSchema, type SafetyVerdict } from "../schemas/index.js";

/**
 * safetyAgent — copyright / IP safety gate.
 *
 * PlotName AI generates ORIGINAL work. We refuse requests that try to imitate
 * specific real manga, real authors, or "draw in the style of <real artist>".
 * This is a deny list of well-known titles/authors plus structural patterns
 * (e.g. "○○先生風", "…の絵柄で", "…風に描いて").
 */

// Well-known titles / franchises / authors (substring match, case-insensitive).
const DENY_TERMS: string[] = [
  // Titles (EN + JP)
  "one piece",
  "ワンピース",
  "鬼滅",
  "kimetsu",
  "demon slayer",
  "naruto",
  "ナルト",
  "ドラゴンボール",
  "dragon ball",
  "進撃の巨人",
  "attack on titan",
  "呪術廻戦",
  "jujutsu kaisen",
  "spy x family",
  "スパイファミリー",
  "チェンソーマン",
  "chainsaw man",
  "ハンターハンター",
  "hunter x hunter",
  "スラムダンク",
  "slam dunk",
  // Authors
  "尾田栄一郎",
  "鳥山明",
  "akira toriyama",
  "吾峠呼世晴",
  "岸本斉史",
];

// Structural patterns that request imitation of a real artist's style.
const DENY_PATTERNS: RegExp[] = [
  /先生風/, // "○○先生風"
  /の絵柄で/, // "…の絵柄で"
  /の作風で/,
  /風に描いて/, // "…風に描いて"
  /そっくりに/,
  /in the style of\s+\S+/i,
  /draw like\s+\S+/i,
  /同じ絵柄/,
];

export function checkSafety(text: string): SafetyVerdict {
  const lowered = text.toLowerCase();

  for (const term of DENY_TERMS) {
    if (lowered.includes(term.toLowerCase())) {
      return SafetyVerdictSchema.parse({
        allowed: false,
        reason: `特定の実在作品・作家「${term}」を模倣・参照する依頼は受け付けられません。オリジナルの設定で作成してください。`,
      });
    }
  }

  for (const pattern of DENY_PATTERNS) {
    const m = text.match(pattern);
    if (m) {
      return SafetyVerdictSchema.parse({
        allowed: false,
        reason: `実在の作家・作品の作風を模倣する表現「${m[0]}」は使用できません。オリジナルの作風を指定してください。`,
      });
    }
  }

  return SafetyVerdictSchema.parse({
    allowed: true,
    reason: "ok",
  });
}

export const safetyAgent = { check: checkSafety };
