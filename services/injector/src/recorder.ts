import { ConditionalCheckFailedException } from "@aws-sdk/client-dynamodb";
import { UpdateCommand, type DynamoDBDocumentClient } from "@aws-sdk/lib-dynamodb";
import type { Fault } from "./fault.js";

// Record step (backend ARCHITECTURE §8.3, cross-repo): after the fault is applied, move the
// session STARTING → INCIDENT_ACTIVE so TTD/TTR start counting.

export type RecordOutcome = "recorded" | "already-recorded";

export interface SessionRecorder {
  recordFaultInjected(fault: Fault, at: Date): Promise<RecordOutcome>;
}

export function createSessionRecorder(
  tableName: string,
  doc: Pick<DynamoDBDocumentClient, "send">,
): SessionRecorder {
  return {
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
        // Already INCIDENT_ACTIVE (a redelivery) or the session ended/was abandoned meanwhile.
        if (err instanceof ConditionalCheckFailedException) return "already-recorded";
        throw err;
      }
    },
  };
}
