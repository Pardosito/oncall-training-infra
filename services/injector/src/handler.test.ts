import { describe, expect, it } from "vitest";
import { createHandler } from "./handler.js";
import { fakes, faultBody, silentLogger } from "./fakes.test-helpers.js";

const make = (f: ReturnType<typeof fakes>) =>
  createHandler({ ...f, mockNamespace: "mock", logger: silentLogger });

describe("fault handler", () => {
  it("applies SCALE_TO_ZERO, then records", async () => {
    const f = fakes();
    const result = await make(f)(faultBody());
    expect(result.kind).toBe("done");
    expect(f.calls).toEqual(["getState:s-1", "scaleToZero:orders", "record:s-1"]);
  });

  it("applies DELETE_PODS, then records", async () => {
    const f = fakes();
    await make(f)(
      faultBody({ type: "DELETE_PODS", target: { namespace: "mock", deployment: "gateway" } }),
    );
    expect(f.calls).toEqual(["getState:s-1", "deletePods:gateway", "record:s-1"]);
  });

  it("treats an already-recorded session as done", async () => {
    const f = fakes({ recordOutcome: "already-recorded" });
    expect((await make(f)(faultBody())).kind).toBe("done");
  });

  it("doesn't record when the apply fails (so TTD never starts without a fault)", async () => {
    const f = fakes({ applyError: new Error("forbidden") });
    await expect(make(f)(faultBody())).rejects.toThrow("forbidden");
    expect(f.calls).toEqual(["getState:s-1", "scaleToZero:orders"]);
  });

  it("skips a redelivered faultId without touching the cluster again", async () => {
    const f = fakes();
    const handle = make(f);
    await handle(faultBody({ type: "DELETE_PODS" }));
    const second = await handle(faultBody({ type: "DELETE_PODS" }));
    expect(second.kind).toBe("duplicate");
    expect(f.calls).toEqual(["getState:s-1", "deletePods:orders", "record:s-1"]);
  });

  it("retries fully when a previous attempt failed", async () => {
    const failing = fakes({ applyError: new Error("timeout") });
    const seen = new Set<string>();
    await expect(
      createHandler({ ...failing, mockNamespace: "mock", logger: silentLogger, seen })(faultBody()),
    ).rejects.toThrow();
    const ok = fakes();
    const result = await createHandler({
      ...ok,
      mockNamespace: "mock",
      logger: silentLogger,
      seen,
    })(faultBody());
    expect(result.kind).toBe("done");
    expect(ok.calls).toEqual(["getState:s-1", "scaleToZero:orders", "record:s-1"]);
  });

  it.each([
    ["FAILED", "session is FAILED"],
    ["RESOLVED", "session is RESOLVED"],
    ["INCIDENT_ACTIVE", "session is INCIDENT_ACTIVE"],
    [null, "no session item"],
  ])("doesn't apply when the session is %s", async (state, reason) => {
    const f = fakes({ state });
    const result = await make(f)(faultBody());
    expect(result).toMatchObject({ kind: "skipped", reason });
    expect(f.calls).toEqual(["getState:s-1"]);
  });

  it("an abandoned-during-warmup fault is skipped again on redelivery", async () => {
    const f = fakes({ state: "FAILED" });
    const handle = make(f);
    await handle(faultBody());
    expect((await handle(faultBody())).kind).toBe("duplicate");
    expect(f.calls).toEqual(["getState:s-1"]);
  });

  it("returns invalid without touching anything", async () => {
    const f = fakes();
    const result = await make(f)(faultBody({ target: { namespace: "app", deployment: "orders" } }));
    expect(result.kind).toBe("invalid");
    expect(f.calls).toEqual([]);
  });
});
