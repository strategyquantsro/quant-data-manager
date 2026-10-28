# Security policy

## Supported versions

| Module | Version | Supported |
|--------|---------|-----------|
| SqCOT  | 4.2.x   | Yes |
| SqCOT  | < 4.2   | No. Upgrade to the latest [release](https://github.com/strategyquantsro/quant-data-manager/releases). |

## Reporting a vulnerability

Please do not report security problems through public issues, discussions or forum posts.

1. **Preferred:** use GitHub private vulnerability reporting. Open the **Security** tab of this repository and choose **Report a vulnerability**, or go directly to <https://github.com/strategyquantsro/quant-data-manager/security/advisories/new>.
2. If you cannot use GitHub, contact StrategyQuant support at <https://strategyquant.com/support/> and mark the request as security-related. It will be forwarded to the maintainers.

Please include the module and version (for example `SqCOT 4.2.5`, from the service startup log or `BUILDINFO.json`), the MetaTrader 5 build, a description of the problem, steps to reproduce and the impact you expect. Never include your Quant Data Manager licence key in a report, log or screenshot.

## What to expect

- We acknowledge new reports within five business days.
- We keep you informed while we investigate and prepare a fix.
- Fixes ship in the next module release. We credit reporters in the release notes unless they prefer to stay anonymous.

## Scope

This policy covers the code published in this repository: MQL5 sources, example programs, documentation, configuration files and GitHub workflows.

Vulnerabilities in StrategyQuant products or services outside this repository, such as the Quant Data Manager application or the data endpoint at `cdn.strategyquantcdn.com`, can be reported through the same channels and will be passed to the responsible team.
