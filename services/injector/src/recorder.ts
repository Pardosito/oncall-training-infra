import { ConditionalCheckFailedException } from "@aws-sdk/client-dynamodb";
import { GetCommand, UpdateCommand, type DynamoDBDocumentClient } from "@aws-sdk/lib-dynamodb";
import type { Fault } from "./fault.js";

// Session item access (backend ARCHITECTURE §7.1, §8.3, cross-repo).
// Before applying: read the state, so a fault for a session the user abandoned during the
// warmup is never applied. After applying: move STARTING → INCIDENT_ACTIVE so TTD/TTR start.

export type RecordOutcome = "recorded" | "already-recorded";

export interface SessionRecorder {
  /** Current `state` of the session item, or undefined if there's no item. Strongly consistent. */
  getState(fault: Fault): Promise<string | undefined>;
  recordFaultInjected(fault: Fault, at: Date): Promise<RecordOutcome>;
}

export function createSessionRecorder(
  tableName: string,
  doc: Pick<DynamoDBDocumentClient, "send">,
): SessionRecorder {
  return {
    async getState(fault) {
      const res = await doc.send(
        new GetCommand({
          TableName: tableName,
          Key: { user_id: fault.userId, session_id: fault.sessionId },
          ProjectionExpression: "#state",
          ExpressionAttributeNames: { "#state": "state" },
          ConsistentRead: true,
        }),
      );
      const state: unknown = res.Item?.state;
      return typeof state === "string" ? state : undefined;
    },

    async recordFaultInjected(fault, at) {
      const now = at.toISOString();
      try {
        await doc.send(
          new UpdateCommand({
            TableName: tableName,
            Key: { user_id: fault.userId, session_id: fault.sessionId },
            UpdateExpression: "SET #state = :active, fault_injected_at = :now, updated_at = :now",
            ConditionExpression: "#state = :starting",
            ExpressionAttributeNames: { "#state": "state" },
            ExpressionAttributeValues: {
              ":active": "INCIDENT_ACTIVE",
              ":starting": "STARTING",
              ":now": now,
            },
          }),
        );
        return "recorded";
      } catch (err) {
        // Already INCIDENT_ACTIVE, or the session ended between the state check and now.
        if (err instanceof ConditionalCheckFailedException) return "already-recorded";
        throw err;
      }
    },
  };
}
