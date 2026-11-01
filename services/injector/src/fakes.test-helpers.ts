import { pino } from "pino";
import type { MockCluster } from "./cluster.js";
import type { RecordOutcome, SessionRecorder } from "./recorder.js";

export const silentLogger = pino({ level: "silent" });

export function faultBody(overrides: Record<string, unknown> = {}): string {
  return JSON.stringify({
    faultId: "f-1",
    sessionId: "s-1",
    userId: "u-1",
    type: "SCALE_TO_ZERO",
    target: { namespace: "mock", deployment: "orders" },
    ...overrides,
  });
}

/** Records every call in one shared list, so tests can assert the order. */
export function fakes(options: { recordOutcome?: RecordOutcome; applyError?: Error } = {}) {
  const calls: string[] = [];
  const cluster: MockCluster = {
    scaleToZero(deployment) {
      calls.push(`scaleToZero:${deployment}`);
      return options.applyError ? Promise.reject(options.applyError) : Promise.resolve();
    },
    deletePods(deployment) {
      calls.push(`deletePods:${deployment}`);
      return options.applyError ? Promise.reject(options.applyError) : Promise.resolve(2);
    },
  };
  const recorder: SessionRecorder = {
    recordFaultInjected(fault) {
      calls.push(`record:${fault.sessionId}`);
      return Promise.resolve(options.recordOutcome ?? "recorded");
    },
  };
  return { calls, cluster, recorder };
}
