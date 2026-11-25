import { applicationDefault, getApps, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { log } from './log';

function app() {
  return getApps()[0] ?? initializeApp({
    credential: applicationDefault(),
    projectId: process.env.FIREBASE_PROJECT_ID || 'pgym-local',
  });
}

export function services() {
  const instance = app();
  return { db: getFirestore(instance), auth: getAuth(instance), now: () => new Date(), log };
}
