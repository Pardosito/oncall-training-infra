import type { Logger } from "pino";
import type { MockCluster } from "./cluster.js";
import { parseFault, type Fault } from "./fault.js";
import type { EventSink } from "./events.js";
import type { SessionRecorder } from "./recorder.js";

// One FAULT message (ARCHITECTURE §8): parse → check session → apply → record → (caller deletes).
// Apply comes before record so TTD/TTR never start before the fault exists (INF-101).
// The session check comes first so a fault for an abandoned or finished session is never
// applied: the api sends FAULT with DelaySeconds = warmup, and the user can abandon meanwhile.

export type HandleResult =
  | { kind: "done"; fault: Fault }
  | { kind: "duplicate"; fault: Fault }
  | { kind: "skipped"; fault: Fault; reason: string }
  | { kind: "invalid"; error: string };

export interface HandlerDeps {
  cluster: MockCluster;
  recorder: SessionRecorder;
  mockNamespace: string;
  logger: Logger;
  /** FAULT_INJECTED in Redis, when REDIS_URL is set. Best effort: never fails the fault. */
  events?: EventSink;
  now?: () => Date;
  /** faultIds already handled by this process; SQS is at-least-once. */
  seen?: Set<string>;
}

export function createHandler(deps: HandlerDeps) {
  const now = deps.now ?? (() => new Date());
  const seen = deps.seen ?? new Set<string>();

  return async function handle(body: string | undefined): Promise<HandleResult> {
    const parsed = parseFault(body, deps.mockNamespace);
    if (!parsed.ok) return { kind: "invalid", error: parsed.error };

    const fault = parsed.fault;
    const log = deps.logger.child({ faultId: fault.faultId, sessionId: fault.sessionId });

    // A redelivery after a successful run: don't break the system a second time
    // (DELETE_PODS would cause a second outage). Only the delete is missing.
    if (seen.has(fault.faultId)) {
      log.info("fault already handled, skipping");
      return { kind: "duplicate", fault };
    }

    const state = await deps.recorder.getState(fault);
    if (state !== "STARTING") {
      // INCIDENT_ACTIVE: applied before a restart (the in-memory set is gone); don't break it twice.
      // Anything else (FAILED, RESOLVED, no item): the session is over or never existed.
      const reason = state === undefined ? "no session item" : `session is ${state}`;
      log.warn({ state }, `not applying fault: ${reason}`);
      seen.add(fault.faultId);
      trimSeen(seen);
      return { kind: "skipped", fault, reason };
    }

    await apply(deps.cluster, fault, log);

    const at = now();
    const recorded = await deps.recorder.recordFaultInjected(fault, at);
    if (recorded.outcome === "recorded") {
      log.info("session is INCIDENT_ACTIVE");
      await recordEvent(deps, fault, recorded.scenarioId, at, log);
    } else {
      // The session left STARTING between the check and the apply (e.g. abandoned). The mock
      // system stays broken until the worker's baseline reset for that session.
      log.warn("fault applied but the session had already left STARTING");
    }

    seen.add(fault.faultId);
    trimSeen(seen);
    return { kind: "done", fault };
  };
}

// Only after the session moved to INCIDENT_ACTIVE, so a redelivery (already-recorded) never adds
// a second line. The event log is analytics: a Redis error is logged and the fault still counts.
async function recordEvent(
  deps: HandlerDeps,
  fault: Fault,
  scenarioId: string | undefined,
  at: Date,
  log: Logger,
): Promise<void> {
  if (!deps.events) return;
  if (!scenarioId) {
    log.warn("session item has no scenario_id; FAULT_INJECTED not recorded");
    return;
  }
  try {
    await deps.events.faultInjected(fault, scenarioId, at);
  } catch (err) {
    log.warn({ err }, "could not record FAULT_INJECTED");
  }
}

async function apply(cluster: MockCluster, fault: Fault, log: Logger): Promise<void> {
  const { deployment } = fault.target;
  switch (fault.type) {
    case "SCALE_TO_ZERO":
      // Idempotent: scaling to 0 twice is the same as once.
      await cluster.scaleToZero(deployment);
      log.info({ deployment }, "scaled to zero");
      return;
    case "DELETE_PODS": {
      const deleted = await cluster.deletePods(deployment);
      log.info({ deployment, deleted }, "pods deleted");
      return;
    }
  }
}

// One fault per session and one session at a time, so this stays tiny; cap it anyway.
const MAX_SEEN = 1000;
function trimSeen(seen: Set<string>): void {
  while (seen.size > MAX_SEEN) {
    const oldest = seen.values().next().value;
    if (oldest === undefined) return;
    seen.delete(oldest);
  }
}
