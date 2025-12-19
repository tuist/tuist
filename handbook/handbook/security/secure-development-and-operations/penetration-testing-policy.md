---
{
  "title": "Penetration testing policy",
  "titleTemplate": ":title | Secure development and operations | Security | Tuist Handbook",
  "description": "Policy establishing the requirements for regular penetration testing of Tuist GmbH systems and applications to identify and remediate security vulnerabilities."
}
---
# Penetration testing policy

- **Policy owner:** Pedro Piñera Buendía
- **Effective Date:** June 19th, 2025

## Purpose

This policy establishes the requirements for regular penetration testing of Tuist GmbH's systems, applications, and infrastructure to identify security vulnerabilities that could potentially be exploited by malicious actors. Penetration testing provides an essential security assessment that goes beyond automated vulnerability scanning by simulating real-world attack scenarios to validate the effectiveness of security controls.

## Scope

This policy applies to all systems, applications, and infrastructure owned, operated, or maintained by Tuist GmbH that are business-critical and/or process, store, or transmit Confidential data. It applies to all employees, contractors, and third parties involved in planning, conducting, or responding to penetration testing activities.

This policy operates within Tuist's [shared responsibility model](/security/shared-responsibility-model), recognizing that infrastructure providers (Render, Supabase, Tigris, and Cloudflare) are responsible for penetration testing of their underlying infrastructure layers.

## Policy Statement

Tuist GmbH shall conduct penetration testing **at least annually** on all Internet-exposed services and critical applications. Additional penetration tests shall be performed following significant changes to the application or when required by compliance requirements.

## Penetration Testing Requirements

### 1. Testing Frequency

- **Annual Testing**: Comprehensive penetration testing of all critical systems at least once per year
- **Event-Driven Testing**: Additional testing following:
  - Major infrastructure changes
  - Significant application updates or new feature releases
  - Security incidents or breaches
  - Discovery of critical vulnerabilities in similar systems
- **Compliance-Driven Testing**: As required by customer contracts or regulatory requirements

### 2. Types of Penetration Testing

The following types of penetration testing shall be conducted by Tuist:

- **Web Application Penetration Testing**: Security assessment of Tuist-developed web applications and APIs
- **API Security Testing**: Comprehensive testing of all Tuist API endpoints for authentication, authorization, and data validation vulnerabilities
- **Business Logic Testing**: Assessment of application workflows and business processes for logical flaws
- **Configuration Review**: Assessment of application-level configurations and security settings within Tuist's control
- **Integration Testing**: Security assessment of integrations between Tuist applications and third-party services

### 3. Testing Scope

In accordance with our [shared responsibility model](/security/shared-responsibility-model), Tuist's penetration testing scope focuses on:

**Tuist's Responsibility (must be tested):**
- All Tuist-developed web applications and APIs
- Application-layer security controls and configurations
- Authentication and authorization mechanisms implemented by Tuist
- Custom integrations and API endpoints
- Application-specific data handling and encryption
- Business logic vulnerabilities

**Infrastructure Provider Responsibility (covered by provider testing):**
- Physical data center security (Render, Supabase, Tigris)
- Network infrastructure and DDoS protection (Render, Cloudflare)
- Platform-level vulnerabilities and patches (all providers)
- Database engine security (Supabase, Tigris)
- CDN and edge security (Cloudflare)
- Infrastructure-level access controls

### 4. Testing Methodology

Penetration testing shall follow industry-standard methodologies such as:

- OWASP Testing Guide for web applications
- PTES (Penetration Testing Execution Standard)
- NIST SP 800-115 Technical Guide to Information Security Testing
- Cloud-specific frameworks for cloud infrastructure testing

### 5. Authorized Testing Providers

Penetration testing must be conducted by:

- **External Testing**: Qualified third-party security firms with demonstrated expertise and appropriate certifications (e.g., OSCP, GPEN, CEH)
- **Internal Testing**: Authorized security personnel with appropriate training and certifications (if applicable)
- All testers must sign appropriate confidentiality agreements before testing begins

### 6. Pre-Testing Requirements

Before penetration testing begins:

- Written authorization must be obtained from the CTO
- Testing scope and timeline must be documented
- Rules of engagement must be established, including:
  - Testing windows to minimize business impact
  - Excluded systems or activities
  - Communication protocols
- Team members must be notified of testing activities

### 7. Testing Execution

During penetration testing:

- All testing activities must be logged and documented
- Testing must be conducted according to the agreed rules of engagement
- Any critical vulnerabilities discovered must be immediately reported
- Testing that could cause service disruption must be carefully managed
- Communication channels must remain open between testers and Tuist personnel

### 8. Post-Testing Requirements

After penetration testing is complete:

- A comprehensive report must be provided within 2 weeks, including:
  - Executive summary
  - Detailed findings with severity ratings
  - Evidence of successful exploitation
  - Remediation recommendations
  - Risk ratings and business impact analysis
- A remediation plan must be developed based on findings
- Retesting must be conducted to verify remediation of critical and high findings

### 9. Remediation Requirements

Vulnerabilities discovered during penetration testing shall be remediated according to:

- Critical: Within 7 days
- High: Within 14 days
- Medium: Within 30 days
- Low: Within 90 days

Any deviation from these timelines requires documented risk acceptance by the CTO.

### 10. Documentation and Record Keeping

The following documentation must be maintained:

- Penetration testing scope and authorization documents
- Testing reports and findings
- Remediation plans and evidence
- Retest results
- Risk acceptances for any exceptions
- Certificates of testing completion
- Infrastructure provider security certifications and attestations (SOC 2, ISO 27001, etc.)

All penetration testing documentation shall be retained for a minimum of 3 years.

### 11. Infrastructure Provider Assurance

To ensure comprehensive security coverage:

- Maintain copies of infrastructure provider security certifications (SOC 2, ISO 27001)
- Monitor provider security bulletins
- Review the shared responsibility model annually

## Vendor Management

When engaging third-party penetration testing providers:

- Vendors must provide evidence of appropriate insurance coverage
- Vendors must demonstrate relevant certifications and experience
- Non-disclosure agreements must be executed before sharing any information
- Vendor personnel must be vetted and approved
- Clear communication protocols must be established

## Evidence Collection and Reporting

To satisfy audit and compliance requirements:

1. Maintain penetration testing reports and completion certificates
2. Track remediation progress
3. Document evidence of critical vulnerability fixes

## Roles and Responsibilities

### Chief Technology Officer (CTO)
- Approves penetration testing schedule and budget
- Authorizes testing activities
- Reviews testing reports and approves remediation priorities
- Accepts risk for any deviations from remediation timelines

### Engineering Team
- Coordinates with testing providers
- Implements remediation for identified vulnerabilities
- Documents remediation actions
- Monitors systems during testing

## Exceptions

Any exceptions to this policy must be documented and approved by the CTO. Exceptions shall include:
- Reason for the exception
- Duration of the exception
- Any compensating controls
- Risk acceptance

## Compliance Monitoring

Compliance with this policy shall be monitored through annual review of:
- Penetration testing completion
- Remediation status
- Testing documentation

## Policy Review

This policy shall be reviewed annually or when significant changes occur to Tuist's technology infrastructure or threat landscape.

## Version History

The version history of this document can be found in Tuist's [handbook](https://github.com/tuist/handbook) repository.
