import { createServer, type IncomingMessage, type Server } from "node:http";
import type { AddressInfo } from "node:net";
import { KubeConfig } from "@kubernetes/client-node";
import { afterEach, describe, expect, it } from "vitest";
import { createMockCluster } from "./cluster.js";

interface Seen {
  method: string;
  url: string;
  contentType: string | undefined;
  body: string;
}

// A tiny fake API server: checks the exact requests the Role has to allow.
async function fakeApi(): Promise<{ server: Server; kc: KubeConfig; seen: Seen[] }> {
  const seen: Seen[] = [];
  const server = createServer((req: IncomingMessage, res) => {
    let body = "";
    req.on("data", (c: Buffer) => (body += c.toString()));
    req.on("end", () => {
      seen.push({
        method: req.method!,
        url: req.url!,
        contentType: req.headers["content-type"],
        body,
      });
      res.setHeader("content-type", "application/json");
      if (req.method === "GET" && req.url!.startsWith("/api/v1/namespaces/mock/pods")) {
        res.end(
          JSON.stringify({
            kind: "PodList",
            apiVersion: "v1",
            items: [{ metadata: { name: "orders-a" } }, { metadata: { name: "orders-b" } }],
          }),
        );
        return;
      }
      res.end(JSON.stringify({ kind: "Status", apiVersion: "v1", status: "Success" }));
    });
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const kc = new KubeConfig();
  kc.loadFromOptions({
    clusters: [
      {
        name: "fake",
        server: `http://127.0.0.1:${(server.address() as AddressInfo).port}`,
        skipTLSVerify: true,
      },
    ],
    users: [{ name: "fake" }],
    contexts: [{ name: "fake", cluster: "fake", user: "fake" }],
    currentContext: "fake",
  });
  return { server, kc, seen };
}

describe("mock cluster gateway", () => {
  let server: Server | undefined;
  afterEach(
    () => new Promise<void>((resolve) => (server ? server.close(() => resolve()) : resolve())),
  );

  it("scales with a merge patch on deployments/scale in the mock namespace", async () => {
    const api = await fakeApi();
    server = api.server;
    await createMockCluster("mock", api.kc).scaleToZero("orders");

    expect(api.seen).toHaveLength(1);
    expect(api.seen[0]).toMatchObject({
      method: "PATCH",
      url: "/apis/apps/v1/namespaces/mock/deployments/orders/scale",
      contentType: "application/merge-patch+json",
    });
    expect(JSON.parse(api.seen[0]!.body)).toEqual({ spec: { replicas: 0 } });
  });

  it("lists pods by label and deletes them one by one (no deletecollection)", async () => {
    const api = await fakeApi();
    server = api.server;
    const deleted = await createMockCluster("mock", api.kc).deletePods("orders");

    expect(deleted).toBe(2);
    const [list, ...deletes] = api.seen;
    expect(list!.method).toBe("GET");
    expect(decodeURIComponent(list!.url)).toContain("labelSelector=app.kubernetes.io/name=orders");
    expect(deletes.map((d) => `${d.method} ${d.url}`).sort()).toEqual([
      "DELETE /api/v1/namespaces/mock/pods/orders-a",
      "DELETE /api/v1/namespaces/mock/pods/orders-b",
    ]);
  });
});
