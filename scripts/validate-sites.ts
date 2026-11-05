import { loadSites, validateSites } from "../lib/sites.ts";

const strict = process.argv.includes("--strict");
try {
  validateSites(loadSites(), strict);
  console.log(`sites.json OK${strict ? " (strict)" : ""}`);
} catch (e) {
  console.error(`sites.json invalid: ${(e as Error).message}`);
  process.exit(1);
}
