/**
 * Cloud Functions entry point (2nd gen). Each export is a thin wrapper over a
 * handler in handlers.ts. Configuration comes from parameters and Secret
 * Manager; nothing secret is in this repo. See README.md for local values.
 */
import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { defineSecret, defineString } from 'firebase-functions/params';
import { onCall, onRequest, type CallableOptions } from 'firebase-functions/v2/https';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import * as agentTokens from './agentTokens';
import { handleApi } from './api';
import * as handlers from './handlers';
import type { PhotoStore } from './photoStore';
import { S3PhotoStore } from './s3PhotoStore';

initializeApp();

const awsAccessKeyId = defineSecret('PGYM_AWS_ACCESS_KEY_ID');
const awsSecretAccessKey = defineSecret('PGYM_AWS_SECRET_ACCESS_KEY');
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
      // Card B2 adds analyzePhysique and its task queue.
      logger.info('analyzePhysique not wired yet', { uid, sessionId });
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

/** rollWeek only touches Firestore, so it gets no S3 credentials. */
const noStore: PhotoStore = {
  presignPut: () => Promise.reject(new Error('no photo store in rollWeek')),
  presignGet: () => Promise.reject(new Error('no photo store in rollWeek')),
  exists: () => Promise.reject(new Error('no photo store in rollWeek')),
  listKeys: () => Promise.reject(new Error('no photo store in rollWeek')),
  deleteKeys: () => Promise.reject(new Error('no photo store in rollWeek')),
};

export const rollWeek = onSchedule({ schedule: 'every 60 minutes', timeZone: 'Etc/UTC' }, async () => {
  await handlers.rollWeek({ db: getFirestore(), store: noStore, now: () => new Date(), log: logger });
});
