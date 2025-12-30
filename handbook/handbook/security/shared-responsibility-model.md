---
{
  "title": "Shared responsibility model",
  "titleTemplate": ":title | Security | Tuist Handbook",
  "description": null
}
---
# Shared responsibility model

At Tuist, we rely on trusted infrastructure providers, such as [Render](https://render.com), [Tigris](https://tigrisdata.com) and [Supabase](https://supabase.com), to manage key aspects of our infrastructure security. These partnerships enable us to deliver reliable and secure services while focusing on application and data-level security.

This document outlines the shared responsibility model between Tuist and its infrastructure providers, detailing the security areas managed by each party.

## Render: Security Responsibilities

[Render](https://render.com) ensures the security of its platform through the following mechanisms:

### **Render's Responsibilities:**
1. **Data Center Security**
   - Physical access control, environmental safeguards, and compliance with industry standards (e.g., SOC 2, ISO 27001).
2. **Network Security**
   - Firewall protection, DDoS mitigation, and secure routing of traffic across their global network.
3. **Platform Updates and Patch Management**
   - Continuous monitoring and patching of vulnerabilities in the Render platform and underlying infrastructure.
4. **Application Security (AppSec)**
   - Secure isolation of customer workloads to prevent unauthorized access between applications running on their platform.

For more details, refer to Render's [Shared Responsibility Model](https://render.com/docs/shared-responsibility-model) and [Security and Trust](https://render.com/trust) documentation.

### **Tuist's Responsibilities on Render:**
- Securing the Tuist application code and dependencies.
- Managing access controls and encryption for data at rest and in transit.
- Implementing monitoring and incident response measures for application-layer threats.

## Tigris: Security Responsibilities

[Tigris](https://tigrisdata.com) provides a secure data platform that adheres to strict privacy and security standards.

### **Tigris's Responsibilities:**
1. **Infrastructure Security**
   - Secure management of the underlying infrastructure, including server and storage security.
2. **Data Encryption**
   - Encryption of data in transit (TLS) and at rest using robust cryptographic protocols.
3. **Access Control**
   - Ensuring role-based access control (RBAC) and secure API integrations.

For additional details, review Tigris’s [Privacy Policy](https://www.tigrisdata.com/docs/legal/privacy-policy/#6-security).

### **Tuist's Responsibilities on Tigris:**
- Implementing proper database access controls.
- Encrypting sensitive data before storing it in Tigris.
- Regularly auditing and monitoring database usage and queries for anomalies.

## Supabase: Security Responsibilities

[Supabase](https://supabase.com) manages and scales our Postgres database.

### **Supabase's Responsibilities:**

1. **Data Security**
   - Encryption of data at rest and in transit.
   - Regular security audits and compliance with standards such as GDPR and CCPA.
2. **Authentication and Authorization**
   - Secure handling of authentication flows and token-based authorization mechanisms.
3. **Platform Monitoring**
   - Proactive monitoring for vulnerabilities and automated updates to ensure platform reliability.

For more details, refer to Supabase’s [Security Documentation](https://supabase.com/security).

### **Tuist's Responsibilities on Supabase:**
- Implementing secure configurations for authentication and access control.
- Protecting user data by applying proper encryption where necessary.
- Monitoring usage patterns to detect and respond to suspicious activity.


## Shared Responsibility Benefits

This shared responsibility model allows Tuist to:
- Leverage the expertise of infrastructure providers for foundational security.
- Focus on securing its application logic, user data, and business operations.
- Continuously improve security practices by collaborating with trusted partners.

By maintaining clear boundaries of responsibility, we ensure the highest security standards for our services while effectively managing risks.

---

If you have questions about this model, please reach out to the security team at [contact@tuist.dev](mailto:contact@tuist.dev).
