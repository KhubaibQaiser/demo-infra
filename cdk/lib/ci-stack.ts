import * as cdk from "aws-cdk-lib";
import * as iam from "aws-cdk-lib/aws-iam";
import { Construct } from "constructs";

export interface DemoCiProps extends cdk.StackProps {
  /** ARN of the GitHub OIDC provider that already exists in the account (created by portfolio-v2). */
  githubOidcProviderArn: string;
  /** OIDC subject repo part. This repo uses immutable subjects: "owner@ownerId/name@repoId" (gh api repos/OWNER/NAME/actions/oidc/customization/sub). */
  repo: string;
}

/** Role that GitHub Actions in this repo assumes (OIDC, no stored AWS keys). It may only assume CDK bootstrap roles. */
export class DemoCiStack extends cdk.Stack {
  readonly role: iam.Role;

  constructor(scope: Construct, id: string, props: DemoCiProps) {
    super(scope, id, { terminationProtection: true, ...props });

    const provider = iam.OpenIdConnectProvider.fromOpenIdConnectProviderArn(this, "Github", props.githubOidcProviderArn);
    this.role = new iam.Role(this, "DeployRole", {
      roleName: "demo-infra-gha-deploy",
      maxSessionDuration: cdk.Duration.hours(1),
      assumedBy: new iam.WebIdentityPrincipal(provider.openIdConnectProviderArn, {
        StringEquals: { "token.actions.githubusercontent.com:aud": "sts.amazonaws.com" },
        StringLike: {
          "token.actions.githubusercontent.com:sub": [
            `repo:${props.repo}:ref:refs/heads/main`,
            `repo:${props.repo}:environment:production`,
          ],
        },
      }),
    });

    this.role.addToPolicy(new iam.PolicyStatement({
      actions: ["sts:AssumeRole"],
      resources: [`arn:${this.partition}:iam::${this.account}:role/cdk-*`],
    }));
    this.role.addToPolicy(new iam.PolicyStatement({
      actions: ["ssm:GetParameter"],
      resources: [`arn:${this.partition}:ssm:${this.region}:${this.account}:parameter/cdk-bootstrap/*`],
    }));

    new cdk.CfnOutput(this, "RoleArn", { value: this.role.roleArn });
    cdk.Tags.of(this).add("project", "demo-infra");
  }
}
