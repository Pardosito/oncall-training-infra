import type { Config } from "./config.js";
import { callDownstream, type Fetch } from "./downstream.js";

// Health chain (ARCHITECTURE §9): gateway → orders /health, orders → worker-svc /ping.
export const GATEWAY_TIMEOUT_MS = 800;
export const ORDERS_TIMEOUT_MS = 500;

export type HealthBody =
  | { status: "up"; role: Config["ROLE"]; latencyMs: number }
  | { status: "down"; role: Config["ROLE"]; latencyMs: number; reason: string };

export interface HealthResult {
  statusCode: 200 | 503;
  body: HealthBody;
}

type HealthConfig = Pick<Config, "ROLE" | "ORDERS_URL" | "WORKER_URL">;

export async function checkHealth(config: HealthConfig, fetchFn?: Fetch): Promise<HealthResult> {
  const role = config.ROLE;
  if (role === "worker-svc") {
    return { statusCode: 200, body: { status: "up", role, latencyMs: 0 } };
  }

  const [url, timeoutMs] =
    role === "gateway"
      ? [new URL("/health", config.ORDERS_URL).toString(), GATEWAY_TIMEOUT_MS]
      : [new URL("/ping", config.WORKER_URL).toString(), ORDERS_TIMEOUT_MS];

  const result = await callDownstream(url, timeoutMs, fetchFn);
  if (result.ok) {
    return { statusCode: 200, body: { status: "up", role, latencyMs: result.latencyMs } };
  }
  return {
    statusCode: 503,
    body: { status: "down", role, latencyMs: result.latencyMs, reason: result.reason },
  };
}
