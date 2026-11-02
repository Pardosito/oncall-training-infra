import { ConditionalCheckFailedException } from "@aws-sdk/client-dynamodb";
import { GetCommand, UpdateCommand } from "@aws-sdk/lib-dynamodb";
import { describe, expect, it, vi } from "vitest";
import { createSessionRecorder } from "./recorder.js";
import type { Fault } from "./fault.js";

const fault: Fault = {
  faultId: "f-1",
  sessionId: "s-1",
  userId: "u-1",
  type: "SCALE_TO_ZERO",
  target: { namespace: "mock", deployment: "orders" },
};
const at = new Date("2026-11-05T12:00:00.000Z");

type Doc = Parameters<typeof createSessionRecorder>[1];
const docWith = (impl: () => Promise<unknown>) => {
  const send = vi.fn(impl);
  return { doc: { send } as unknown as Doc, send };
};

describe("session recorder", () => {
  it("moves STARTING → INCIDENT_ACTIVE with a conditional update", async () => {
    const { doc, send } = docWith(() => Promise.resolve({}));
    const outcome = await createSessionRecorder("Sessions", doc).recordFaultInjected(fault, at);

    expect(outcome).toBe("recorded");
    const command = (send.mock.calls[0] as unknown[])[0] as UpdateCommand;
    expect(command).toBeInstanceOf(UpdateCommand);
    expect(command.input).toMatchObject({
      TableName: "Sessions",
      Key: { user_id: "u-1", session_id: "s-1" },
      ConditionExpression: "#state = :starting",
      ExpressionAttributeNames: { "#state": "state" },
      ExpressionAttributeValues: {
        ":active": "INCIDENT_ACTIVE",
        ":starting": "STARTING",
        ":now": "2026-11-05T12:00:00.000Z",
      },
    });
    expect(command.input.UpdateExpression).toContain("fault_injected_at = :now");
    expect(command.input.UpdateExpression).toContain("updated_at = :now");
  });

  it("reads the state with a consistent read", async () => {
    const { doc, send } = docWith(() => Promise.resolve({ Item: { state: "FAILED" } }));
    await expect(createSessionRecorder("Sessions", doc).getState(fault)).resolves.toBe("FAILED");
    const command = (send.mock.calls[0] as unknown[])[0] as GetCommand;
    expect(command).toBeInstanceOf(GetCommand);
    expect(command.input).toMatchObject({
      TableName: "Sessions",
      Key: { user_id: "u-1", session_id: "s-1" },
      ConsistentRead: true,
    });
  });

  it("returns undefined when there's no session item", async () => {
    const { doc } = docWith(() => Promise.resolve({}));
    await expect(createSessionRecorder("Sessions", doc).getState(fault)).resolves.toBeUndefined();
  });

  it("treats ConditionalCheckFailed as already recorded", async () => {
    const { doc } = docWith(() =>
      Promise.reject(new ConditionalCheckFailedException({ message: "failed", $metadata: {} })),
    );
    await expect(
      createSessionRecorder("Sessions", doc).recordFaultInjected(fault, at),
    ).resolves.toBe("already-recorded");
  });

  it("rethrows other errors so the message is retried", async () => {
    const { doc } = docWith(() => Promise.reject(new Error("ProvisionedThroughputExceeded")));
    await expect(
      createSessionRecorder("Sessions", doc).recordFaultInjected(fault, at),
    ).rejects.toThrow("ProvisionedThroughputExceeded");
  });
});
