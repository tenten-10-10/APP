import { runPipeline } from "./pipeline.js";
import { createProvider } from "./providers/index.js";
import { phaseNameFor } from "./schemas/index.js";

/**
 * Demo entry point. Runs the full FABLE pipeline on a sample idea using the
 * provider selected by AI_PROVIDER (default "mock") and prints a readable
 * summary: genre verdict, 13 phases, all page goals, panel count, and a
 * usage/credit summary.
 */

const SAMPLE_IDEA =
  "田舎の高校生が、死んだ祖父のノートを頼りに幻の星を探す話";

const line = (n = 64) => "─".repeat(n);

async function main() {
  const provider = createProvider();
  const out = await runPipeline(
    {
      idea: SAMPLE_IDEA,
      page_count: 35,
      format: "manga",
      target_reader: "少年・青年",
      tone: ["ノスタルジック", "冒険", "エモーショナル"],
      title: "星をさがすノート",
      protagonist_name: "ハル",
      now: "2026-01-01T00:00:00.000Z",
    },
    provider,
  );

  console.log(line());
  console.log("  PlotName AI — FABLE pipeline demo");
  console.log(`  provider: ${provider.name}`);
  console.log(line());
  console.log(`Idea     : ${SAMPLE_IDEA}`);
  console.log(`Project  : ${out.project.title} (${out.project.format}, ${out.project.page_count}p)`);
  console.log(`Logline  : ${out.brief.logline}`);
  console.log(`Theme    : ${out.brief.theme}`);
  console.log(
    `Protag.  : ${out.brief.protagonist.name} — want: ${out.brief.protagonist.want} / need: ${out.brief.protagonist.need} / flaw: ${out.brief.protagonist.flaw}`,
  );

  console.log("\n" + line());
  console.log("  GENRE VERDICT (Save the Cat)");
  console.log(line());
  console.log(`Type      : ${out.genre.save_the_cat_type}`);
  console.log(`Sub-type  : ${out.genre.sub_type}`);
  console.log(`Confidence: ${out.genre.confidence}`);
  console.log(`Rationale : ${out.genre.rationale}`);

  console.log("\n" + line());
  console.log("  13-PHASE STRUCTURE");
  console.log(line());
  for (const p of out.phases) {
    const pagesLabel =
      p.pages.length === 1
        ? `p${p.pages[0]}`
        : `p${p.pages[0]}–${p.pages[p.pages.length - 1]}`;
    const ev = p.emotional_value >= 0 ? `+${p.emotional_value}` : `${p.emotional_value}`;
    console.log(
      `  ${String(p.phase_number).padStart(2)} ${p.phase_name.padEnd(3)} [${pagesLabel.padEnd(8)}] EV ${ev.padStart(2)}  ${p.function}`,
    );
  }

  console.log("\n" + line());
  console.log("  PAGE PLAN (all pages)");
  console.log(line());
  for (const page of out.pagePlan) {
    const tp = page.turning_point ? " ★TP" : "";
    console.log(
      `  p${String(page.page_number).padStart(2)} [${phaseNameFor(page.phase)}] ${page.panel_count}コマ d:${page.dialogue_density[0]}/v:${page.visual_density[0]}${tp}  ${page.page_goal}`,
    );
  }

  console.log("\n" + line());
  console.log("  PANELS");
  console.log(line());
  const panelsPerPage = new Map<number, number>();
  for (const panel of out.panels) {
    panelsPerPage.set(
      panel.page_number,
      (panelsPerPage.get(panel.page_number) ?? 0) + 1,
    );
  }
  console.log(`  Total panels: ${out.panels.length} across ${out.pagePlan.length} pages`);
  const first = out.panels[0];
  if (first) {
    console.log("  Example panel (p1):");
    console.log(`    shot=${first.shot} camera=${first.camera}`);
    console.log(`    image_prompt: ${first.image_prompt}`);
  }

  console.log("\n" + line());
  console.log("  CRITIC");
  console.log(line());
  console.log(`  score: ${out.critique.score}/100`);
  console.log(`  issues: ${out.critique.issues.length ? out.critique.issues.join("; ") : "none"}`);

  console.log("\n" + line());
  console.log("  USAGE / CREDITS");
  console.log(line());
  console.log(`  ledger entries : ${out.ledger.all().length}`);
  console.log(`  credits spent  : ${out.ledger.creditsSpent()}`);
  console.log(`  credit balance : ${out.ledger.creditsBalance()} (net delta)`);
  console.log(`  est. cost (USD): $${out.ledger.totalEstimatedCostUsd().toFixed(4)}`);
  console.log(line());
  console.log("  Done.");
}

main().catch((err) => {
  console.error("Demo failed:", err);
  process.exit(1);
});
