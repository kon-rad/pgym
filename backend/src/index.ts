/**
 * Cloud Functions entry point (2nd gen). Each export is a thin wrapper over a
 * handler in handlers.ts. Configuration comes from parameters and Secret
 * Manager; nothing secret is in this repo. See README.md for local values.
 */
import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { getFunctions } from 'firebase-admin/functions';
import { logger } from 'firebase-functions/v2';
import { defineSecret, defineString } from 'firebase-functions/params';
import { onCall, onRequest, type CallableOptions } from 'firebase-functions/v2/https';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { onTaskDispatched } from 'firebase-functions/v2/tasks';
import * as agentTokens from './agentTokens';
import { handleApi } from './api';
import * as handlers from './handlers';
import * as physique from './physique';
import { PINNED_MODEL_ID } from './physiquePrompt';
import { FirestorePhysiqueRepo } from './physiqueRepo';
import type { PhotoStore } from './photoStore';
import { S3PhotoStore } from './s3PhotoStore';
import { GeminiClient } from './visionModel';

initializeApp();

const awsAccessKeyId = defineSecret('PGYM_AWS_ACCESS_KEY_ID');
const awsSecretAccessKey = defineSecret('PGYM_AWS_SECRET_ACCESS_KEY');
/** Gemini API key, paid tier. Secret Manager in production; `.secret.local` (git-ignored) for the emulator. */
const geminiApiKey = defineSecret('PGYM_GEMINI_API_KEY');
const s3Bucket = defineString('PGYM_S3_BUCKET');
const s3Region = defineString('PGYM_S3_REGION', { default: 'us-east-1' });
/** Empty for AWS; for local work point it at MinIO, for example http://127.0.0.1:9000. */
const s3Endpoint = defineString('PGYM_S3_ENDPOINT', { default: '' });

let store: PhotoStore | undefined;
function photoStore(): PhotoStore {
  store ??= new S3PhotoStore({
    bucket: s3Bucket.value(),
    region: s3Region.value(),
    endpoint: s3Endpoint.value(),
    accessKeyId: awsAccessKeyId.value(),
    secretAccessKey: awsSecretAccessKey.value(),
  });
  return store;
}

function deps(): handlers.Deps {
  return {
    db: getFirestore(),
    auth: getAuth(),
    store: photoStore(),
    now: () => new Date(),
    log: logger,
    enqueuePhysique: async (uid, sessionId) => {
      try {
        await getFunctions()
          .taskQueue('analyzePhysique')
          .enqueue({ uid, sessionId }, { id: physique.physiqueTaskId(uid, sessionId) });
      } catch (err) {
        // The same session queued twice: the first task does the work.
        if ((err as { code?: string }).code === 'functions/task-already-exists') return;
        throw err;
      }
    },
  };
}

const callable: CallableOptions = {
  secrets: [awsAccessKeyId, awsSecretAccessKey],
  // App Check (App Attest) guards production; the emulator has no attestation.
  enforceAppCheck: process.env.FUNCTIONS_EMULATOR !== 'true',
};

export const createUploadUrls = onCall(callable, (req) => handlers.createUploadUrls(deps(), req.auth?.uid, req.data));
export const getPhotoUrls = onCall(callable, (req) => handlers.getPhotoUrls(deps(), req.auth?.uid, req.data));
export const stampSession = onCall(callable, (req) => handlers.stampSession(deps(), req.auth?.uid, req.data));
export const deleteSession = onCall(callable, (req) => handlers.deleteSession(deps(), req.auth?.uid, req.data));
export const deleteAccount = onCall(callable, (req) => handlers.deleteAccount(deps(), req.auth?.uid));

export const createAgentToken = onCall(callable, (req) => agentTokens.createAgentToken(deps(), req.auth?.uid, req.data));
export const revokeAgentToken = onCall(callable, (req) => agentTokens.revokeAgentToken(deps(), req.auth?.uid, req.data));

/**
 * The agent API. Agents are not the app, so there is no App Check here: the
 * personal access token is the credential. Public invoker, read-only, JSON.
 */
export const api = onRequest({ secrets: [awsAccessKeyId, awsSecretAccessKey], invoker: 'public', cors: false }, async (req, res) => {
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

/**
 * The physique score. Queued by stampSession, one task per session (the task
 * ID dedupes). The handler re-checks consent and age, then enforces one
 * analysis per session and DAILY_LIMIT per user per local day. A storage
 * error throws so the queue retries; a model error is written as a refusal
 * and not retried.
 */
export const analyzePhysique = onTaskDispatched(
  {
    secrets: [awsAccessKeyId, awsSecretAccessKey, geminiApiKey],
    retryConfig: { maxAttempts: 3, minBackoffSeconds: 30 },
    rateLimits: { maxConcurrentDispatches: 10 },
    memory: '512MiB',
    timeoutSeconds: 120,
  },
  async (req) => {
    const model = PINNED_MODEL_ID ? new GeminiClient({ apiKey: geminiApiKey.value(), modelId: PINNED_MODEL_ID }) : null;
    await physique.analyzePhysique(
      { repo: new FirestorePhysiqueRepo(getFirestore()), store: photoStore(), model, now: () => new Date(), log: logger },
      req.data,
    );
  },
);

/** rollWeek only touches Firestore, so it gets no S3 credentials. */
const noStore: PhotoStore = {
  presignPut: () => Promise.reject(new Error('no photo store in rollWeek')),
  presignGet: () => Promise.reject(new Error('no photo store in rollWeek')),
  exists: () => Promise.reject(new Error('no photo store in rollWeek')),
  listKeys: () => Promise.reject(new Error('no photo store in rollWeek')),
  deleteKeys: () => Promise.reject(new Error('no photo store in rollWeek')),
  getBytes: () => Promise.reject(new Error('no photo store in rollWeek')),
};

export const rollWeek = onSchedule({ schedule: 'every 60 minutes', timeZone: 'Etc/UTC' }, async () => {
  await handlers.rollWeek({ db: getFirestore(), store: noStore, now: () => new Date(), log: logger });
});
