import { pino } from "pino";
import { describe, expect, it, vi } from "vitest";
import { loadConfig } from "./config.js";
import { sendOneRequest } from "./traffic.js";
import type { Fetch } from "./downstream.js";

function captureLogger() {
  const lines: Record<string, unknown>[] = [];
  const logger = pino(
    { level: "info" },
    { write: (line: string) => lines.push(JSON.parse(line) as Record<string, unknown>) },
  );
  return { logger, lines };
}

const config = loadConfig({ ROLE: "gateway" });

describe("synthetic traffic", () => {
  it("logs info on success", async () => {
    const { logger, lines } = captureLogger();
    const fetchFn = vi.fn<Fetch>(() => Promise.resolve(new Response("{}", { status: 200 })));
    await sendOneRequest(config, logger, fetchFn);
    expect(fetchFn).toHaveBeenCalledWith("http://orders:8080/health", expect.anything());
    expect(lines).toHaveLength(1);
    expect(lines[0]).toMatchObject({ level: 30, msg: "GET /orders 200" });
  });

  it("logs error with the cause on failure", async () => {
    const { logger, lines } = captureLogger();
    const fetchFn: Fetch = () =>
      Promise.reject(new TypeError("fetch failed", { cause: { code: "ECONNREFUSED" } }));
    await sendOneRequest(config, logger, fetchFn);
    expect(lines[0]).toMatchObject({
      level: 50,
      msg: "GET /orders failed: ECONNREFUSED orders:8080",
      reason: "ECONNREFUSED orders:8080",
    });
  });
});
