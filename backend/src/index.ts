/** Cloud Functions entry point. Proof media is never configured or retained server-side. */
import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { defineSecret } from 'firebase-functions/params';
import { onCall, onRequest, type CallableOptions } from 'firebase-functions/v2/https';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import * as agentTokens from './agentTokens';
import { handleApi } from './api';
import * as handlers from './handlers';
import { analyzePhotoInsight as analyzeInsight, INSIGHT_MODEL_ID } from './photoInsight';
import { GeminiClient } from './visionModel';

initializeApp();
const geminiApiKey = defineSecret('PGYM_GEMINI_API_KEY');

function deps(): handlers.Deps {
  return { db: getFirestore(), auth: getAuth(), now: () => new Date(), log: logger };
}

const callable: CallableOptions = { enforceAppCheck: process.env.FUNCTIONS_EMULATOR !== 'true' };

export const stampSession = onCall(callable, (req) => handlers.stampSession(deps(), req.auth?.uid, req.data));
export const deleteSession = onCall(callable, (req) => handlers.deleteSession(deps(), req.auth?.uid, req.data));
export const deleteAccount = onCall(callable, (req) => handlers.deleteAccount(deps(), req.auth?.uid));
export const createAgentToken = onCall(callable, (req) => agentTokens.createAgentToken(deps(), req.auth?.uid, req.data));
export const revokeAgentToken = onCall(callable, (req) => agentTokens.revokeAgentToken(deps(), req.auth?.uid, req.data));

export const analyzePhotoInsight = onCall(
  { ...callable, secrets: [geminiApiKey], memory: '512MiB', timeoutSeconds: 60 },
  async (req) => analyzeInsight(
    {
      db: getFirestore(),
      model: new GeminiClient({ apiKey: geminiApiKey.value(), modelId: INSIGHT_MODEL_ID }),
      now: () => new Date(),
      log: logger,
    },
    req.auth?.uid,
    req.data,
  ),
);

/** Agent access is read-only structured workout data. It never exposes photos or local insights. */
export const api = onRequest({ invoker: 'public', cors: false }, async (req, res) => {
  const out = await handleApi(deps(), {
    method: req.method,
    path: req.path,
    query: req.query as Record<string, unknown>,
    headers: req.headers,
  });
  res.status(out.status).set(out.headers);
  if (req.method === 'HEAD') res.end();
  else res.send(JSON.stringify(out.body));
});

export const rollWeek = onSchedule({ schedule: 'every 60 minutes', timeZone: 'Etc/UTC' }, async () => {
  await handlers.rollWeek(deps());
});
