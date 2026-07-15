import { GenreVerdictSchema, type GenreVerdict, type Format } from "../schemas/index.js";
import type { AIProvider } from "../providers/types.js";

/** genreAgent — Save the Cat genre classification. Validates provider output. */
export interface GenreInput {
  idea: string;
  format: Format;
  target_reader: string;
  tone: string[];
}

export async function runGenre(
  provider: AIProvider,
  input: GenreInput,
): Promise<GenreVerdict> {
  const verdict = await provider.classifyGenre(input);
  return GenreVerdictSchema.parse(verdict);
}

export const genreAgent = { run: runGenre };
