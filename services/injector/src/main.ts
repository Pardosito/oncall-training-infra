import { SQSClient } from "@aws-sdk/client-sqs";
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient } from "@aws-sdk/lib-dynamodb";
import { pino } from "pino";
import { createMockCluster } from "./cluster.js";
import { loadConfig } from "./config.js";
import { createHandler } from "./handler.js";
import { startPoller } from "./poller.js";
import { createSessionRecorder } from "./recorder.js";
import { createHealthServer } from "./server.js";

const config = loadConfig();
const logger = pino({ level: config.LOG_LEVEL, base: { service: "injector" } });

if (config.REDIS_URL) {
  // The FAULT_INJECTED event in Redis comes with ElastiCache in M2.
  logger.warn("REDIS_URL is set but Redis events aren't implemented yet; ignoring it");
}

// SDK clients use the default credential chain (node role in EKS) and AWS_ENDPOINT_URL locally.
const handle = createHandler({
  cluster: createMockCluster(config.MOCK_NAMESPACE),
  recorder: createSessionRecorder(
    config.SESSIONS_TABLE,
    DynamoDBDocumentClient.from(new DynamoDBClient({ region: config.AWS_REGION })),
  ),
  mockNamespace: config.MOCK_NAMESPACE,
  logger,
});

const poller = startPoller({
  sqs: new SQSClient({ region: config.AWS_REGION }),
  queueUrl: config.FAULTS_QUEUE_URL,
  waitTimeSeconds: config.WAIT_TIME_SECONDS,
  handle,
  logger,
});

const server = createHealthServer(() => poller.lastPollAt());
server.listen(config.PORT, () => {
  logger.info({ port: config.PORT, queue: config.FAULTS_QUEUE_URL }, "injector started");
});

const shutdown = (signal: string) => {
  logger.info({ signal }, "stopping: finishing in-flight fault");
  poller.stop();
  poller.done
    .catch((err: unknown) => logger.error({ err }, "poll loop failed"))
    .finally(() => server.close(() => process.exit(0)));
  setTimeout(() => process.exit(1), 25_000).unref();
};
process.on("SIGTERM", () => shutdown("SIGTERM"));
process.on("SIGINT", () => shutdown("SIGINT"));
