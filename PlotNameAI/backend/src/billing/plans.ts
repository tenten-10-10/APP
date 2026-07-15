import {
  SubscriptionEntitlementSchema,
  type SubscriptionEntitlement,
  type Plan,
} from "../schemas/index.js";

/**
 * Subscription plans: features, monthly limits, and the credit-cost table for
 * each billable action. Credits are the internal currency; estimated_cost_usd
 * is tracked separately in the usage ledger.
 */

export const PLANS: Record<Plan, SubscriptionEntitlement> = {
  free: SubscriptionEntitlementSchema.parse({
    plan: "free",
    features: {
      openai_provider: false,
      image_generation: false,
      export_pdf: false,
      team_seats: false,
      priority_queue: false,
    },
    limits: {
      monthly_credits: 100,
      max_projects: 1,
      max_pages_per_project: 16,
      max_images_per_month: 0,
    },
  }),
  plus: SubscriptionEntitlementSchema.parse({
    plan: "plus",
    features: {
      openai_provider: true,
      image_generation: true,
      export_pdf: true,
      team_seats: false,
      priority_queue: false,
    },
    limits: {
      monthly_credits: 1500,
      max_projects: 10,
      max_pages_per_project: 45,
      max_images_per_month: 100,
    },
  }),
  pro: SubscriptionEntitlementSchema.parse({
    plan: "pro",
    features: {
      openai_provider: true,
      image_generation: true,
      export_pdf: true,
      team_seats: false,
      priority_queue: true,
    },
    limits: {
      monthly_credits: 6000,
      max_projects: 100,
      max_pages_per_project: 200,
      max_images_per_month: 600,
    },
  }),
  studio: SubscriptionEntitlementSchema.parse({
    plan: "studio",
    features: {
      openai_provider: true,
      image_generation: true,
      export_pdf: true,
      team_seats: true,
      priority_queue: true,
    },
    limits: {
      monthly_credits: 30000,
      max_projects: -1, // unlimited
      max_pages_per_project: 600,
      max_images_per_month: 5000,
    },
  }),
};

/** Credit cost per billable action. */
export type BillableAction =
  | "classify_genre"
  | "generate_phases"
  | "generate_page_plan"
  | "generate_layout" // per page
  | "generate_dialogue" // per page
  | "generate_image_prompt" // per panel
  | "critique"
  | "generate_image"; // per image (image_generation feature)

export const CREDIT_COSTS: Record<BillableAction, number> = {
  classify_genre: 1,
  generate_phases: 5,
  generate_page_plan: 8,
  generate_layout: 1,
  generate_dialogue: 1,
  generate_image_prompt: 1,
  critique: 3,
  generate_image: 20,
};

/** Rough USD cost estimate per 1K tokens (input/output) and per image. */
export const COST_TABLE = {
  usd_per_1k_input_tokens: 0.005,
  usd_per_1k_output_tokens: 0.015,
  usd_per_image: 0.04,
};
