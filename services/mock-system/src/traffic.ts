import type { Logger } from "pino";
import type { Config } from "./config.js";
import { callDownstream, type Fetch } from "./downstream.js";
import { GATEWAY_TIMEOUT_MS } from "./health.js";

// Synthetic traffic (ARCHITECTURE §9): the gateway calls orders on a timer and logs one
// line per request. These lines are what the user reads in "view logs".

export async function sendOneRequest(config: Config, logger: Logger, fetchFn?: Fetch) {
  const url = new URL("/health", config.ORDERS_URL).toString();
  const result = await callDownstream(url, GATEWAY_TIMEOUT_MS, fetchFn);
  if (result.ok) {
    logger.info({ latencyMs: result.latencyMs }, "GET /orders 200");
  } else {
    logger.error(
      { latencyMs: result.latencyMs, reason: result.reason },
      `GET /orders failed: ${result.reason}`,
    );
  }
  return result;
}

/** Starts the loop; returns a function that stops it. Requests never overlap. */
export function startTraffic(config: Config, logger: Logger, fetchFn?: Fetch): () => void {
  let stopped = false;
  let timer: NodeJS.Timeout | undefined;

  const tick = () => {
    sendOneRequest(config, logger, fetchFn)
      .catch((err: unknown) => logger.error({ err }, "traffic tick crashed"))
      .finally(() => {
        if (!stopped) timer = setTimeout(tick, config.TRAFFIC_INTERVAL_MS);
      });
  };
  timer = setTimeout(tick, config.TRAFFIC_INTERVAL_MS);

  return () => {
    stopped = true;
    clearTimeout(timer);
  };
}
