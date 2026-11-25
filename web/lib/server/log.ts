const REDACTED_KEYS = /authorization|token|image|photo|body|output|secret|key/i;

function redact(value: unknown): unknown {
  if (!value || typeof value !== 'object') return value;
  if (Array.isArray(value)) return value.map(redact);
  return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, REDACTED_KEYS.test(key) ? '[REDACTED]' : redact(item)]));
}

function write(level: 'info' | 'warn', event: string, data: Record<string, unknown> = {}) {
  const safe = redact(data) as Record<string, unknown>;
  const line = JSON.stringify({ level, event, ...safe, at: new Date().toISOString() });
  if (level === 'warn') console.warn(line);
  else console.info(line);
}

export const log = {
  info: (event: string, data?: Record<string, unknown>) => write('info', event, data),
  warn: (event: string, data?: Record<string, unknown>) => write('warn', event, data),
};
