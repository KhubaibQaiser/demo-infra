# ADR 0001: The Route 53 zone stays in portfolio-v2

Status: accepted · Date: 2026-11-05

## Context
`portfolio-v2` owns the `khubaibqaiser.com` hosted zone (stack `Portfolio-Dns`, us-east-1) and its certificates.
This repo only needs to add CNAMEs for demo sites.

## Decision
`demo-infra` references the zone by ID (`HostedZone.fromHostedZoneAttributes`, no CloudFormation export/import,
consistent with portfolio ADR 0001) and adds records in its own stack `DemoDns`.

## Why not extract the zone into a shared infra repo now
Moving a live zone between CloudFormation stacks needs retain-and-import on the production portfolio, for no demo benefit.
The zone ID, and therefore the registrar's nameservers, would not change, so the migration can be done later on its own.

## Consequences
- If portfolio-v2 deletes or recreates the zone, DemoDns breaks; its zone has termination protection/retention there.
- A shared `khubaib-infra` repo remains a valid future migration (separate ADR and plan).
