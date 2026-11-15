/**
 * npm run eval -- <photo folder> [--runs 5] [--json out.json]
 *
 * Scores every photo in the folder `--runs` times (default 5) with the real
 * Gemini API and the production prompt, then prints the mean and spread per
 * photo and the cost per analysis in USD from the returned token counts.
 * This calls a paid API: it is never run by `npm test`.
 *
 * Environment (nothing is read from a file in the repo):
 *   PGYM_GEMINI_API_KEY or GEMINI_API_KEY   the key, required
 *   PGYM_GEMINI_MODEL                       model ID; defaults to PINNED_MODEL_ID in src/physiquePrompt.ts
 *   PGYM_GEMINI_PRICE_INPUT_PER_M           USD per 1M input tokens, paid tier
 *   PGYM_GEMINI_PRICE_OUTPUT_PER_M          USD per 1M output tokens, paid tier
 * Without both prices the token counts are printed and the cost reads "price not set".
 */
import { readdir, readFile, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { PINNED_MODEL_ID } from '../src/physiquePrompt';
import { formatReport, runEval, type EvalPhoto, type Prices } from '../src/physiqueEval';
import { GeminiClient, mimeTypeFor } from '../src/visionModel';

const out = (s: string) => process.stdout.write(`${s}\n`);
const fail = (s: string): never => {
  process.stderr.write(`${s}\n`);
  process.exit(2);
};

function parseArgs(argv: string[]): { folder: string; runs: number; json: string | null } {
  let folder: string | null = null;
  let runs = 5;
  let json: string | null = null;
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--runs') runs = Number(argv[++i]);
    else if (a === '--json') json = argv[++i] ?? null;
    else if (a.startsWith('--')) fail(`unknown option ${a}`);
    else folder = a;
  }
  if (!folder) fail('usage: npm run eval -- <photo folder> [--runs 5] [--json out.json]');
  if (!Number.isInteger(runs) || runs < 1 || runs > 50) fail('--runs must be a whole number from 1 to 50');
  return { folder: folder!, runs, json };
}

function readPrices(): Prices | null {
  const i = process.env.PGYM_GEMINI_PRICE_INPUT_PER_M;
  const o = process.env.PGYM_GEMINI_PRICE_OUTPUT_PER_M;
  if (!i || !o) return null;
  const prices = { inputPerMillion: Number(i), outputPerMillion: Number(o) };
  if (!Number.isFinite(prices.inputPerMillion) || !Number.isFinite(prices.outputPerMillion)) {
    fail('PGYM_GEMINI_PRICE_INPUT_PER_M and PGYM_GEMINI_PRICE_OUTPUT_PER_M must be numbers (USD per 1M tokens)');
  }
  return prices;
}

async function main(): Promise<void> {
  const { folder, runs, json } = parseArgs(process.argv.slice(2));
  const apiKey = process.env.PGYM_GEMINI_API_KEY || process.env.GEMINI_API_KEY;
  if (!apiKey) fail('set PGYM_GEMINI_API_KEY (or GEMINI_API_KEY) in the environment');
  const modelId = process.env.PGYM_GEMINI_MODEL || PINNED_MODEL_ID;
  if (!modelId) fail('no model: PINNED_MODEL_ID in src/physiquePrompt.ts is not set, so set PGYM_GEMINI_MODEL');

  const names = (await readdir(folder)).filter((n) => !n.startsWith('.') && mimeTypeFor(n)).sort();
  if (names.length === 0) fail(`no .jpg, .jpeg, .png, .webp, .heic or .heif files in ${folder}`);
  const photos: EvalPhoto[] = [];
  for (const name of names) {
    photos.push({ name, mimeType: mimeTypeFor(name)!, bytes: new Uint8Array(await readFile(join(folder, name))) });
  }

  const prices = readPrices();
  const model = new GeminiClient({ apiKey: apiKey!, modelId: modelId! });
  out(`Scoring ${photos.length} photos x ${runs} runs with ${modelId} (${photos.length * runs} paid calls).`);
  const report = await runEval({
    model,
    photos,
    runs,
    prices,
    onProgress: (photo, run) => process.stderr.write(`  ${photo} run ${run}/${runs}\r`),
  });
  process.stderr.write('\n');
  out(formatReport(report));
  if (json) {
    // Scores and token counts only; no image data.
    await writeFile(json, JSON.stringify(report, null, 2));
    out(`wrote ${json}`);
  }
}

main().catch((err) => fail(`eval failed: ${err instanceof Error ? err.message : String(err)}`));
