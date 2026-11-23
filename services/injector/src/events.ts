import type { Redis } from "ioredis";
import type { Fault } from "./fault.js";

// FAULT_INJECTED in the session's event buffer (ARCHITECTURE §5.4 step 5, backend §7.2/§7.4).
// The backend worker flushes `session:{id}:events` to S3 when the session ends; the line format
// is the backend's event line (the Glue table's columns), every key present.

export const EVENTS_TTL_SECONDS = 2 * 60 * 60;
export const eventsKey = (sessionId: string) => `session:${sessionId}:events`;

export interface EventSink {
  faultInjected(fault: Fault, scenarioId: string, at: Date): Promise<void>;
}

export function faultInjectedLine(fault: Fault, scenarioId: string, at: Date) {
  return {
    ts: at.toISOString(),
    user_id: fault.userId,
    session_id: fault.sessionId,
    scenario_id: scenarioId,
    type: "FAULT_INJECTED",
    action: null,
    target: fault.target.deployment,
    params: null,
    valid: null,
    score: null,
    ttd_seconds: null,
    ttr_seconds: null,
  };
}

/** `RPUSH` + `EXPIRE 2h` in one MULTI, like the backend's `EventLog.append`. */
export function createRedisEventSink(redis: Pick<Redis, "multi">): EventSink {
  return {
    async faultInjected(fault, scenarioId, at) {
      const key = eventsKey(fault.sessionId);
      const results = await redis
        .multi()
        .rpush(key, JSON.stringify(faultInjectedLine(fault, scenarioId, at)))
        .expire(key, EVENTS_TTL_SECONDS)
        .exec();
      const failed = results?.find(([error]) => error);
      if (!results || failed) throw failed?.[0] ?? new Error("event append aborted");
    },
  };
}
