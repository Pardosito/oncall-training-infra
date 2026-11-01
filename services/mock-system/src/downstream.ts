// Calls another mock service and turns any failure into a short, readable reason.
// The reasons end up in the logs the user sees in VIEW_LOGS (ARCHITECTURE §9).

export type Fetch = typeof fetch;

export type DownstreamResult =
  { ok: true; latencyMs: number } | { ok: false; latencyMs: number; reason: string };

export async function callDownstream(
  url: string,
  timeoutMs: number,
  fetchFn: Fetch = fetch,
): Promise<DownstreamResult> {
  const started = performance.now();
  const latency = () => Math.round(performance.now() - started);
  try {
    const res = await fetchFn(url, { signal: AbortSignal.timeout(timeoutMs) });
    // Drain the body so the connection can be reused.
    await res.text();
    if (res.ok) return { ok: true, latencyMs: latency() };
    return { ok: false, latencyMs: latency(), reason: `HTTP ${res.status} from ${hostOf(url)}` };
  } catch (err) {
    return { ok: false, latencyMs: latency(), reason: describeError(err, url, timeoutMs) };
  }
}

export function describeError(err: unknown, url: string, timeoutMs: number): string {
  if (err instanceof Error && (err.name === "TimeoutError" || err.name === "AbortError")) {
    return `timeout after ${timeoutMs}ms`;
  }
  // Node's fetch wraps socket errors: TypeError("fetch failed") with a `cause` that has a code.
  const cause = err instanceof Error ? (err.cause as { code?: unknown } | undefined) : undefined;
  if (cause && typeof cause.code === "string") {
    return `${cause.code} ${hostOf(url)}`;
  }
  return err instanceof Error ? err.message : String(err);
}

function hostOf(url: string): string {
  const u = new URL(url);
  return u.port ? `${u.hostname}:${u.port}` : u.hostname;
}
