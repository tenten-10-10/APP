import {
  type SubscriptionEntitlement,
  type Plan,
} from "../schemas/index.js";
import { PLANS } from "./plans.js";

/** Resolve the full entitlement (features + limits) for a plan. */
export function resolveEntitlement(plan: Plan): SubscriptionEntitlement {
  return PLANS[plan];
}

export type FeatureName = keyof SubscriptionEntitlement["features"];

/** Check whether a plan has a given feature flag enabled. */
export function hasFeature(plan: Plan, feature: FeatureName): boolean {
  return resolveEntitlement(plan).features[feature];
}

export interface EnforceResult {
  ok: boolean;
  reason: string;
}

/** Enforce the per-project page limit. */
export function checkPageLimit(plan: Plan, pageCount: number): EnforceResult {
  const limit = resolveEntitlement(plan).limits.max_pages_per_project;
  if (pageCount > limit) {
    return {
      ok: false,
      reason: `Plan "${plan}" allows up to ${limit} pages per project (requested ${pageCount}).`,
    };
  }
  return { ok: true, reason: "ok" };
}

/** Enforce the monthly project-count limit (-1 == unlimited). */
export function checkProjectLimit(
  plan: Plan,
  currentProjectCount: number,
): EnforceResult {
  const limit = resolveEntitlement(plan).limits.max_projects;
  if (limit !== -1 && currentProjectCount >= limit) {
    return {
      ok: false,
      reason: `Plan "${plan}" allows up to ${limit} project(s).`,
    };
  }
  return { ok: true, reason: "ok" };
}

/** Enforce that there are enough credits remaining for a spend. */
export function checkCredits(
  plan: Plan,
  creditsUsedThisMonth: number,
  spend: number,
): EnforceResult {
  const budget = resolveEntitlement(plan).limits.monthly_credits;
  if (creditsUsedThisMonth + spend > budget) {
    return {
      ok: false,
      reason: `Insufficient credits: plan "${plan}" budget ${budget}, used ${creditsUsedThisMonth}, need ${spend}.`,
    };
  }
  return { ok: true, reason: "ok" };
}

/** Require a feature, throwing a clear error if the plan lacks it. */
export function requireFeature(plan: Plan, feature: FeatureName): void {
  if (!hasFeature(plan, feature)) {
    throw new Error(`Plan "${plan}" does not include feature "${feature}".`);
  }
}
