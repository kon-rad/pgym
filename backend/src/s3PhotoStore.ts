import {
  DeleteObjectsCommand,
  GetObjectCommand,
  HeadObjectCommand,
  ListObjectsV2Command,
  PutObjectCommand,
  S3Client,
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import type { PhotoStore } from './photoStore';

export interface S3PhotoStoreConfig {
  bucket: string;
  region: string;
  /** Set for MinIO or another S3-compatible server; empty for AWS. */
  endpoint?: string;
  accessKeyId: string;
  secretAccessKey: string;
}

/** S3 allows at most 1000 keys per DeleteObjects request. */
const DELETE_BATCH = 1000;

export class S3PhotoStore implements PhotoStore {
  private readonly client: S3Client;
  private readonly bucket: string;

  constructor(config: S3PhotoStoreConfig) {
    if (!config.bucket) throw new Error('S3 bucket is not configured');
    this.bucket = config.bucket;
    this.client = new S3Client({
      region: config.region,
      endpoint: config.endpoint || undefined,
      forcePathStyle: Boolean(config.endpoint),
      credentials: { accessKeyId: config.accessKeyId, secretAccessKey: config.secretAccessKey },
    });
  }

  presignPut(key: string, contentType: string, contentLength: number, expiresInSec: number): Promise<string> {
    const command = new PutObjectCommand({
      Bucket: this.bucket,
      Key: key,
      ContentType: contentType,
      ContentLength: contentLength,
    });
    // Signing both headers means S3 rejects an upload with another type or size.
    return getSignedUrl(this.client, command, {
      expiresIn: expiresInSec,
      signableHeaders: new Set(['content-type', 'content-length']),
    });
  }

  presignGet(key: string, expiresInSec: number): Promise<string> {
    return getSignedUrl(this.client, new GetObjectCommand({ Bucket: this.bucket, Key: key }), {
      expiresIn: expiresInSec,
    });
  }

  async exists(key: string): Promise<boolean> {
    try {
      await this.client.send(new HeadObjectCommand({ Bucket: this.bucket, Key: key }));
      return true;
    } catch (err) {
      const e = err as { name?: string; $metadata?: { httpStatusCode?: number } };
      if (e.name === 'NotFound' || e.name === 'NoSuchKey' || e.$metadata?.httpStatusCode === 404) return false;
      throw err;
    }
  }

  async listKeys(prefix: string): Promise<string[]> {
    const keys: string[] = [];
    let token: string | undefined;
    do {
      const page = await this.client.send(
        new ListObjectsV2Command({ Bucket: this.bucket, Prefix: prefix, ContinuationToken: token }),
      );
      for (const obj of page.Contents ?? []) if (obj.Key) keys.push(obj.Key);
      token = page.IsTruncated ? page.NextContinuationToken : undefined;
    } while (token);
    return keys;
  }

  async getBytes(key: string, maxBytes: number): Promise<Uint8Array> {
    const res = await this.client.send(new GetObjectCommand({ Bucket: this.bucket, Key: key }));
    if (typeof res.ContentLength === 'number' && res.ContentLength > maxBytes) {
      throw new Error(`object is ${res.ContentLength} bytes, over the ${maxBytes} byte limit`);
    }
    if (!res.Body) throw new Error('object has no body');
    const bytes = await res.Body.transformToByteArray();
    if (bytes.byteLength > maxBytes) throw new Error(`object is ${bytes.byteLength} bytes, over the ${maxBytes} byte limit`);
    return bytes;
  }

  async deleteKeys(keys: string[]): Promise<void> {
    for (let i = 0; i < keys.length; i += DELETE_BATCH) {
      const batch = keys.slice(i, i + DELETE_BATCH);
      const res = await this.client.send(
        new DeleteObjectsCommand({
          Bucket: this.bucket,
          Delete: { Objects: batch.map((Key) => ({ Key })), Quiet: true },
        }),
      );
      if (res.Errors && res.Errors.length > 0) {
        const first = res.Errors[0];
        throw new Error(`S3 delete failed for ${res.Errors.length} keys, first: ${first.Code ?? 'unknown'}`);
      }
    }
  }
}
