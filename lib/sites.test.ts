import { describe, expect, it } from "vitest";
import { activeHoursPerDay, keepaliveTargets, loadSites, validateSites, type SitesConfig } from "./sites.ts";

const base = (): SitesConfig => structuredClone(loadSites());

describe("validateSites", () => {
  it("accepts the committed sites.json", () => expect(() => validateSites(base())).not.toThrow());
  it("rejects the placeholder zone in strict mode", () => {
    const c = base();
    c.zone.id = "Z0000000000000";
    expect(() => validateSites(c, true)).toThrow(/placeholder/);
  });
  it("rejects duplicate subdomains across frontend and api", () => {
    const c = base();
    c.sites[0].backend!.subdomain = c.sites[0].subdomain;
    expect(() => validateSites(c)).toThrow(/duplicate subdomain/);
  });
  it("rejects reserved and malformed labels", () => {
    const c = base();
    c.sites[0].subdomain = "www";
    expect(() => validateSites(c)).toThrow(/reserved/);
    c.sites[0].subdomain = "Bad_Label";
    expect(() => validateSites(c)).toThrow(/invalid/);
  });
  it("rejects intervals outside 5-14", () => {
    const c = base();
    c.keepalive.intervalMinutes = 15;
    expect(() => validateSites(c)).toThrow(/5-14/);
    c.keepalive.intervalMinutes = 4;
    expect(() => validateSites(c)).toThrow(/5-14/);
  });
  it("fails when keep-alive would exceed 750 h/month", () => {
    const c = base();
    c.keepalive.activeHoursUtc = "0-23"; // 744 h for one target: ok
    expect(() => validateSites(c)).not.toThrow();
    c.sites.push({ ...structuredClone(c.sites[0]), name: "b", subdomain: "b", pages: { ...c.sites[0].pages, project: "b" }, backend: { ...c.sites[0].backend!, subdomain: "b-api" } });
    expect(() => validateSites(c)).toThrow(/h\/month/);
  });
  it("allows a static site with no backend", () => {
    const c = base();
    c.sites.push({ name: "stray", subdomain: "stray", pages: { ...c.sites[0].pages, project: "stray" } });
    expect(() => validateSites(c)).not.toThrow();
    expect(keepaliveTargets(c)).toHaveLength(1);
    expect(keepaliveTargets(c)[0]).toMatch(/\/api\/health\/ready$/);
  });
});

describe("activeHoursPerDay", () => {
  it("counts inclusive hours", () => {
    expect(activeHoursPerDay("6-20")).toBe(15);
    expect(activeHoursPerDay("0-23")).toBe(24);
  });
  it("rejects bad ranges", () => {
    expect(() => activeHoursPerDay("20-6")).toThrow();
    expect(() => activeHoursPerDay("x")).toThrow();
  });
});
