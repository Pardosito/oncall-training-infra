import {
  DeleteMessageCommand,
  ReceiveMessageCommand,
  type Message,
  type SQSClient,
} from "@aws-sdk/client-sqs";
import type { Logger } from "pino";
import type { HandleResult } from "./handler.js";

// Long-polls `faults` (ARCHITECTURE §8). A message is deleted only after it was handled.
// Invalid messages and failures stay in the queue; after 3 receives SQS moves them to the DLQ.

export interface PollerDeps {
  sqs: Pick<SQSClient, "send">;
  queueUrl: string;
  waitTimeSeconds: number;
  handle: (body: string | undefined) => Promise<HandleResult>;
  logger: Logger;
  /** Pause after an SQS error, so a bad credential doesn't spin the CPU. */
  errorBackoffMs?: number;
}

export interface Poller {
  /** Resolves when the loop has stopped and the in-flight message is finished. */
  done: Promise<void>;
  stop(): void;
  /** Time of the last successful ReceiveMessage, for /healthz. */
  lastPollAt(): number;
}

export function startPoller(deps: PollerDeps): Poller {
  const abort = new AbortController();
  let lastPoll = Date.now();

  const loop = async () => {
    while (!abort.signal.aborted) {
      let messages: Message[];
      try {
        const res = await deps.sqs.send(
          new ReceiveMessageCommand({
            QueueUrl: deps.queueUrl,
            MaxNumberOfMessages: 1,
            WaitTimeSeconds: deps.waitTimeSeconds,
          }),
          { abortSignal: abort.signal },
        );
        lastPoll = Date.now();
        messages = res.Messages ?? [];
      } catch (err) {
        if (abort.signal.aborted) break;
        deps.logger.error({ err }, "receive from faults failed");
        await sleep(deps.errorBackoffMs ?? 5000, abort.signal);
        continue;
      }

      // Finish in-flight work even if stop() is called meanwhile.
      for (const message of messages) {
        await processMessage(deps, message);
      }
    }
  };

  const done = loop();
  return {
    done,
    stop: () => abort.abort(),
    lastPollAt: () => lastPoll,
  };
}

export async function processMessage(deps: PollerDeps, message: Message): Promise<void> {
  const log = deps.logger.child({ messageId: message.MessageId });
  let result: HandleResult;
  try {
    result = await deps.handle(message.Body);
  } catch (err) {
    log.error({ err }, "fault handling failed; leaving message for retry");
    return;
  }

  if (result.kind === "invalid") {
    log.error({ error: result.error }, "invalid fault message; leaving it for the DLQ");
    return;
  }

  try {
    await deps.sqs.send(
      new DeleteMessageCommand({ QueueUrl: deps.queueUrl, ReceiptHandle: message.ReceiptHandle }),
    );
    log.info({ faultId: result.fault.faultId, kind: result.kind }, "fault message deleted");
  } catch (err) {
    // The redelivery is skipped as a duplicate by faultId, then deleted.
    log.error({ err, faultId: result.fault.faultId }, "delete failed; message will come back");
  }
}

function sleep(ms: number, signal: AbortSignal): Promise<void> {
  return new Promise((resolve) => {
    const timer = setTimeout(resolve, ms);
    signal.addEventListener("abort", () => {
      clearTimeout(timer);
      resolve();
    });
  });
}
