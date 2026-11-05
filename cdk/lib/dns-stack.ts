import * as cdk from "aws-cdk-lib";
import * as route53 from "aws-cdk-lib/aws-route53";
import { Construct } from "constructs";
import { apiHost, frontendHost, pagesTarget, renderTarget, validateSites, type SitesConfig } from "../../lib/sites.ts";

/** CNAMEs for every demo site. The zone is owned by portfolio-v2 and referenced by ID (no CFN export/import, cf. its ADR 0001). */
export class DemoDnsStack extends cdk.Stack {
  constructor(scope: Construct, id: string, config: SitesConfig, props?: cdk.StackProps) {
    super(scope, id, { terminationProtection: true, ...props });
    validateSites(config);

    const zone = route53.HostedZone.fromHostedZoneAttributes(this, "Zone", {
      hostedZoneId: config.zone.id,
      zoneName: config.apex,
    });

    for (const site of config.sites) {
      new route53.CnameRecord(this, `Site-${site.name}`, {
        zone,
        recordName: frontendHost(config, site),
        domainName: pagesTarget(site),
        ttl: cdk.Duration.minutes(5),
      });
      if (site.backend) {
        new route53.CnameRecord(this, `Api-${site.name}`, {
          zone,
          recordName: apiHost(config, site),
          domainName: renderTarget(site),
          ttl: cdk.Duration.minutes(5),
        });
      }
    }

    cdk.Tags.of(this).add("project", "demo-infra");
    cdk.Tags.of(this).add("managed-by", "cdk");
  }
}
