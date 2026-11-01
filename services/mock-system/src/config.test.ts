import { describe, expect, it } from "vitest";
import { loadConfig } from "./config.js";

describe("loadConfig", () => {
  it("applies defaults", () => {
    const config = loadConfig({ ROLE: "orders" });
    expect(config).toMatchObject({
      ROLE: "orders",
      PORT: 8080,
      ORDERS_URL: "http://orders:8080",
      WORKER_URL: "http://worker-svc:8080",
      TRAFFIC_INTERVAL_MS: 500,
    });
  });

  it("rejects an unknown role", () => {
    expect(() => loadConfig({ ROLE: "payments" })).toThrow();
  });

  it("requires a role", () => {
    expect(() => loadConfig({})).toThrow();
  });
});
