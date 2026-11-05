export interface Env {
  /** JSON array of URLs to GET. */
  TARGETS: string;
}

const TIMEOUT_MS = 10_000;

export async function pingAll(targets: string[], doFetch: typeof fetch = fetch): Promise<string[]> {
  const lines = await Promise.all(
    targets.map(async (url) => {
      const t0 = Date.now();
      try {
        const res = await doFetch(url, { signal: AbortSignal.timeout(TIMEOUT_MS), headers: { "user-agent": "demo-infra-keepalive" } });
        return `${url} ${res.status} ${Date.now() - t0}ms`;
      } catch (e) {
        return `${url} ERROR ${(e as Error).name} ${Date.now() - t0}ms`;
      }
    }),
  );
  return lines;
}

export default {
  // One failing target never stops the others; the next tick is the retry.
  async scheduled(_event: ScheduledController, env: Env): Promise<void> {
    for (const line of await pingAll(JSON.parse(env.TARGETS) as string[])) console.log(line);
  },
} satisfies ExportedHandler<Env>;
