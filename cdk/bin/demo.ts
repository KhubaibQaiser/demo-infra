import * as cdk from "aws-cdk-lib";
import { loadSites } from "../../lib/sites.ts";
import { DemoCiStack } from "../lib/ci-stack.ts";
import { DemoDnsStack } from "../lib/dns-stack.ts";

const app = new cdk.App();
const env = { account: process.env.CDK_DEFAULT_ACCOUNT, region: "us-east-1" }; // same region as portfolio's Portfolio-Dns

new DemoDnsStack(app, "DemoDns", loadSites(), { env });

// Bootstrap-only stack: needs `-c githubOidcProviderArn=arn:aws:iam::<acct>:oidc-provider/token.actions.githubusercontent.com`
const oidc = app.node.tryGetContext("githubOidcProviderArn");
if (oidc) {
  new DemoCiStack(app, "DemoCi", { env, githubOidcProviderArn: oidc, repo: "KhubaibQaiser/demo-infra" });
}
