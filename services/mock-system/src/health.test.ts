import { createServer, type Server } from "node:http";
import type { AddressInfo } from "node:net";
import { afterEach, describe, expect, it, vi } from "vitest";
import { checkHealth } from "./health.js";
import type { Fetch } from "./downstream.js";

const base = { ORDERS_URL: "http://orders:8080", WORKER_URL: "http://worker-svc:8080" };

const okFetch: Fetch = vi.fn(() => Promise.resolve(new Response("{}", { status: 200 })));

describe("checkHealth with a fake downstream", () => {
  it("worker-svc is always up and calls nothing", async () => {
    const fetchFn = vi.fn<Fetch>();
    const result = await checkHealth({ ...base, ROLE: "worker-svc" }, fetchFn);
    expect(result.statusCode).toBe(200);
    expect(fetchFn).not.toHaveBeenCalled();
  });

  it("gateway checks orders /health", async () => {
    const result = await checkHealth({ ...base, ROLE: "gateway" }, okFetch);
    expect(result).toMatchObject({ statusCode: 200, body: { status: "up", role: "gateway" } });
    expect(okFetch).toHaveBeenCalledWith("http://orders:8080/health", expect.anything());
  });

  it("orders checks worker-svc /ping", async () => {
    const fetchFn = vi.fn<Fetch>(() => Promise.resolve(new Response("{}", { status: 200 })));
    await checkHealth({ ...base, ROLE: "orders" }, fetchFn);
    expect(fetchFn).toHaveBeenCalledWith("http://worker-svc:8080/ping", expect.anything());
  });

  it("reports a downstream 503 as down", async () => {
    const fetchFn: Fetch = () => Promise.resolve(new Response("{}", { status: 503 }));
    const result = await checkHealth({ ...base, ROLE: "gateway" }, fetchFn);
    expect(result).toMatchObject({
      statusCode: 503,
      body: { status: "down", reason: "HTTP 503 from orders:8080" },
    });
  });

  it("reports connection refused with the host", async () => {
    const fetchFn: Fetch = () =>
      Promise.reject(new TypeError("fetch failed", { cause: { code: "ECONNREFUSED" } }));
    const result = await checkHealth({ ...base, ROLE: "gateway" }, fetchFn);
    expect(result.body).toMatchObject({ status: "down", reason: "ECONNREFUSED orders:8080" });
  });

  it("reports DNS failures (Service has no endpoints/doesn't exist)", async () => {
    const fetchFn: Fetch = () =>
      Promise.reject(new TypeError("fetch failed", { cause: { code: "ENOTFOUND" } }));
    const result = await checkHealth({ ...base, ROLE: "orders" }, fetchFn);
    expect(result.body).toMatchObject({ reason: "ENOTFOUND worker-svc:8080" });
  });
});

describe("checkHealth against real sockets", () => {
  let server: Server | undefined;
  afterEach(
    () => new Promise<void>((resolve) => (server ? server.close(() => resolve()) : resolve())),
  );

  const listen = (handler: Parameters<typeof createServer>[1]) =>
    new Promise<string>((resolve) => {
      server = createServer(handler).listen(0, "127.0.0.1", () => {
        resolve(`http://127.0.0.1:${(server!.address() as AddressInfo).port}`);
      });
    });

  it("times out a slow orders after 800 ms", async () => {
    const url = await listen((_req, res) => {
      setTimeout(() => res.end("late"), 1500);
    });
    const result = await checkHealth({ ...base, ROLE: "gateway", ORDERS_URL: url });
    expect(result.body).toMatchObject({ status: "down", reason: "timeout after 800ms" });
    expect(result.body.latencyMs).toBeGreaterThanOrEqual(790);
    expect(result.body.latencyMs).toBeLessThan(1400);
  });

  it("times out a slow worker-svc after 500 ms", async () => {
    const url = await listen((_req, res) => {
      setTimeout(() => res.end("late"), 1500);
    });
    const result = await checkHealth({ ...base, ROLE: "orders", WORKER_URL: url });
    expect(result.body).toMatchObject({ status: "down", reason: "timeout after 500ms" });
  });

  it("reports a closed port as ECONNREFUSED", async () => {
    const url = await listen((_req, res) => res.end());
    await new Promise<void>((resolve) => server!.close(() => resolve()));
    server = undefined;
    const result = await checkHealth({ ...base, ROLE: "gateway", ORDERS_URL: url });
    expect(result.body).toMatchObject({ status: "down" });
    expect((result.body as { reason: string }).reason).toMatch(/^ECONNREFUSED 127\.0\.0\.1:\d+$/);
  });
});
