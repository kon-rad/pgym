import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    include: ['test/**/*.test.ts'],
    testTimeout: 30_000,
    hookTimeout: 30_000,
    // Emulator-backed files share one Firestore; each test uses its own user IDs.
    fileParallelism: false,
  },
});
