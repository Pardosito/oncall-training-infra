import type { Server } from "node:http";
import type { AddressInfo } from "node:net";
import { afterEach, describe, expect, it } from "vitest";
import { createHealthServer } from "./server.js";

describe("/healthz", () => {
  let server: Server;
  afterEach(() => new Promise<void>((resolve) => server.close(() => resolve())));

  const start = async (lastPollAt: number) => {
    server = createHealthServer(() => lastPollAt, 60_000);
    await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
    return `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  };

  it("is 200 while the loop polls", async () => {
    const base = await start(Date.now());
    expect((await fetch(`${base}/healthz`)).status).toBe(200);
  });

  it("is 503 when the loop is stuck", async () => {
    const base = await start(Date.now() - 120_000);
    expect((await fetch(`${base}/healthz`)).status).toBe(503);
  });
});
