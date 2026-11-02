import { describe, expect, it } from "vitest";
import { parseFault } from "./fault.js";

const valid = {
  faultId: "f-1",
  sessionId: "s-1",
  userId: "u-1",
  type: "SCALE_TO_ZERO",
  target: { namespace: "mock", deployment: "orders" },
  sentAt: "2026-11-05T12:00:00.000Z",
};
const body = (overrides: Record<string, unknown> = {}) =>
  JSON.stringify({ ...valid, ...overrides });

// Verbatim copy of the backend's test/fixtures/fault-message.json (cross-repo contract).
const backendFixture = `{
  "faultId": "01JBQ5A7C2D3E4F5G6H7J8K9M0",
  "sessionId": "01JBQ4ZJ8V2N7K3M5P6R8S9T0W",
  "userId": "8f1c2b9e-0d4a-4c1e-9b7a-3f2e1d0c9b8a",
  "type": "SCALE_TO_ZERO",
  "target": { "namespace": "mock", "deployment": "orders" },
  "sentAt": "2026-11-05T18:00:20.000Z"
}`;

describe("parseFault", () => {
  it("accepts the backend's FAULT fixture", () => {
    expect(parseFault(backendFixture, "mock").ok).toBe(true);
  });

  it("accepts a valid SCALE_TO_ZERO", () => {
    const result = parseFault(body(), "mock");
    expect(result).toEqual({ ok: true, fault: valid });
  });

  it("accepts DELETE_PODS on every mock deployment", () => {
    for (const deployment of ["gateway", "orders", "worker-svc"]) {
      const result = parseFault(
        body({ type: "DELETE_PODS", target: { namespace: "mock", deployment } }),
        "mock",
      );
      expect(result.ok).toBe(true);
    }
  });

  it("sentAt is optional", () => {
    const rest: Partial<typeof valid> = { ...valid };
    delete rest.sentAt;
    expect(parseFault(JSON.stringify(rest), "mock").ok).toBe(true);
  });

  it("rejects malformed JSON", () => {
    expect(parseFault("{nope", "mock")).toEqual({ ok: false, error: "body is not JSON" });
  });

  it("rejects an empty body", () => {
    expect(parseFault(undefined, "mock").ok).toBe(false);
  });

  it("rejects a target in another namespace", () => {
    const result = parseFault(body({ target: { namespace: "app", deployment: "orders" } }), "mock");
    expect(result).toEqual({ ok: false, error: 'target namespace "app" is not "mock"' });
  });

  it("rejects an unknown deployment", () => {
    const result = parseFault(
      body({ target: { namespace: "mock", deployment: "backend-api" } }),
      "mock",
    );
    expect(result.ok).toBe(false);
  });

  it("rejects an unknown fault type", () => {
    expect(parseFault(body({ type: "CORRUPT_DB" }), "mock").ok).toBe(false);
  });

  it("rejects a missing userId (the record step needs it)", () => {
    const rest: Partial<typeof valid> = { ...valid };
    delete rest.userId;
    expect(parseFault(JSON.stringify(rest), "mock").ok).toBe(false);
  });
});
