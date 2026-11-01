import { createServer, type Server, type ServerResponse } from "node:http";
import type { Logger } from "pino";
import type { Config } from "./config.js";
import { checkHealth } from "./health.js";
import type { Fetch } from "./downstream.js";

export function createMockServer(config: Config, logger: Logger, fetchFn?: Fetch): Server {
  return createServer((req, res) => {
    const path = new URL(req.url ?? "/", "http://localhost").pathname;

    if (req.method !== "GET") {
      sendJson(res, 405, { error: "method not allowed" });
      return;
    }

    if (path === "/ping") {
      // Liveness and readiness: up while the process is, whatever happens downstream.
      sendJson(res, 200, { status: "up", role: config.ROLE });
      return;
    }

    if (path === "/health") {
      checkHealth(config, fetchFn)
        .then(({ statusCode, body }) => sendJson(res, statusCode, body))
        .catch((err: unknown) => {
          logger.error({ err }, "health check crashed");
          sendJson(res, 500, { status: "down", role: config.ROLE, reason: "internal error" });
        });
      return;
    }

    sendJson(res, 404, { error: "not found" });
  });
}

function sendJson(res: ServerResponse, statusCode: number, body: unknown): void {
  const payload = JSON.stringify(body);
  res.writeHead(statusCode, {
    "content-type": "application/json",
    "content-length": Buffer.byteLength(payload),
  });
  res.end(payload);
}
