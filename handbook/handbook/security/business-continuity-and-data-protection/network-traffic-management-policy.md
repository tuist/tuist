---
{
  "title": "Network traffic management policy",
  "titleTemplate": ":title | Business continuity and data protection | Security | Tuist Handbook",
  "description": "This policy establishes procedures for monitoring, controlling, managing, and evaluating network traffic to identify vulnerabilities, anomalies and capacity issues in Tuist GmbH's infrastructure."
}
---
# Network traffic management policy

- **Policy owner:** Pedro Piñera Buendía
- **Policy owner:** Effective Date: December 12, 2024

## Purpose

To establish comprehensive rules and procedures for monitoring, controlling, managing, and periodically evaluating network traffic to identify vulnerabilities, anomalies, and capacity issues to protect Tuist GmbH's applications and services.

## Scope

This policy applies to all network traffic related to Tuist GmbH applications and services, while recognizing the shared responsibility model with our infrastructure provider Render as documented in our [Shared Responsibility Model](/security/shared-responsibility-model).

## Shared Responsibility Model for Network Traffic Management

Tuist GmbH operates its infrastructure on Render, which creates a shared responsibility model for network traffic management:

### Render Responsibilities:
- Physical network infrastructure security
- Network perimeter security including DDoS protection
- Core network monitoring and management
- Underlying network capacity planning
- Network-level intrusion detection and prevention

### Tuist GmbH Responsibilities:
- Application-level traffic monitoring and analysis
- API request monitoring and rate limiting
- Application-generated network traffic patterns
- Identifying and responding to application-level traffic anomalies
- Implementing proper access controls for application endpoints

## Policy Requirements

### 1. Traffic Monitoring and Analysis

- **Regular Monitoring**: Tuist GmbH shall implement and maintain tools to monitor application-level network traffic at least daily.
- **Logging Requirements**: All application-level network traffic shall be logged with timestamps, source/destination information, request types, response codes, and data volumes.
- **Automated Alerts**: Automated monitoring systems shall be configured to alert the operations team when:
  - Unusual traffic patterns are detected
  - Error rates exceed defined thresholds
  - Application response times degrade beyond acceptable levels
  - Traffic volumes approach capacity limits

### 2. Traffic Control and Management

- **Rate Limiting**: All public-facing APIs shall implement appropriate rate limiting to prevent abuse.
- **Access Controls**: Network traffic shall be restricted based on the principle of least privilege.
- **Traffic Prioritization**:
  - Business-critical traffic must be prioritized to ensure smooth operations.
  - Non-essential traffic may be restricted during high-demand periods.
- **Traffic Filtering**: Application-level traffic filtering shall be implemented to prevent known attack patterns.

### 3. Periodic Evaluation and Assessment

- **Regular Reviews**: Tuist GmbH shall conduct formal reviews of network traffic patterns at least quarterly to identify trends, anomalies, and potential security issues.
- **Capacity Planning**: Traffic volume trends shall be analyzed at least quarterly to ensure adequate capacity planning.
- **Vulnerability Scanning**: Application vulnerability scanning shall be performed at least quarterly to identify potential security weaknesses.
- **Annual Assessment**: A comprehensive assessment of network traffic management controls shall be performed annually, including:
  - Effectiveness of monitoring tools
  - Adequacy of alerting thresholds
  - Review of incident response times
  - Analysis of traffic patterns and anomalies
  - Evaluation of capacity planning forecasts

### 4. Anomaly Detection and Response

- **Baseline Establishment**: Normal traffic patterns shall be established and documented as baselines.
- **Deviation Thresholds**: Acceptable deviation thresholds from baselines shall be defined and documented.
- **Incident Response**: Anomalous traffic that exceeds defined thresholds shall trigger the incident response procedure as defined in the [Incident Response Management](/security/human-and-incident-management/incident-response-management) policy.
- **Documentation**: All detected anomalies, their investigations, and resolutions shall be documented.

### 5. Security Controls for Network Traffic

- **Encryption**: All network traffic shall be encrypted in transit using industry-standard protocols.
- **Authentication**: Access to Tuist GmbH services shall require appropriate authentication.
- **Secure API Design**: APIs shall be designed with security best practices to prevent common vulnerabilities.
- **Regular Security Updates**: Security patches for application components shall be applied according to the vulnerability management requirements in the [Secure Development Policy](/security/secure-development-and-operations/secure-development-policy).

### 6. Monitoring Tools and Technologies

Tuist GmbH shall implement and maintain at least the following monitoring tools:
- Application Performance Monitoring (APM) solutions
- API gateway monitoring and analytics
- Log aggregation and analysis tools
- Real-time alerting systems
- Traffic visualization dashboards

### 7. Documentation and Reporting

- **Traffic Reports**: Monthly network traffic summary reports shall be generated and reviewed by IT management.
- **Incident Documentation**: All traffic-related security incidents shall be documented according to the Incident Response Management policy.
- **Trend Analysis**: Quarterly trend analysis reports shall be generated to identify long-term patterns.
- **Annual Assessment Report**: An annual comprehensive assessment of network traffic management shall be documented.

## Implementation and Evidence of Compliance

To demonstrate compliance with this policy, Tuist GmbH shall maintain the following evidence:

1. Screenshots of monitoring dashboards showing active traffic monitoring
2. Logs of detected anomalies and their remediation
3. Quarterly network traffic analysis reports
4. Annual comprehensive network traffic assessment reports
5. Documentation of alerting thresholds and their review history
6. Minutes of capacity planning meetings
7. Evidence of regular security scanning and vulnerability testing
8. Incident response documentation for network-related security events

## Roles and Responsibilities

### IT Manager/Security Lead
- Overall responsibility for implementation of this policy
- Review of network traffic reports and assessments
- Approval of changes to monitoring thresholds and alerting rules

### Development and Operations Teams
- Day-to-day monitoring of application network traffic
- Implementation of technical controls for traffic management
- Initial investigation and response to traffic anomalies
- Implementation of approved capacity improvements

## Compliance

Any breach of this policy may result in disciplinary action up to and including termination of employment in accordance with company procedures. Non-compliance may also result in access restrictions or termination of network privileges.

## Review

This policy shall be reviewed annually or when significant changes occur to Tuist's technology infrastructure.

## Version history

The version history of this document can be found in Tuist's [handbook](https://github.com/tuist/handbook) repository.
