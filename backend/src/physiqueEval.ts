/**
 * The stability check behind `npm run eval`: score each photo of a fixed set
 * several times with the production prompt and parser, then report the mean
 * and spread per photo and the cost per analysis. Smoothing is left out on
 * purpose: the eval measures the raw number one photo produces.
 *
 * The CLI in scripts/physique-eval.ts wires this to the real Gemini client;
 * the tests drive it with a fake model.
 */
import { parseModelReply } from './physique';
import { PHYSIQUE_PROMPT, PHYSIQUE_RESPONSE_SCHEMA, PROMPT_VERSION } from './physiquePrompt';
import type { TokenUsage, VisionModel } from './visionModel';

export interface EvalPhoto {
  name: string;
  mimeType: string;
  bytes: Uint8Array;
}

/** USD per one million tokens, paid tier. */
export interface Prices {
  inputPerMillion: number;
  outputPerMillion: number;
}

export interface RunResult {
  score: number | null;
  refusedReason: string | null;
  usage: TokenUsage | null;
  error: string | null;
}

export interface PhotoSummary {
  name: string;
  runs: RunResult[];
  scored: number;
  mean: number | null;
  /** Population standard deviation of the scored runs. */
  stdDev: number | null;
  min: number | null;
  max: number | null;
  /** max - min. */
  range: number | null;
  refusals: Record<string, number>;
  meanCostUsd: number | null;
}

export interface EvalReport {
  model: string;
  promptVersion: string;
  runsPerPhoto: number;
  photos: PhotoSummary[];
  analyses: number;
  meanInputTokens: number | null;
  meanOutputTokens: number | null;
  meanCostUsd: number | null;
  /** Largest range over all photos: the number to watch. No pass mark is decided yet. */
  worstRange: number | null;
}

export function costUsd(usage: TokenUsage, prices: Prices): number {
  return (usage.inputTokens * prices.inputPerMillion + usage.outputTokens * prices.outputPerMillion) / 1_000_000;
}

function mean(xs: number[]): number | null {
  return xs.length === 0 ? null : xs.reduce((a, b) => a + b, 0) / xs.length;
}

export function summarize(name: string, runs: RunResult[], prices: Prices | null): PhotoSummary {
  const scores = runs.map((r) => r.score).filter((s): s is number => s !== null);
  const m = mean(scores);
  const sd = m === null ? null : Math.sqrt(scores.reduce((a, s) => a + (s - m) ** 2, 0) / scores.length);
  const refusals: Record<string, number> = {};
  for (const r of runs) {
    const key = r.refusedReason ?? (r.error ? 'error' : null);
    if (key) refusals[key] = (refusals[key] ?? 0) + 1;
  }
  const costs = prices ? runs.filter((r) => r.usage).map((r) => costUsd(r.usage!, prices)) : [];
  return {
    name,
    runs,
    scored: scores.length,
    mean: m,
    stdDev: sd,
    min: scores.length ? Math.min(...scores) : null,
    max: scores.length ? Math.max(...scores) : null,
    range: scores.length ? Math.max(...scores) - Math.min(...scores) : null,
    refusals,
    meanCostUsd: mean(costs),
  };
}

export async function runOnce(model: VisionModel, photo: EvalPhoto): Promise<RunResult> {
  try {
    const res = await model.analyze({
      prompt: PHYSIQUE_PROMPT,
      responseSchema: PHYSIQUE_RESPONSE_SCHEMA,
      image: photo.bytes,
      mimeType: photo.mimeType,
    });
    const reply = parseModelReply(res.text);
    if (reply.kind === 'usable') return { score: reply.score, refusedReason: null, usage: res.usage, error: null };
    if (reply.kind === 'refused') return { score: null, refusedReason: reply.reason, usage: res.usage, error: null };
    return { score: null, refusedReason: 'failure', usage: res.usage, error: reply.problem };
  } catch (err) {
    return { score: null, refusedReason: null, usage: null, error: err instanceof Error ? err.message : String(err) };
  }
}

export async function runEval(opts: {
  model: VisionModel;
  photos: EvalPhoto[];
  runs: number;
  prices: Prices | null;
  onProgress?: (photo: string, run: number) => void;
}): Promise<EvalReport> {
  const photos: PhotoSummary[] = [];
  for (const photo of opts.photos) {
    const runs: RunResult[] = [];
    // Sequential on purpose: a burst of parallel calls can hit the rate limit and look like instability.
    for (let i = 0; i < opts.runs; i++) {
      opts.onProgress?.(photo.name, i + 1);
      runs.push(await runOnce(opts.model, photo));
    }
    photos.push(summarize(photo.name, runs, opts.prices));
  }
  const all = photos.flatMap((p) => p.runs).filter((r) => r.usage);
  const ranges = photos.map((p) => p.range).filter((r): r is number => r !== null);
  return {
    model: opts.model.modelId,
    promptVersion: PROMPT_VERSION,
    runsPerPhoto: opts.runs,
    photos,
    analyses: all.length,
    meanInputTokens: mean(all.map((r) => r.usage!.inputTokens)),
    meanOutputTokens: mean(all.map((r) => r.usage!.outputTokens)),
    meanCostUsd: opts.prices ? mean(all.map((r) => costUsd(r.usage!, opts.prices!))) : null,
    worstRange: ranges.length ? Math.max(...ranges) : null,
  };
}

const fmt = (n: number | null, digits = 1) => (n === null ? '-' : n.toFixed(digits));
const usd = (n: number | null) => (n === null ? 'price not set' : `$${n.toFixed(6)}`);

/** Plain-text report: one row per photo, then the totals. */
export function formatReport(r: EvalReport): string {
  const lines: string[] = [];
  lines.push(`PGYM physique eval: model ${r.model}, prompt ${r.promptVersion}, ${r.runsPerPhoto} runs per photo`);
  lines.push('');
  const header = ['photo', 'scored', 'mean', 'sd', 'min', 'max', 'range', 'refusals', 'cost/analysis'];
  const rows = r.photos.map((p) => [
    p.name,
    `${p.scored}/${p.runs.length}`,
    fmt(p.mean),
    fmt(p.stdDev, 2),
    fmt(p.min, 0),
    fmt(p.max, 0),
    fmt(p.range, 0),
    Object.entries(p.refusals)
      .map(([k, v]) => `${k} x${v}`)
      .join(', ') || '-',
    usd(p.meanCostUsd),
  ]);
  const widths = header.map((h, i) => Math.max(h.length, ...rows.map((row) => row[i].length)));
  const line = (cells: string[]) => cells.map((c, i) => c.padEnd(widths[i])).join('  ').trimEnd();
  lines.push(line(header));
  lines.push(line(widths.map((w) => '-'.repeat(w))));
  for (const row of rows) lines.push(line(row));
  lines.push('');
  lines.push(`analyses with token counts: ${r.analyses}`);
  lines.push(`mean tokens per analysis: input ${fmt(r.meanInputTokens, 0)}, output ${fmt(r.meanOutputTokens, 0)}`);
  lines.push(`mean cost per analysis (USD): ${usd(r.meanCostUsd)}`);
  lines.push(`worst range over photos: ${fmt(r.worstRange, 0)} points`);
  return lines.join('\n');
}
