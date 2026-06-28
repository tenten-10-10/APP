import {
  PhaseCardSchema,
  PagePlanSchema,
  PanelSpecSchema,
  GenreVerdictSchema,
  CritiqueSchema,
  phaseNameFor,
  type PhaseCard,
  type PagePlan,
  type PanelSpec,
  type GenreVerdict,
  type Critique,
  type Density,
} from "../schemas/index.js";
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
 * Deterministic mock provider. Produces coherent, schema-valid output with no
 * randomness (no Math.random / Date.now affecting ordering). Given the same
 * input it always returns the same result. Used for offline demo + tests.
 */

// Static description of each of the 13 phases: its dramatic function, the
// default emotional value, and the rough fraction of the book it occupies.
interface PhaseTemplate {
  fn: string;
  emotional_value: number;
  must_show: string[];
}

const PHASE_TEMPLATES: PhaseTemplate[] = [
  { fn: "世界観と主人公の日常を提示する", emotional_value: 0, must_show: ["主人公の日常", "欠落の兆し"] }, // 1 日常
  { fn: "日常を壊す事件を起こす", emotional_value: -1, must_show: ["きっかけの事件", "状況の変化"] }, // 2 事件
  { fn: "主人公が目的に向けて決意する", emotional_value: 1, must_show: ["決意の瞬間", "目的の宣言"] }, // 3 決意
  { fn: "最初の壁にぶつかり苦しむ", emotional_value: -1, must_show: ["最初の障害", "主人公の弱さ"] }, // 4 苦境
  { fn: "仲間や助けが現れる", emotional_value: 1, must_show: ["助力者の登場", "新たな手段"] }, // 5 助け
  { fn: "主人公が学び成長する", emotional_value: 2, must_show: ["スキルの獲得", "関係の深化"] }, // 6 成長
  { fn: "中間の勝利を得る", emotional_value: 3, must_show: ["小さな達成", "希望の高まり"] }, // 7 達成
  { fn: "より大きな試練が訪れる", emotional_value: 0, must_show: ["敵の本気", "代償の提示"] }, // 8 試練
  { fn: "全てを失う最悪の瞬間", emotional_value: -3, must_show: ["最大の喪失", "絶望"] }, // 9 破滅
  { fn: "立ち上がる契機をつかむ", emotional_value: -1, must_show: ["内なる気づき", "needの直視"] }, // 10 契機
  { fn: "最終決戦に挑む", emotional_value: 1, must_show: ["最終対決", "全力の衝突"] }, // 11 対決
  { fn: "障害を乗り越え敵を退ける", emotional_value: 2, must_show: ["勝利の決定打", "flawの克服"] }, // 12 排除
  { fn: "新しい日常と満足を描く", emotional_value: 3, must_show: ["変化した主人公", "新たな日常"] }, // 13 満足
];

// Relative weights used to allocate pages across the 13 phases. The shape gives
// a brisk setup, a substantial middle, and a punchy climax/resolution.
const PHASE_WEIGHTS = [10, 7, 6, 8, 6, 9, 7, 9, 6, 5, 9, 5, 5];

/**
 * Allocate `pageCount` pages across 13 phases using PHASE_WEIGHTS. Deterministic:
 * uses largest-remainder apportionment so the totals always sum exactly.
 * Returns, per phase index, the inclusive [start, end] page numbers.
 */
function allocatePages(pageCount: number): Array<{ start: number; end: number }> {
  const totalWeight = PHASE_WEIGHTS.reduce((a, b) => a + b, 0);
  const raw = PHASE_WEIGHTS.map((w) => (w / totalWeight) * pageCount);
  const floors = raw.map((r) => Math.floor(r));
  let remaining = pageCount - floors.reduce((a, b) => a + b, 0);

  // Distribute leftover pages to the phases with the largest fractional parts.
  const order = raw
    .map((r, i) => ({ i, frac: r - Math.floor(r) }))
    .sort((a, b) => b.frac - a.frac || a.i - b.i);
  const counts = [...floors];
  for (let k = 0; k < order.length && remaining > 0; k++) {
    counts[order[k]!.i]! += 1;
    remaining -= 1;
  }
  // Guarantee every phase gets at least one page (steal from the largest).
  for (let i = 0; i < counts.length; i++) {
    if (counts[i]! === 0) {
      const donorIdx = counts.indexOf(Math.max(...counts));
      counts[donorIdx]! -= 1;
      counts[i]! = 1;
    }
  }

  const ranges: Array<{ start: number; end: number }> = [];
  let cursor = 1;
  for (let i = 0; i < counts.length; i++) {
    const start = cursor;
    const end = cursor + counts[i]! - 1;
    ranges.push({ start, end });
    cursor = end + 1;
  }
  return ranges;
}

function pickGenre(idea: string, tone: string[]): GenreVerdict {
  // Deterministic keyword heuristic over the canonical Save the Cat types.
  const text = (idea + " " + tone.join(" ")).toLowerCase();
  const has = (...words: string[]) => words.some((w) => text.includes(w));

  let type: GenreVerdict["save_the_cat_type"] = "golden_fleece";
  let sub = "クエスト型の旅";
  let rationale = "目的地や対象を探して旅をする構造が中心のため。";

  if (has("探", "旅", "見つけ", "幻", "クエスト", "探す")) {
    type = "golden_fleece";
    sub = "宝探し / 自分探しの旅";
    rationale = "何かを探し求めて移動する『旅』の構造が物語の背骨になっている。";
  } else if (has("殺", "犯人", "謎", "推理", "事件")) {
    type = "whydunit";
    sub = "動機探求型ミステリー";
    rationale = "出来事の『なぜ』を解き明かす探求が駆動力になっている。";
  } else if (has("学校", "高校", "成長", "青春")) {
    type = "rites_of_passage";
    sub = "成長と通過儀礼";
    rationale = "人生の節目を乗り越えて成長する物語の型に合致する。";
  }

  return GenreVerdictSchema.parse({
    save_the_cat_type: type,
    sub_type: sub,
    confidence: 0.82,
    rationale,
  });
}

function densityForPhase(phase: number): { dialogue: Density; visual: Density } {
  // Action/climax phases lean visual; setup/turning phases lean dialogue.
  if ([2, 9, 11, 12].includes(phase)) return { dialogue: "low", visual: "high" };
  if ([1, 3, 10].includes(phase)) return { dialogue: "high", visual: "low" };
  return { dialogue: "medium", visual: "medium" };
}

function panelCountForPage(pageNumber: number, phase: number, isTurning: boolean): number {
  // First page = a single bold establishing splash. Climax pages = fewer, bigger
  // panels. Quiet/dialogue pages = denser grids. All deterministic.
  if (pageNumber === 1) return 1;
  if (isTurning) return 3;
  if ([9, 11, 12].includes(phase)) return 4;
  if ([1, 3, 10, 13].includes(phase)) return 6;
  return 5;
}

export class MockProvider implements AIProvider {
  readonly name = "mock";

  async classifyGenre(input: ClassifyGenreInput): Promise<GenreVerdict> {
    return pickGenre(input.idea, input.tone);
  }

  async generatePhases(input: GeneratePhasesInput): Promise<PhaseCard[]> {
    const ranges = allocatePages(input.page_count);
    const cards: PhaseCard[] = PHASE_TEMPLATES.map((tpl, idx) => {
      const phaseNumber = idx + 1;
      const { start, end } = ranges[idx]!;
      const pages: number[] = [];
      for (let p = start; p <= end; p++) pages.push(p);
      return PhaseCardSchema.parse({
        phase_number: phaseNumber,
        phase_name: phaseNameFor(phaseNumber),
        summary: `${phaseNameFor(phaseNumber)}: ${tpl.fn}（${input.brief.protagonist.name}の物語上の役割）`,
        function: tpl.fn,
        emotional_value: tpl.emotional_value,
        pages,
        must_show: tpl.must_show,
      });
    });
    return cards;
  }

  async generatePagePlan(input: GeneratePagePlanInput): Promise<PagePlan[]> {
    // Build a page_number -> phase_number map from the phase cards.
    const pageToPhase = new Map<number, number>();
    for (const card of input.phases) {
      for (const p of card.pages) pageToPhase.set(p, card.phase_number);
    }

    // Turning points: page 1 (hook), and the structural pivots near 16 & 20
    // (scaled to the page count), plus the 破滅 (phase 9) low point.
    const pivotA = Math.max(2, Math.round((16 / 35) * input.page_count));
    const pivotB = Math.max(pivotA + 1, Math.round((20 / 35) * input.page_count));
    const turningPoints = new Set<number>([1, pivotA, pivotB]);

    const plans: PagePlan[] = [];
    for (let page = 1; page <= input.page_count; page++) {
      const phase = pageToPhase.get(page) ?? 1;
      const tpl = PHASE_TEMPLATES[phase - 1]!;
      const isTurning = turningPoints.has(page);
      const dens = densityForPhase(phase);
      const panelCount = panelCountForPage(page, phase, isTurning);

      let goal: string;
      let emotion: string;
      let hook: string;
      if (page === 1) {
        goal = `読者を掴む冒頭。${input.brief.protagonist.name}の日常と欠落を一枚で見せる`;
        emotion = "興味・引き込まれる";
        hook = "日常を破る違和感を最後のコマに置く";
      } else if (phase === 7) {
        goal = "中間の勝利を実感させ、希望のピークを作る";
        emotion = "高揚・安堵";
        hook = "勝利の裏に潜む不穏な影を匂わせる";
      } else if (phase === 9) {
        goal = "全てを失う最悪の瞬間を突きつける";
        emotion = "絶望・喪失";
        hook = "立ち上がれない主人公の背中で引く";
      } else if (phase === 13) {
        goal = "変化した主人公の新しい日常で満足を残す";
        emotion = "充足・余韻";
        hook = "テーマを象徴する最後の一コマ";
      } else {
        goal = `${phaseNameFor(phase)}フェーズを前進させる（${tpl.fn}）`;
        emotion = ["不安", "期待", "緊張", "決意", "希望"][page % 5]!;
        hook = isTurning
          ? "状況が反転する『引き』で次ページへ"
          : "次の行動への期待を残す";
      }

      plans.push(
        PagePlanSchema.parse({
          page_number: page,
          phase,
          page_goal: goal,
          reader_emotion: emotion,
          turning_point: isTurning,
          panel_count: panelCount,
          last_panel_hook: hook,
          dialogue_density: dens.dialogue,
          visual_density: dens.visual,
          why_this_page_exists: `${phaseNameFor(phase)}の機能「${tpl.fn}」を担い、物語のテンポを保つため。`,
        }),
      );
    }
    return plans;
  }

  async generateLayout(input: GenerateLayoutInput): Promise<PanelSpec[]> {
    const { page } = input;
    const n = page.panel_count;
    const shots = ["establishing", "wide", "medium", "close-up", "extreme close-up", "over-the-shoulder"];
    const cameras = ["eye-level", "low-angle", "high-angle", "dutch-angle", "bird's-eye"];

    const panels: PanelSpec[] = [];
    // Simple deterministic vertical stack of equal-height rows (relative coords).
    const rowH = 1 / n;
    for (let i = 0; i < n; i++) {
      const panelNumber = i + 1;
      const isLast = panelNumber === n;
      const shot = n === 1 ? "establishing" : shots[(page.page_number + i) % shots.length]!;
      const camera = cameras[(page.phase + i) % cameras.length]!;
      panels.push(
        PanelSpecSchema.parse({
          page_number: page.page_number,
          panel_number: panelNumber,
          layout: {
            x: 0,
            y: Number((i * rowH).toFixed(4)),
            w: 1,
            h: Number(rowH.toFixed(4)),
          },
          shot,
          camera,
          description: isLast
            ? `『引き』のコマ: ${page.last_panel_hook}`
            : `${page.page_goal} を進めるコマ${panelNumber}（${shot} / ${camera}）`,
          characters: [input.brief.protagonist.name],
          dialogue: "",
          sfx: "",
          emotion: page.reader_emotion,
          image_prompt: "",
        }),
      );
    }
    return panels;
  }

  async generateDialogue(input: GenerateDialogueInput): Promise<PanelSpec[]> {
    const { page, panels } = input;
    const proto = input.brief.protagonist.name;
    return panels.map((panel) => {
      const isLast = panel.panel_number === panels.length;
      let dialogue = "";
      let sfx = "";
      if (page.dialogue_density !== "low") {
        if (isLast) {
          dialogue = `${proto}「……行こう。${input.brief.theme}」`;
        } else if (panel.panel_number === 1) {
          dialogue = `${proto}「（${page.reader_emotion}……）」`;
        } else {
          dialogue = `${proto}「${page.page_goal.slice(0, 12)}……」`;
        }
      }
      if (page.visual_density === "high" && !isLast) {
        sfx = ["ドッ", "ザッ", "ゴゴゴ", "バッ"][panel.panel_number % 4]!;
      }
      return PanelSpecSchema.parse({ ...panel, dialogue, sfx });
    });
  }

  async generatePanelImagePrompt(
    input: GeneratePanelImagePromptInput,
  ): Promise<string> {
    const { panel, brief } = input;
    // Original, style-neutral description. No real-author / real-title references.
    const prompt = [
      "black-and-white manga panel",
      `${panel.shot} shot, ${panel.camera}`,
      panel.description,
      `characters: ${panel.characters.join(", ")}`,
      `mood: ${panel.emotion}`,
      `theme: ${brief.theme}`,
      "original character designs, screentone shading, clean inking",
    ].join("; ");
    return prompt;
  }

  async critique(input: CritiqueInput): Promise<Critique> {
    const issues: string[] = [];
    if (input.pagePlan.length < 10) issues.push("ページ数が少なく構成が窮屈。");
    const hasMidVictory = input.phases.some((p) => p.phase_number === 7);
    const hasAllIsLost = input.phases.some((p) => p.phase_number === 9);
    if (!hasMidVictory) issues.push("中間の勝利（達成）が弱い。");
    if (!hasAllIsLost) issues.push("破滅の底が浅い。");

    return CritiqueSchema.parse({
      score: issues.length === 0 ? 88 : 88 - issues.length * 6,
      strengths: [
        "13フェーズが過不足なくページに割り当てられている。",
        "感情曲線の山と谷が明確。",
        "各ページに存在理由と『引き』がある。",
      ],
      issues,
      suggestions: [
        "破滅フェーズの直前で希望を一段上げ、落差を強める。",
        "ターニングポイントのコマ割りを大ゴマで強調する。",
      ],
    });
  }
}
