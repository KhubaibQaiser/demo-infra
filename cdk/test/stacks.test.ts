import * as cdk from "aws-cdk-lib";
import { Match, Template } from "aws-cdk-lib/assertions";
import { describe, expect, it } from "vitest";
import { loadSites } from "../../lib/sites.ts";
import { DemoCiStack } from "../lib/ci-stack.ts";
import { DemoDnsStack } from "../lib/dns-stack.ts";

const dns = (mutate?: (c: ReturnType<typeof loadSites>) => void) => {
  const c = structuredClone(loadSites());
  mutate?.(c);
  return Template.fromStack(new DemoDnsStack(new cdk.App(), "T", c, { env: { region: "us-east-1" } }));
};

describe("DemoDnsStack", () => {
  it("creates frontend and api CNAMEs for a site with a backend", () => {
    const t = dns();
    t.resourceCountIs("AWS::Route53::RecordSet", 2);
    t.hasResourceProperties("AWS::Route53::RecordSet", { Name: "lumen.khubaibqaiser.com.", Type: "CNAME", ResourceRecords: ["lumen-demo.pages.dev"], TTL: "300" });
    t.hasResourceProperties("AWS::Route53::RecordSet", { Name: "lumen-api.khubaibqaiser.com.", Type: "CNAME", ResourceRecords: ["lumen-demo-api-kq.onrender.com"] });
  });
  it("creates only one record for a static site", () => {
    const t = dns((c) => c.sites.push({ name: "stray", subdomain: "stray", pages: { ...c.sites[0].pages, project: "stray" } }));
    t.resourceCountIs("AWS::Route53::RecordSet", 3);
  });
  it("throws on a duplicate subdomain", () => {
    expect(() => dns((c) => { c.sites[0].backend!.subdomain = "lumen"; })).toThrow(/duplicate/);
  });
});

describe("DemoCiStack", () => {
  const t = Template.fromStack(new DemoCiStack(new cdk.App(), "C", {
    env: { account: "111111111111", region: "us-east-1" },
    githubOidcProviderArn: "arn:aws:iam::111111111111:oidc-provider/token.actions.githubusercontent.com",
    repo: "KhubaibQaiser/demo-infra",
  }));
  it("trusts only main and the production environment", () => {
    t.hasResourceProperties("AWS::IAM::Role", {
      AssumeRolePolicyDocument: Match.objectLike({
        Statement: [Match.objectLike({ Condition: Match.objectLike({ StringLike: { "token.actions.githubusercontent.com:sub": [
          "repo:KhubaibQaiser/demo-infra:ref:refs/heads/main",
          "repo:KhubaibQaiser/demo-infra:environment:production",
        ] } }) })],
      }),
    });
  });
  it("can only assume cdk-* roles", () => {
    const json = JSON.stringify(t.toJSON());
    expect(json).toContain("role/cdk-*");
    expect(json).not.toContain('"Action":"*"');
  });
});
