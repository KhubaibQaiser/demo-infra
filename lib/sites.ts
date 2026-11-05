import { readFileSync } from "node:fs";

export interface Site {
  name: string;
  subdomain: string;
  pages: {
    project: string;
    repo: string;
    branch: string;
    buildCommand: string;
    outputDir: string;
    env?: Record<string, string>;
  };
  backend?: {
    subdomain: string;
    renderService: string;
    healthPath: string;
    keepalive?: boolean;
    repo: string; // "owner/name" of the Laravel repo Render builds
    branch: string;
    dockerfile: string;
    env?: Record<string, string>; // non-secret; secrets are injected by OpenTofu
  };
}

export interface SitesConfig {
  apex: string;
  zone: { id: string };
  sites: Site[];
  keepalive: { intervalMinutes: number; activeHoursUtc: string };
}

export const PLACEHOLDER_ZONE = "Z0000000000000";
export const RENDER_FREE_HOURS = 750;
const LABEL = /^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$/;
const RESERVED = new Set(["www", "@"]);

export function loadSites(path = new URL("../sites.json", import.meta.url)): SitesConfig {
  return JSON.parse(readFileSync(path, "utf8")) as SitesConfig;
}

export const frontendHost = (c: SitesConfig, s: Site) => `${s.subdomain}.${c.apex}`;
export const apiHost = (c: SitesConfig, s: Site) => `${s.backend!.subdomain}.${c.apex}`;
export const pagesTarget = (s: Site) => `${s.pages.project}.pages.dev`;
export const renderTarget = (s: Site) => `${s.backend!.renderService}.onrender.com`;

/** Number of hours a day covered by "a-b" (inclusive), e.g. "6-20" -> 15. */
export function activeHoursPerDay(range: string): number {
  const m = /^(\d{1,2})-(\d{1,2})$/.exec(range);
  if (!m) throw new Error(`activeHoursUtc must look like "6-20", got "${range}"`);
  const [a, b] = [Number(m[1]), Number(m[2])];
  if (a > 23 || b > 23 || a > b) throw new Error(`activeHoursUtc out of range: "${range}"`);
  return b - a + 1;
}

/** Throws on the first problem. strict = also reject the placeholder zone id (used before deploy). */
export function validateSites(c: SitesConfig, strict = false): void {
  if (!/^[a-z0-9.-]+\.[a-z]{2,}$/.test(c.apex)) throw new Error(`invalid apex "${c.apex}"`);
  if (strict && (!c.zone?.id || c.zone.id === PLACEHOLDER_ZONE)) throw new Error("zone.id is still the placeholder");
  if (!/^Z[A-Z0-9]+$/.test(c.zone?.id ?? "")) throw new Error(`invalid zone id "${c.zone?.id}"`);

  const { intervalMinutes: iv, activeHoursUtc } = c.keepalive;
  if (!Number.isInteger(iv) || iv < 5 || iv > 14) throw new Error("keepalive.intervalMinutes must be 5-14 (Render sleeps after 15 min)");

  const hosts = new Set<string>();
  const names = new Set<string>();
  const projects = new Set<string>();
  for (const s of c.sites) {
    if (names.has(s.name)) throw new Error(`duplicate site name "${s.name}"`);
    if (projects.has(s.pages.project)) throw new Error(`duplicate pages project "${s.pages.project}"`);
    names.add(s.name);
    projects.add(s.pages.project);
    for (const label of [s.subdomain, s.backend?.subdomain].filter((x): x is string => !!x)) {
      if (!LABEL.test(label) || RESERVED.has(label)) throw new Error(`invalid or reserved subdomain "${label}"`);
      if (hosts.has(label)) throw new Error(`duplicate subdomain "${label}"`);
      hosts.add(label);
    }
    if (s.backend && !s.backend.healthPath.startsWith("/")) throw new Error(`healthPath must start with "/" (${s.name})`);
    if (s.backend?.env?.APP_ENV === "production") throw new Error(`demo:set-password refuses APP_ENV=production (${s.name})`);
  }

  const targets = c.sites.filter((s) => s.backend?.keepalive).length;
  const monthlyHours = targets * activeHoursPerDay(activeHoursUtc) * 31;
  if (monthlyHours > RENDER_FREE_HOURS) {
    throw new Error(`keep-alive would use ${monthlyHours} h/month; Render free allows ${RENDER_FREE_HOURS}. Narrow activeHoursUtc or disable a target.`);
  }
}

export function keepaliveTargets(c: SitesConfig): string[] {
  return c.sites
    .filter((s) => s.backend?.keepalive)
    .map((s) => `https://${apiHost(c, s)}${s.backend!.healthPath}`);
}
