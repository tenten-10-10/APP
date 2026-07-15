import {
  UsageLedgerEntrySchema,
  type UsageLedgerEntry,
} from "../schemas/index.js";
import { COST_TABLE } from "../billing/plans.js";

/**
 * In-memory usage ledger. Records billable actions, computes credit balance,
 * and estimates USD cost. Deterministic IDs (monotonic counter); created_at is
 * passed in so the ledger itself has no hidden time-based nondeterminism.
 */

export interface RecordInput {
  user_id: string;
  project_id: string;
  action: string;
  model: string;
  input_tokens?: number;
  output_tokens?: number;
  image_count?: number;
  credits_delta: number; // negative = spend, positive = grant
  created_at?: string;
}

export function estimateCost(input: {
  input_tokens?: number;
  output_tokens?: number;
  image_count?: number;
}): number {
  const it = input.input_tokens ?? 0;
  const ot = input.output_tokens ?? 0;
  const img = input.image_count ?? 0;
  const usd =
    (it / 1000) * COST_TABLE.usd_per_1k_input_tokens +
    (ot / 1000) * COST_TABLE.usd_per_1k_output_tokens +
    img * COST_TABLE.usd_per_image;
  return Number(usd.toFixed(6));
}

export class UsageLedger {
  private entries: UsageLedgerEntry[] = [];
  private counter = 0;

  record(input: RecordInput): UsageLedgerEntry {
    this.counter += 1;
    const estimated_cost_usd = estimateCost(input);
    const entry = UsageLedgerEntrySchema.parse({
      id: `ul_${this.counter.toString().padStart(6, "0")}`,
      user_id: input.user_id,
      project_id: input.project_id,
      action: input.action,
      model: input.model,
      input_tokens: input.input_tokens ?? 0,
      output_tokens: input.output_tokens ?? 0,
      image_count: input.image_count ?? 0,
      credits_delta: input.credits_delta,
      estimated_cost_usd,
      created_at: input.created_at ?? "1970-01-01T00:00:00.000Z",
    });
    this.entries.push(entry);
    return entry;
  }

  /** Net credit balance = sum of credits_delta (grants minus spends). */
  creditsBalance(): number {
    return this.entries.reduce((sum, e) => sum + e.credits_delta, 0);
  }

  /** Total credits spent (sum of negative deltas, as a positive number). */
  creditsSpent(): number {
    return this.entries.reduce(
      (sum, e) => sum + (e.credits_delta < 0 ? -e.credits_delta : 0),
      0,
    );
  }

  totalEstimatedCostUsd(): number {
    return Number(
      this.entries.reduce((s, e) => s + e.estimated_cost_usd, 0).toFixed(6),
    );
  }

  all(): readonly UsageLedgerEntry[] {
    return this.entries;
  }
}
