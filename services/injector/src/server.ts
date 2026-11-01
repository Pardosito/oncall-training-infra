import { createServer, type Server } from "node:http";

/**
 * /healthz (ARCHITECTURE §8). Unhealthy if the poll loop hasn't completed a receive for a
 * while (stuck loop): Kubernetes then restarts the pod. A receive takes up to 20 s.
 */
export function createHealthServer(lastPollAt: () => number, maxSilenceMs = 120_000): Server {
  return createServer((req, res) => {
    const path = new URL(req.url ?? "/", "http://localhost").pathname;
    if (path !== "/healthz") {
      res.writeHead(404).end();
      return;
    }
    const silentMs = Date.now() - lastPollAt();
    const ok = silentMs < maxSilenceMs;
    res
      .writeHead(ok ? 200 : 503, { "content-type": "application/json" })
      .end(JSON.stringify({ status: ok ? "up" : "down", lastPollAgoMs: silentMs }));
  });
}
