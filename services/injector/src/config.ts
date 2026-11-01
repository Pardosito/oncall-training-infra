import { z } from "zod";

// ARCHITECTURE §5.4. REDIS_URL is optional: the Nov 5 MVP runs without Redis (INF-139).
const envSchema = z.object({
  AWS_REGION: z.string().min(1).default("us-east-1"),
  FAULTS_QUEUE_URL: z.url(),
  SESSIONS_TABLE: z.string().min(1),
  MOCK_NAMESPACE: z.string().min(1).default("mock"),
  REDIS_URL: z.string().optional(),
  PORT: z.coerce.number().int().min(1).max(65535).default(8080),
  LOG_LEVEL: z.enum(["trace", "debug", "info", "warn", "error", "fatal"]).default("info"),
  WAIT_TIME_SECONDS: z.coerce.number().int().min(0).max(20).default(20),
});

export type Config = z.infer<typeof envSchema>;

export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  return envSchema.parse(env);
}
