import { z } from "zod";

// FAULT message (ARCHITECTURE §7, cross-repo). Sent by the state machine
// (in the MVP: by the backend api) to the `faults` queue.

export const MOCK_DEPLOYMENTS = ["gateway", "orders", "worker-svc"] as const;
export type MockDeployment = (typeof MOCK_DEPLOYMENTS)[number];

export const FAULT_TYPES = ["SCALE_TO_ZERO", "DELETE_PODS"] as const;

export const faultSchema = z.object({
  faultId: z.string().min(1),
  sessionId: z.string().min(1),
  userId: z.string().min(1),
  type: z.enum(FAULT_TYPES),
  target: z.object({
    namespace: z.string().min(1),
    deployment: z.enum(MOCK_DEPLOYMENTS),
  }),
  sentAt: z.string().optional(),
});

export type Fault = z.infer<typeof faultSchema>;

export type ParseResult = { ok: true; fault: Fault } | { ok: false; error: string };

/**
 * Parses a message body and checks the target against the allowed list before anything
 * touches the cluster (CONVENTIONS §4).
 */
export function parseFault(body: string | undefined, mockNamespace: string): ParseResult {
  let json: unknown;
  try {
    json = JSON.parse(body ?? "");
  } catch {
    return { ok: false, error: "body is not JSON" };
  }

  const parsed = faultSchema.safeParse(json);
  if (!parsed.success) {
    return { ok: false, error: z.prettifyError(parsed.error) };
  }

  if (parsed.data.target.namespace !== mockNamespace) {
    return {
      ok: false,
      error: `target namespace "${parsed.data.target.namespace}" is not "${mockNamespace}"`,
    };
  }

  return { ok: true, fault: parsed.data };
}
