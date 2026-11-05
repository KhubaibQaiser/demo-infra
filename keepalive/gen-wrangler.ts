import { writeFileSync } from "node:fs";
import { activeHoursPerDay, keepaliveTargets, loadSites, validateSites, type SitesConfig } from "../lib/sites.ts";

export function buildWranglerConfig(c: SitesConfig) {
  validateSites(c);
  const { intervalMinutes, activeHoursUtc } = c.keepalive;
  const targets = keepaliveTargets(c);
  return {
    config: {
      name: "demo-keepalive",
      main: "src/index.ts",
      compatibility_date: "2026-01-01",
      workers_dev: false,
      triggers: { crons: [`*/${intervalMinutes} ${activeHoursUtc} * * *`] },
      vars: { TARGETS: JSON.stringify(targets) },
    },
    summary: `${targets.length} target(s), ${60 / intervalMinutes} hits/hour each, ${activeHoursPerDay(activeHoursUtc)} h/day`,
  };
}

if (process.argv[1]?.endsWith("gen-wrangler.ts")) {
  const { config, summary } = buildWranglerConfig(loadSites());
  writeFileSync(new URL("./wrangler.generated.jsonc", import.meta.url), JSON.stringify(config, null, 2) + "\n");
  console.log(`wrangler.generated.jsonc written: ${summary}`);
}
