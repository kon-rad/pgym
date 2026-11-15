import { describe, expect, it } from 'vitest';
import { isOwnKey, cardKey, photoKey } from '../src/photoStore';
import { S3PhotoStore } from '../src/s3PhotoStore';

// Presigning is local computation: no network call is made here.
const store = new S3PhotoStore({
  bucket: 'pgym-test-bucket',
  region: 'us-east-1',
  endpoint: 'http://127.0.0.1:9000',
  accessKeyId: 'test-access-key',
  secretAccessKey: 'test-secret-key',
});

describe('S3PhotoStore presigning', () => {
  it('signs content type and length into a 5-minute PUT', async () => {
    const url = new URL(await store.presignPut(photoKey('u1', 's1'), 'image/jpeg', 123456, 300));
    expect(url.pathname).toBe('/pgym-test-bucket/users/u1/sessions/s1/photo.jpg');
    expect(url.searchParams.get('X-Amz-Expires')).toBe('300');
    const signed = url.searchParams.get('X-Amz-SignedHeaders')!.split(';');
    expect(signed).toEqual(expect.arrayContaining(['content-length', 'content-type', 'host']));
  });

  it('presigns a 1-hour GET', async () => {
    const url = new URL(await store.presignGet(cardKey('u1', 's1'), 3600));
    expect(url.pathname).toBe('/pgym-test-bucket/users/u1/sessions/s1/card.jpg');
    expect(url.searchParams.get('X-Amz-Expires')).toBe('3600');
  });
});

describe('isOwnKey', () => {
  it.each([
    ['users/u1/sessions/s1/photo.jpg', true],
    ['users/u1/sessions/s1/card.jpg', true],
    ['users/u2/sessions/s1/photo.jpg', false],
    ['users/u1/sessions/../photo.jpg', false],
    ['users/u1/sessions/s1/other.jpg', false],
    ['users/u1x/sessions/s1/photo.jpg', false],
  ])('%s -> %s', (key, expected) => {
    expect(isOwnKey('u1', key)).toBe(expected);
  });
});
