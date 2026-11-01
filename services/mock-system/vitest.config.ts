import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    name: "mock-system",
    include: ["src/**/*.test.ts"],
    // Unit tests never reach AWS: fake credentials and an endpoint nothing listens on.
    env: {
      AWS_ACCESS_KEY_ID: "test",
      AWS_SECRET_ACCESS_KEY: "test",
      AWS_SESSION_TOKEN: "test",
      AWS_REGION: "us-east-1",
      AWS_ENDPOINT_URL: "http://127.0.0.1:9",
      AWS_PROFILE: "",
    },
  },
});
