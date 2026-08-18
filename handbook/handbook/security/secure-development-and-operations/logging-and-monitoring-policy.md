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

This policy applies to all Tuist GmbH production systems, internal systems, and third-party services that store, process, or transmit Confidential or Restricted data as defined in the [Data Management Policy](/pdfs/security/business-continuity-and-data-protection/data-management-policy-bsi.pdf). It applies to all employees, contractors, and third parties with access to those systems.

Logging responsibility is shared with infrastructure providers, but not along the line a fully managed platform would draw. Tuist GmbH operates its own Kubernetes clusters and its own database on rented hardware, and buys managed services for object storage, edge delivery, and log storage. Providers are therefore responsible for logging at the physical and hardware layers and within the managed services they themselves run. Everything above that, including the cluster and platform layer as well as the application, data, and identity layers, is Tuist GmbH's responsibility. The [Shared Responsibility Model](/security/shared-responsibility-model) records the division per provider.

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

- Security-relevant logs shall be retained for a minimum of thirty (30) days, fully searchable for that period. Records of the log reviews described in section 2 are retained for at least one year, so the evidence of what was examined and what was found outlives the raw logs it was drawn from.
- Because the retention window is thirty days, a review that is not performed on schedule cannot be performed retrospectively. Reviews scheduled monthly shall be completed within the first week of the period they cover.
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

Automated alerting complements periodic review rather than replacing it. It is configured for conditions where a signal arriving in minutes is materially better than one found at the next review, and where the detection can be stated precisely enough to be acted on rather than dismissed:

- Repeated authentication failures against a single account, or spread across many accounts
- Privileged access exercised outside an approved elevation, detected by joining infrastructure access records against the approved elevation window covering them
- Operator access to a customer's data without a corresponding signed access grant
- Loss of log ingestion from any source, treated as a loss of visibility rather than as an absence of events

The second and third conditions are stated as reconciliations against an authoritative record rather than as behavioural anomalies. An alert that fires on a deviation from a learned baseline is only as good as the baseline; one that fires when an action has no matching authorization is either true or a bug in the authorization path, and both are worth knowing.

Changes to logging configuration held in version control are covered by change review rather than by alerting. Where a provider holds configuration outside version control, the change record available from that provider is what applies.

This list is deliberately short. A condition is added when it can be expressed precisely and someone will act on it, not to broaden coverage on paper.

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

Systems that cannot meet the requirements of this policy shall have the limitation documented, a compensating control identified, and an exception approved by the IT Manager. Exceptions shall be reviewed at least annually.

## Violations and enforcement

Any known violations of this policy should be reported to the IT Manager. Violations can result in immediate withdrawal or suspension of system and network privileges and disciplinary action in accordance with company procedures up to and including termination of employment.

## Review

This policy shall be reviewed annually or when significant changes occur to Tuist GmbH's technology infrastructure.

## Appendix A: Logging coverage

This appendix records what is captured at each activity level and where it is
held. It is the documentation of logging configuration required by section 5,
and it is maintained alongside the systems it describes.

Every request handled by the Tuist server emits a structured completion record
carrying the request identifier, the request kind, the acting account, the
selected account and project where one is in scope, the method, the route, the
response status, and the duration. Where a request runs under an operator
access grant, the grant identifier and subject are attached to that same
record. This single record is what provides actor, action, resource, outcome,
and correlation identifier for most of what follows, which is why the table
below points at it repeatedly rather than describing a separate log per event.

### Administrative activity

| Event | Where it is captured |
| --- | --- |
| Authentication attempts and their outcome | Server request records, identified by route and response status, with the acting account attached |
| Workforce authentication and multi-factor challenges | The identity provider's own audit log. The Tuist application does not authenticate workforce identity directly |
| Account creation, modification, disablement, and deletion | Server request records; automated retirement of dormant accounts additionally emits a record naming every account actioned |
| Role, permission, and organization membership changes | Server request records |
| Privileged infrastructure elevation, with justification | Three independent records: the approval thread, the operations database, and the per-call access log of the cluster gateway |
| Operator access to a customer account | The signed grant, joinable to every request made under it by the grant identifier |
| Infrastructure, network, and deployment configuration changes | Version control history and the deployment pipeline's own run records |
| Changes to logging configuration held in version control | Version control history |

### Application activity

| Event | Where it is captured |
| --- | --- |
| Access to and modification of customer data and organization settings | Server request records, attributed to the selected account and project |
| Creation, rotation, and revocation of tokens and other credentials | Server request records |
| Administrative operations performed on customer accounts by Tuist personnel | Server request records carrying the operator grant identifier |
| Export or bulk retrieval of data | Server request records |
| Errors and exceptions indicating a security-relevant failure | Application error reporting, and the server's own error records |

### Transaction activity

| Event | Where it is captured |
| --- | --- |
| Interface requests, with method, route, status, and originating account | Server request records |
| Database schema migrations and administrative tasks | The output of the job that runs them, collected with all other workload output |
| Object storage deletions, including those performed by scheduled retention and cleanup work | A dedicated record naming the operation, the account, the prefix or object count, and the outcome |
| Billing and subscription state changes | The payment provider's event log, and the server request and webhook records that accompany each change |

### Where records are held

Workload output is shipped off the originating host to the central telemetry
platform, so no system holds the only copy of its own audit trail. Records held
by third parties, including the identity provider and the payment provider,
remain in those systems and are retrieved from them when a review or an
investigation calls for it.

### Maintenance

This appendix is reviewed whenever a new system is introduced, whenever an
existing system changes what it records, and at the annual review of this
policy. Where a governance process needs evidence that current coverage cannot
produce, section 1.3 applies: the coverage is extended rather than the process
weakened.

## Version history

The version history of this document can be found in Tuist's [handbook](https://github.com/tuist/handbook) repository.
