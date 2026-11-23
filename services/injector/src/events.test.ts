import { describe, expect, it, vi } from "vitest";
import { createRedisEventSink, EVENTS_TTL_SECONDS, faultInjectedLine } from "./events.js";
import type { Fault } from "./fault.js";

const fault: Fault = {
  faultId: "f-1",
  sessionId: "s-1",
  userId: "u-1",
  type: "SCALE_TO_ZERO",
  target: { namespace: "mock", deployment: "orders" },
};
const at = new Date("2026-11-19T18:00:20.000Z");

describe("FAULT_INJECTED event line", () => {
  it("has the backend's twelve keys in order (Glue columns), nulls where not applicable", () => {
    expect(faultInjectedLine(fault, "orders-down", at)).toEqual({
      ts: "2026-11-19T18:00:20.000Z",
      user_id: "u-1",
      session_id: "s-1",
      scenario_id: "orders-down",
      type: "FAULT_INJECTED",
      action: null,
      target: "orders",
      params: null,
      valid: null,
      score: null,
      ttd_seconds: null,
      ttr_seconds: null,
    });
    expect(Object.keys(faultInjectedLine(fault, "x", at))).toEqual([
      "ts",
      "user_id",
      "session_id",
      "scenario_id",
      "type",
      "action",
      "target",
      "params",
      "valid",
      "score",
      "ttd_seconds",
      "ttr_seconds",
    ]);
  });
});

describe("Redis event sink", () => {
  const fakeMulti = (results: [Error | null, unknown][] | null) => {
    const chain = {
      rpush: vi.fn(() => chain),
      expire: vi.fn(() => chain),
      exec: vi.fn(() => Promise.resolve(results)),
    };
    return { redis: { multi: () => chain } as never, chain };
  };

  it("appends to session:{id}:events and refreshes the 2 h TTL in one MULTI", async () => {
    const { redis, chain } = fakeMulti([
      [null, 1],
      [null, 1],
    ]);
    await createRedisEventSink(redis).faultInjected(fault, "orders-down", at);
    expect(chain.rpush).toHaveBeenCalledWith(
      "session:s-1:events",
      JSON.stringify(faultInjectedLine(fault, "orders-down", at)),
    );
    expect(chain.expire).toHaveBeenCalledWith("session:s-1:events", EVENTS_TTL_SECONDS);
  });

  it("throws when a command in the MULTI failed", async () => {
    const { redis } = fakeMulti([
      [new Error("WRONGTYPE"), null],
      [null, 1],
    ]);
    await expect(createRedisEventSink(redis).faultInjected(fault, "x", at)).rejects.toThrow(
      "WRONGTYPE",
    );
  });
});
