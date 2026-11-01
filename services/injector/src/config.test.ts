import { describe, expect, it } from "vitest";
import { loadConfig } from "./config.js";

const required = {
  FAULTS_QUEUE_URL: "https://sqs.us-east-1.amazonaws.com/123/oncall-training-faults",
  SESSIONS_TABLE: "Sessions",
};

describe("loadConfig", () => {
  it("runs without REDIS_URL (MVP, INF-139)", () => {
    const config = loadConfig(required);
    expect(config).toMatchObject({ MOCK_NAMESPACE: "mock", PORT: 8080, WAIT_TIME_SECONDS: 20 });
    expect(config.REDIS_URL).toBeUndefined();
  });

  it("requires the queue URL and table", () => {
    expect(() => loadConfig({ SESSIONS_TABLE: "Sessions" })).toThrow();
    expect(() => loadConfig({ FAULTS_QUEUE_URL: required.FAULTS_QUEUE_URL })).toThrow();
  });
});
