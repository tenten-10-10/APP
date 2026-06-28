import type { AIProvider } from "./types.js";
import { MockProvider } from "./mockProvider.js";
import { OpenAIProvider } from "./openaiProvider.js";

export * from "./types.js";
export { MockProvider } from "./mockProvider.js";
export { OpenAIProvider } from "./openaiProvider.js";

/**
 * Factory: choose a provider by the AI_PROVIDER env var. Defaults to "mock"
 * so the app always runs fully offline without an API key.
 */
export function createProvider(name?: string): AIProvider {
  const choice = (name ?? process.env.AI_PROVIDER ?? "mock").toLowerCase();
  switch (choice) {
    case "openai":
      return new OpenAIProvider();
    case "mock":
      return new MockProvider();
    default:
      throw new Error(
        `Unknown AI_PROVIDER "${choice}". Expected "mock" or "openai".`,
      );
  }
}
