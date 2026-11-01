import type { Logger } from "pino";
import type { MockCluster } from "./cluster.js";
import { parseFault, type Fault } from "./fault.js";
import type { SessionRecorder } from "./recorder.js";

// One FAULT message (ARCHITECTURE §8): parse → apply → record → (caller deletes).
// Apply comes before record so TTD/TTR never start before the fault exists (INF-101).

export type HandleResult =
  | { kind: "done"; fault: Fault }
  | { kind: "duplicate"; fault: Fault }
  | { kind: "invalid"; error: string };

export interface HandlerDeps {
  cluster: MockCluster;
  recorder: SessionRecorder;
  mockNamespace: string;
  logger: Logger;
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

    await apply(deps.cluster, fault, log);

    const outcome = await deps.recorder.recordFaultInjected(fault, now());
    log.info({ outcome }, "session updated");

    seen.add(fault.faultId);
    trimSeen(seen);
    return { kind: "done", fault };
  };
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
