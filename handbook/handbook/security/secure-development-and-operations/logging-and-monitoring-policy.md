---
{
  "title": "Logging and monitoring policy",
  "titleTemplate": ":title | Secure development and operations | Security | Tuist Handbook",
  "description": "This policy defines how Tuist GmbH logs user and system activity, what level of detail those logs carry, how logs are reviewed, and how log anomalies are responded to."
}
---
# Logging and monitoring policy

- **Policy owner:** Pedro Piñera Buendía
- **Effective date:** August 14, 2026

## Purpose

To ensure that activity across Tuist GmbH systems and applications is logged at a level of detail that supports security investigations, business operations, and governance processes, that those logs are reviewed on a cadence proportionate to risk and information classification, and that anomalies found in logs are responded to in a manner appropriate to the risk they represent.

## Scope

This policy applies to all Tuist GmbH production systems, internal systems, and third-party services that store, process, or transmit Confidential or Restricted data as defined in the Data Management Policy. It applies to all employees, contractors, and third parties with access to those systems.

Because Tuist GmbH runs on managed cloud infrastructure, logging responsibility is shared with our providers as described in the [Shared Responsibility Model](/security/shared-responsibility-model). Providers are responsible for logging at the physical, hypervisor, and platform layers. Tuist GmbH is responsible for logging at the application, data, and identity layers.

## 1. Logging requirements

### 1.1 Activity levels that must be logged

Systems and applications shall log user activity at three levels:

**Administrative activity.** Actions that change the security posture, configuration, or access model of a system:

- Authentication events, including successful logins, failed login attempts, and multi-factor authentication challenges
- Creation, modification, disabling, and deletion of user accounts and service accounts
- Grants, changes, and revocations of roles, permissions, and privileged access
- Elevation to privileged access, including the justification recorded at the time of elevation
- Changes to infrastructure configuration, secrets, network rules, and deployment pipelines
- Changes to logging and monitoring configuration itself

**Application activity.** Actions users and services take inside Tuist GmbH products and internal tools:

- Access to and modification of customer data and organization settings
- Creation, rotation, and revocation of tokens, keys, and other credentials
- Administrative operations performed by Tuist GmbH personnel on customer accounts, including impersonation sessions
- Export or bulk retrieval of data
- Errors and exceptions that indicate a security-relevant failure

**Transaction activity.** Individual operations against data and service endpoints:

- API requests, including method, endpoint, response status, and originating account
- Database schema migrations and administrative queries executed outside the application
- Object storage read and write operations against buckets holding customer data
- Billing and subscription state changes

### 1.2 Minimum log content

Each log record shall, where technically feasible, contain:

- Timestamp in UTC
- Identity of the actor: user ID, service account, or system component
- Source of the request, such as IP address or workload identity
- The action performed and the resource acted upon
- The outcome of the action, including success or failure and any relevant error code
- A correlation identifier that allows the record to be joined to related records across services

Logs shall not contain secrets, credentials, full authentication tokens, or plaintext personal data beyond what is required to identify the actor and the affected resource. Where sensitive values must be recorded for traceability, they shall be redacted, hashed, or truncated.

### 1.3 Level of detail and governance alignment

The level of logging detail shall be set so that it supports the business and governance processes that depend on it, specifically:

- Security incident detection and investigation, as required by the [Incident Response Management](/security/human-and-incident-management/incident-response-management) policy
- Access reviews and privileged access attestation, as required by the [Access control policy](/security/access-and-risk-management/access-control-policy)
- Customer and regulatory data requests, including data subject access and deletion requests
- Service reliability analysis and capacity planning
- External audit and certification evidence

Where a governance process requires evidence that current logging cannot produce, the logging configuration shall be extended rather than the process weakened.

### 1.4 Retention and integrity

- Security-relevant logs shall be retained for a minimum of twelve (12) months, with at least ninety (90) days immediately searchable.
- Logs shall be shipped off the originating host to centralized storage so that compromise of a single system does not destroy its own audit trail.
- Log storage shall be append-only or otherwise protected against modification and deletion by the accounts whose activity it records.
- Access to logs shall follow the principle of least privilege and shall itself be logged.
- Logs containing Confidential or Restricted data shall be encrypted in transit and at rest in accordance with the [Cryptography policy](/security/business-continuity-and-data-protection/cryptography-policy).

## 2. Log review

Logs shall be reviewed periodically. Review frequency is driven by the risk of the system and the classification of the information it handles.

| Log source | Information classification | Review frequency |
| --- | --- | --- |
| Production authentication and privileged access logs | Confidential | Monthly |
| Production application and customer data access logs | Confidential | Monthly |
| Infrastructure and deployment change logs | Confidential | Quarterly |
| Third-party service administrative logs (identity provider, source control, cloud providers) | Confidential | Quarterly |
| Internal tooling and collaboration systems | Restricted | Quarterly |
| Public-facing marketing and documentation systems | Public | Annually |

Reviews shall be performed by a person other than the primary operator of the system under review wherever staffing allows. Where the size of the team makes full separation impractical, the review shall be documented and countersigned by a second reviewer.

Each review shall be recorded with the reviewer, the date, the period covered, the sources examined, and the findings. Records of reviews shall be retained for at least one year and serve as evidence of compliance.

Continuous automated monitoring supplements but does not replace periodic review. Alerts that fire between reviews shall be triaged when they fire.

## 3. Anomaly detection and response

### 3.1 Detection

Automated alerting shall be configured for at least the following conditions:

- Repeated authentication failures against a single account, or authentication failures spread across many accounts
- Successful authentication from an unexpected location, network, or device for privileged accounts
- Privileged access granted or used outside an approved request
- Access to customer data that does not match an expected support or operational workflow
- Unusual volumes of data export or object storage reads
- Gaps in log ingestion, which are treated as a potential loss of visibility rather than as an absence of events
- Changes to logging configuration, retention, or access controls

### 3.2 Risk-proportionate response

Anomalies shall be responded to in a manner appropriate to the risk they represent:

| Severity | Definition | Response |
| --- | --- | --- |
| High | Credible indication of unauthorized access to Confidential data, or compromise of a privileged account or production system | Triage immediately on detection. Escalate to the [Incident Response Management](/security/human-and-incident-management/incident-response-management) process. Contain first, investigate second. |
| Medium | Suspicious activity that may indicate misuse or a control failure but with no confirmed exposure of Confidential data | Triage within one (1) business day. Investigate, determine root cause, and record the outcome. Escalate to incident response if exposure is confirmed. |
| Low | Anomalies with a plausible benign explanation, such as a known operational change or a misconfigured client | Triage within five (5) business days. Record the disposition and, where the anomaly is expected to recur, tune the alert or the underlying control. |

Every anomaly shall be closed with a documented disposition, even when the disposition is that no action was needed. Recurring low-severity anomalies that are dismissed repeatedly shall trigger a review of the alert rule so that alert fatigue does not mask real events.

### 3.3 Feedback into controls

Findings from log reviews and anomaly investigations shall feed the [Risk management policy](/security/access-and-risk-management/risk-management-policy) risk register and, where relevant, result in changes to access controls, alerting thresholds, or logging coverage.

## 4. Roles and responsibilities

**Security lead.** Owns this policy, approves logging and alerting configuration changes, ensures periodic reviews happen and are documented, and makes the severity call on escalated anomalies.

**Engineering team.** Implements and maintains logging in applications and infrastructure, ensures new services log to the central pipeline before reaching production, performs first-line triage of alerts, and documents dispositions.

**All personnel.** Report suspected security events they observe, whether or not an automated alert fired.

## 5. Evidence of compliance

To demonstrate compliance, Tuist GmbH shall maintain:

1. Documentation of logging configuration per system, including which activity levels are captured
2. Records of periodic log reviews, including reviewer, date, scope, and findings
3. Alerting rule definitions and their change history
4. Records of anomaly investigations and their dispositions
5. Evidence of log retention settings and access controls on log storage

## Exceptions

Systems that cannot meet the requirements of this policy shall have the limitation documented, a compensating control identified, and an exception approved by the security lead. Exceptions shall be reviewed at least annually.

## Violations and enforcement

Any known violations of this policy should be reported to the security lead. Violations can result in immediate withdrawal or suspension of system and network privileges and disciplinary action in accordance with company procedures up to and including termination of employment.

## Review

This policy shall be reviewed annually or when significant changes occur to Tuist GmbH's technology infrastructure.

## Version history

The version history of this document can be found in Tuist's [handbook](https://github.com/tuist/handbook) repository.
