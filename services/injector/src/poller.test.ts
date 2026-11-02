import { DeleteMessageCommand, ReceiveMessageCommand, type SQSClient } from "@aws-sdk/client-sqs";
import { describe, expect, it, vi } from "vitest";
import { createHandler } from "./handler.js";
import { processMessage, startPoller, type PollerDeps } from "./poller.js";
import { fakes, faultBody, silentLogger } from "./fakes.test-helpers.js";

type Send = Pick<SQSClient, "send">["send"];

function deps(send: Send, f = fakes()): PollerDeps {
  return {
    sqs: { send },
    queueUrl: "https://sqs.us-east-1.amazonaws.com/123/oncall-training-faults",
    waitTimeSeconds: 0,
    handle: createHandler({ ...f, mockNamespace: "mock", logger: silentLogger }),
    logger: silentLogger,
    errorBackoffMs: 1,
  };
}

const tick = () => new Promise((resolve) => setTimeout(resolve, 1));
const message = (body: string) => ({ MessageId: "m-1", ReceiptHandle: "rh-1", Body: body });

describe("processMessage", () => {
  it("deletes the message after a successful apply + record", async () => {
    const send = vi.fn(() => Promise.resolve({})) as unknown as Send;
    await processMessage(deps(send), message(faultBody()));
    const commands = vi.mocked(send).mock.calls.map((c) => c[0]);
    expect(commands).toHaveLength(1);
    expect(commands[0]).toBeInstanceOf(DeleteMessageCommand);
    expect(commands[0]!.input).toMatchObject({ ReceiptHandle: "rh-1" });
  });

  it("deletes a skipped fault (session already ended)", async () => {
    const send = vi.fn(() => Promise.resolve({})) as unknown as Send;
    await processMessage(deps(send, fakes({ state: "FAILED" })), message(faultBody()));
    expect(vi.mocked(send).mock.calls.map((c) => c[0])[0]).toBeInstanceOf(DeleteMessageCommand);
  });

  it("leaves an invalid message for the DLQ", async () => {
    const send = vi.fn(() => Promise.resolve({})) as unknown as Send;
    await processMessage(deps(send), message("not json"));
    expect(send).not.toHaveBeenCalled();
  });

  it("leaves the message when the apply fails", async () => {
    const send = vi.fn(() => Promise.resolve({})) as unknown as Send;
    await processMessage(
      deps(send, fakes({ applyError: new Error("boom") })),
      message(faultBody()),
    );
    expect(send).not.toHaveBeenCalled();
  });

  it("survives a failed delete", async () => {
    const send = vi.fn(() => Promise.reject(new Error("throttled"))) as unknown as Send;
    await expect(processMessage(deps(send), message(faultBody()))).resolves.toBeUndefined();
  });
});

describe("startPoller", () => {
  it("receives, handles and deletes, then stops cleanly", async () => {
    const f = fakes();
    let receives = 0;
    const send = vi.fn((command: unknown) => {
      if (command instanceof ReceiveMessageCommand) {
        receives += 1;
        // Real SQS long-polls; yield a tick so the loop doesn't starve the event loop.
        return tick().then(() => (receives === 1 ? { Messages: [message(faultBody())] } : {}));
      }
      return Promise.resolve({});
    }) as unknown as Send;

    const poller = startPoller(deps(send, f));
    await vi.waitFor(() => expect(receives).toBeGreaterThan(1));
    poller.stop();
    await poller.done;

    expect(f.calls).toEqual(["getState:s-1", "scaleToZero:orders", "record:s-1"]);
    expect(vi.mocked(send).mock.calls.some((c) => c[0] instanceof DeleteMessageCommand)).toBe(true);
  });

  it("keeps polling after a receive error", async () => {
    let receives = 0;
    const send = vi.fn(() => {
      receives += 1;
      return receives === 1 ? Promise.reject(new Error("expired token")) : tick().then(() => ({}));
    }) as unknown as Send;

    const poller = startPoller(deps(send));
    await vi.waitFor(() => expect(receives).toBeGreaterThan(2));
    poller.stop();
    await poller.done;
  });
});
