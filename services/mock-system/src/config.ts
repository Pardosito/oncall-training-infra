import { z } from "zod";

export const ROLES = ["gateway", "orders", "worker-svc"] as const;
export type Role = (typeof ROLES)[number];

// Downstream URLs default to the in-namespace Service names (ARCHITECTURE §5.1).
const envSchema = z.object({
  ROLE: z.enum(ROLES),
  PORT: z.coerce.number().int().min(1).max(65535).default(8080),
  LOG_LEVEL: z.enum(["trace", "debug", "info", "warn", "error", "fatal"]).default("info"),
  ORDERS_URL: z.url().default("http://orders:8080"),
  WORKER_URL: z.url().default("http://worker-svc:8080"),
  TRAFFIC_INTERVAL_MS: z.coerce.number().int().min(100).default(500),
});

export type Config = z.infer<typeof envSchema>;

export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  return envSchema.parse(env);
}
