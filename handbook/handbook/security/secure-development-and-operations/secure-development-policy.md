---
{
  "title": "Secure development policy",
  "titleTemplate": ":title | Secure development and operations | Security | Tuist Handbook",
  "description": "To ensure that information security is designed and implemented within the development lifecycle for applications and information systems."
}
---
# Secure development policy

- **Policy owner:** Pedro Piñera Buendía
- **Effective date:** Nov 19, 2026

## Purpose

To ensure that information security is designed and implemented within the development lifecycle for applications and information systems.

## Scope

All Tuist GmbH applications and information systems that are business critical and/or process, store, or transmit Confidential data. This policy applies to all internal and external engineers and developers of Tuist GmbH software and infrastructure.

## General requirements

This policy describes the rules for the acquisition and development of software and systems that shall be applied to developments within the Tuist GmbH organization.

## System change control procedures

Changes to systems within the development lifecycle shall be controlled by the use of formal change control procedures. Change control procedures and requirements are described in the Tuist GmbH [Operations Security Policy](/security/secure-development-and-operations/operations-security-policy).

Software changes follow trunk-based development, as described in [Standard practices](/engineering/standard-practices), with `main` as the production branch. Engineers may push or merge changes directly to `main`. Opening a pull request and obtaining peer review before merge is optional, not required. Only people with write access to the repository may push to `main`.

Development takes place in a controlled development environment. The same deterministic checks used in continuous integration, including tests and linting, are also run in that environment before a change is merged. Validating a change there is therefore equivalent to running those CI checks in a controlled environment. After the change is pushed to `main`, the same checks run again in GitHub Actions, so the controls run both before and after the merge. The repository provides shared mise tasks for these checks, which engineers can run locally and which CI also uses.

Automated continuous integration is the primary automated pre-production control after a change lands on `main`. GitHub Actions workflows run on every push to `main` and on pull requests. These workflows include unit and integration tests, linting and formatting checks, dependency and container vulnerability scanning (Trivy), and CodeQL analysis. Required status checks are not configured as a merge gate on `main`. Failed checks remain visible in GitHub Actions and shall be investigated and remediated.

Engineers use AI coding agents locally to review changes against repository guidelines before merging. Those guidelines are documented in `AGENTS.md` throughout the repository (with `CLAUDE.md` pointing to the same instructions), including project-specific review skills for Swift and Elixir. Automated agent review also runs on pull requests: GitHub Copilot code review is enabled on the repository, and CodeRabbit is configured to review pull requests.

The following compensating controls also apply to changes that land on `main`:

- Deployment and rollback. Production software is deployed through documented GitHub Actions workflows. Changes to the hosted server are deployed from `main` first to a canary environment, then through acceptance checks, and then to production. Failed Helm releases are configured to roll back automatically. A previous known-good image or chart revision can be redeployed through the Server Deployment workflow.
- Monitoring and alerting. Production systems emit application and infrastructure metrics and error events. Application errors are sent to Tuist's self-hosted Atlas and Pulse error ingest. Kubernetes and application metrics are collected by the Kubernetes monitoring chart and evaluated as Grafana-managed alert rules, which route through Grafana IRM to Slack and the public status page.

Changes to `main` are traceable through git history and CI results. Failed CI checks on `main` are investigated and remediated. Peer review is not a required control.

## Software version control

All Tuist GmbH software is version controlled and synced between contributors (developers). Access to the central repository is restricted based on an employee's role. All code is written, tested, and saved in a local repository before being synced to the origin repository.

## Technical review of applications after operating platform changes

When operating platforms are changed, business critical applications shall be reviewed and tested to ensure that there is no adverse impact on organizational operations or security.

## Restrictions on changes to software packages

Modifications to third-party business application packages shall be discouraged, limited to necessary changes and all changes shall be strictly controlled.

## Secure system engineering principles

Principles for engineering secure systems shall be established, documented, maintained and applied to any information system implementation efforts.

At a minimum, the following secure-by-design and privacy-by-design principles shall be applied:

Secure-by-design principles:

1. Minimize attack surface area
2. Establish secure defaults
3. The principle of Least privilege
4. The principle of defense in depth
5. Fail securely
6. Don't trust services
7. Separation of duties
8. Avoid security by obscurity
9. Keep security simple
10. Fix security issues correctly

Privacy-by-design principles:

1. Proactive not Reactive; Preventative not Remedial
2. Privacy as the Default Setting
3. Privacy Embedded into Design
4. Full Functionality - Positive-Sum, not Zero-Sum
5. End-to-End Security - Full Lifecycle Protection
6. Visibility and Transparency - Keep it Open
7. Respect for User Privacy - Keep it User-Centric

Engineering documentation and technical references can be found in the process here: https://handbook.tuist.io

Software developers are expected to adhere to Tuist GmbH's coding standards throughout the development cycle, including standards for quality, commenting, and security.

## Secure development environment

Tuist GmbH shall establish and appropriately protect environments for system development and integration efforts that cover the entire system development lifecycle. The following environments shall be logically or physically segregated:

- Production
- Test / Staging
- Development

## System security testing

Testing of security functionality shall be performed at defined periods during the development life cycle. No code shall be deployed to Tuist GmbH production systems without documented, successful test results and evidence of security remediation activities.

Comprehensive penetration testing shall be performed at least annually on applications and cloud resources according to the requirements outlined in the [Penetration Testing Policy](/security/secure-development-and-operations/penetration-testing-policy). As per our [Shared Responsibility Model](/security/shared-responsibility-model), providers test the physical and hardware layers they operate. Tuist GmbH runs its own Kubernetes clusters, so testing of the cluster network and everything above it falls to Tuist GmbH rather than to a provider.

Application-level network traffic shall be monitored, controlled, managed, and periodically evaluated to identify vulnerabilities, anomalies, and capacity issues in accordance with the [Network Traffic Management Policy](/security/business-continuity-and-data-protection/network-traffic-management-policy).

Systems and applications shall log administrative, application, and transaction level user activity, and those logs shall be reviewed and acted upon in accordance with the [Logging and Monitoring Policy](/security/secure-development-and-operations/logging-and-monitoring-policy).

## Application vulnerability management

Application code should be scanned prior to deployment. Application code and dependencies are scanned using GitHub Dependabot, Snyk, Sobelow, and Trivy according to the requirements outlined in the [Vulnerability Scanning Policy](/security/secure-development-and-operations/vulnerability-scanning-policy). All Internet-exposed services and remote client applications shall undergo weekly vulnerability scanning. GitHub Actions workflows that run on every push to `main` and on pull requests include dependency and container vulnerability scanning (Trivy) and CodeQL analysis. Sobelow is used for detecting vulnerabilities in Elixir application code. Required status checks are not configured as a merge gate on `main`. Failed checks remain visible in GitHub Actions and shall be investigated and remediated. Patches for application vulnerabilities shall be deployed within the deadlines in the [Operations Security Policy](/security/secure-development-and-operations/operations-security-policy#technical-vulnerability-management).

## System acceptance testing

Acceptance testing programs and related criteria shall be established for new information systems, upgrades and new versions.

Prior to deploying code, a Release Checklist MUST be completed which includes a checklist of all Test Plans which show the completion of all associated tests and remediation of identified issues.

## Protection of test data

Test data shall be selected carefully, protected and controlled. Confidential customer data shall be protected in accordance with all contracts and commitments. Customer data shall not be used for testing purposes without the explicit permission of the data owner and the CTO.

## Acquisition of third-party systems and software

The acquisition of third-party systems and software shall be done in accordance with the requirements of the Tuist GmbH [Third-Party Management Policy](/security/access-and-risk-management/third-party-risk-management-policy).

## Developer training

Software developers shall be provided with secure development training appropriate to their role at least annually. Training content shall be determined by management but shall address the prevention of common web application attacks and vulnerabilities. The following threats and vulnerabilities should be addressed as appropriate:

- Prevention of authorization bypass attacks
- Prevention of the use of insecure session IDs
- Prevention of Injection attacks
- Prevention of cross-site scripting attacks
- Prevention of cross-site request forgery attacks
- Prevention of the use of vulnerable libraries

## Exceptions

Requests for an exception to this Policy must be submitted to the IT Manager for approval.

## Violations & enforcement

Any known violations of this policy should be reported to the IT Manager. Violations of this policy can result in immediate withdrawal or suspension of system and network privileges and/or disciplinary action in accordance with company procedures up to and including termination of employment.

## Version history

| Version | Date | Description | Author | Approver |
| --- | --- | --- | --- | --- |
| 3.1 | Nov 19, 2026 | Application errors are sent to Tuist's self-hosted Atlas and Pulse error ingest. | Pedro Piñera Buendía | Pending approval |
| 3.0 | Nov 16, 2026 | Documented that engineers may merge directly to main; the same deterministic checks run in the controlled development environment and again in CI; plus agent review, compensating deployment, rollback, and monitoring controls. Changes to main are traceable through git history and CI results. Failed CI checks on main are investigated and remediated. Peer review is not a required control | Pedro Piñera Buendía | Pending approval |
| 2.0 | Dec 11, 2025 | Version 2.0 | Pedro Piñera Buendía | Pedro Piñera Buendía |
| 1.0 | Oct 14, 2024 | Version 1.0 | Pedro Piñera Buendía | Pedro Piñera Buendía |
