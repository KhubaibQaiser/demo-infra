import { describe, expect, it } from "vitest";
import { loadSites } from "../../lib/sites.ts";
import { buildWranglerConfig } from "../gen-wrangler.ts";
import { pingAll } from "../src/index.ts";

describe("pingAll", () => {
  it("hits every target and survives errors", async () => {
    const calls: string[] = [];
    const fake = (async (url: string) => {
      calls.push(url);
      if (url.includes("bad")) throw new DOMException("timeout", "TimeoutError");
      return new Response("ok", { status: 200 });
    }) as unknown as typeof fetch;
    const out = await pingAll(["https://a/x", "https://bad/x", "https://c/x"], fake);
    expect(calls).toHaveLength(3);
    expect(out[0]).toMatch(/200/);
    expect(out[1]).toMatch(/ERROR TimeoutError/);
    expect(out[2]).toMatch(/200/);
  });
});

describe("buildWranglerConfig", () => {
  it("derives cron and targets from sites.json", () => {
    const { config } = buildWranglerConfig(loadSites());
    expect(config.triggers.crons).toEqual(["*/10 6-20 * * *"]);
    expect(JSON.parse(config.vars.TARGETS)).toEqual(["https://lumen-api.khubaibqaiser.com/api/health/live"]);
    expect(config.workers_dev).toBe(false);
  });
  it("rejects a bad interval", () => {
    const c = structuredClone(loadSites());
    c.keepalive.intervalMinutes = 30;
    expect(() => buildWranglerConfig(c)).toThrow(/5-14/);
  });
});
