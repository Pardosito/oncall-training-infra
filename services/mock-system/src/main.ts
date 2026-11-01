import { pino } from "pino";
import { loadConfig } from "./config.js";
import { createMockServer } from "./server.js";
import { startTraffic } from "./traffic.js";

const config = loadConfig();
const logger = pino({ level: config.LOG_LEVEL, base: { role: config.ROLE } });

const server = createMockServer(config, logger);
const stopTraffic = config.ROLE === "gateway" ? startTraffic(config, logger) : () => undefined;

server.listen(config.PORT, () => {
  logger.info({ port: config.PORT }, "mock service listening");
});

const shutdown = (signal: string) => {
  logger.info({ signal }, "shutting down");
  stopTraffic();
  server.close(() => process.exit(0));
  // Don't hang on keep-alive connections past the pod's grace period.
  setTimeout(() => process.exit(0), 5000).unref();
};
process.on("SIGTERM", () => shutdown("SIGTERM"));
process.on("SIGINT", () => shutdown("SIGINT"));
