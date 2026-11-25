export type ErrorCode =
  | 'unauthenticated'
  | 'invalid-argument'
  | 'not-found'
  | 'failed-precondition'
  | 'permission-denied'
  | 'resource-exhausted'
  | 'unimplemented'
  | 'internal';

export class HttpsError extends Error {
  constructor(public readonly code: ErrorCode, message: string) {
    super(message);
    this.name = 'HttpsError';
  }
}
