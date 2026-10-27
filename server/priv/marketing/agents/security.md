# Tuist security

How to evaluate Tuist's security posture and how to report a vulnerability.

## Assurance

Tuist is SOC 2 Type II certified. The [trust center](https://security.tuist.dev/) provides details and access to the latest report. The [full security statement](/marketing-markdown/source/security) describes the practices: TLS in transit and encryption of sensitive data at rest, role-based access with least privilege, code review with static analysis and automated testing, dependency monitoring, continuous monitoring and incident response, data minimization, and retention limits.

## Evaluating an integration

1. Review the trust center and the security page.
2. Identify what your integration uploads: build artifacts, build and test metadata, bundles, or app previews.
3. Configure access: organization membership, [SSO](/en/docs-markdown/guides/integrations/authentication/sso) and [SCIM](/en/docs-markdown/guides/integrations/authentication/scim), CI authentication through OIDC or scoped tokens, cache upload restrictions, and preview visibility.
4. Review [data retention](/en/docs-markdown/guides/server/data-retention), the [privacy policy](/privacy), and the [data processing addendum](/data-processing-addendum).
5. If data must stay on your infrastructure, evaluate [self-hosting](/en/docs-markdown/guides/server/self-host/server) (Enterprise) or contact the team.

## Reporting vulnerabilities

Email [contact@tuist.dev](mailto:contact@tuist.dev) with a description, reproduction steps, and relevant evidence. Give Tuist reasonable time to investigate before public disclosure, and avoid accessing other users' data or disrupting the service. There is no paid bug bounty; valid reports can be acknowledged publicly on request.

## Limitations

Certification evidences audited controls; it does not guarantee that every integration or customer configuration is secure. This guide does not replace the audit report, your contract, or your own review. Do not include credentials or unnecessary customer data in a report.
