import { SQSClient } from "@aws-sdk/client-sqs";
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient } from "@aws-sdk/lib-dynamodb";
import { Redis } from "ioredis";
import { pino } from "pino";
import { createMockCluster } from "./cluster.js";
import { loadConfig } from "./config.js";
import { createRedisEventSink } from "./events.js";
import { createHandler } from "./handler.js";
import { startPoller } from "./poller.js";
import { createSessionRecorder } from "./recorder.js";
import { createHealthServer } from "./server.js";

const config = loadConfig();
const logger = pino({ level: config.LOG_LEVEL, base: { service: "injector" } });

// Optional (MVP runs without it): FAULT_INJECTED goes to the session's event buffer.
// `rediss://` is ElastiCache with in-transit TLS (D-09). Commands fail fast while Redis is down
// and the handler only logs it, so a Redis outage never blocks a fault.
const redis = config.REDIS_URL
  ? new Redis(config.REDIS_URL, {
      ...(config.REDIS_URL.startsWith("rediss://") ? { tls: {} } : {}),
      connectTimeout: 5_000,
      maxRetriesPerRequest: 1,
    })
  : undefined;
let lastRedisError = 0;
redis?.on("error", (err: Error) => {
  if (Date.now() - lastRedisError < 10_000) return;
  lastRedisError = Date.now();
  logger.warn({ err }, "redis connection error");
});

// SDK clients use the default credential chain (node role in EKS) and AWS_ENDPOINT_URL locally.
const handle = createHandler({
  cluster: createMockCluster(config.MOCK_NAMESPACE),
  recorder: createSessionRecorder(
    config.SESSIONS_TABLE,
    DynamoDBDocumentClient.from(new DynamoDBClient({ region: config.AWS_REGION })),
  ),
  mockNamespace: config.MOCK_NAMESPACE,
  logger,
  ...(redis ? { events: createRedisEventSink(redis) } : {}),
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
    .finally(() => {
      redis?.disconnect();
      server.close(() => process.exit(0));
    });
  setTimeout(() => process.exit(1), 25_000).unref();
};
process.on("SIGTERM", () => shutdown("SIGTERM"));
process.on("SIGINT", () => shutdown("SIGINT"));
