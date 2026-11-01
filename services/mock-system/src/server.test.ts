import type { Server } from "node:http";
import type { AddressInfo } from "node:net";
import { pino } from "pino";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { loadConfig } from "./config.js";
import { createMockServer } from "./server.js";
import type { Fetch } from "./downstream.js";

const logger = pino({ level: "silent" });
const refused: Fetch = () =>
  Promise.reject(new TypeError("fetch failed", { cause: { code: "ECONNREFUSED" } }));

describe("mock server", () => {
  let server: Server;
  let base: string;

  beforeEach(async () => {
    server = createMockServer(loadConfig({ ROLE: "gateway" }), logger, refused);
    await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
    base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  });

  afterEach(() => new Promise<void>((resolve) => server.close(() => resolve())));

  it("/ping is 200 even when downstream is down", async () => {
    const res = await fetch(`${base}/ping`);
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ status: "up", role: "gateway" });
  });

  it("/health is 503 with a reason when downstream is down", async () => {
    const res = await fetch(`${base}/health`);
    expect(res.status).toBe(503);
    expect(await res.json()).toMatchObject({
      status: "down",
      role: "gateway",
      reason: "ECONNREFUSED orders:8080",
    });
  });

  it("unknown paths are 404", async () => {
    expect((await fetch(`${base}/nope`)).status).toBe(404);
  });

  it("non-GET methods are 405", async () => {
    expect((await fetch(`${base}/ping`, { method: "POST" })).status).toBe(405);
  });
});
