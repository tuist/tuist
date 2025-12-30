---
{
  "title": "Access control policy",
  "titleTemplate": ":title | Access and risk management | Security | Tuist Handbook",
  "description": "To limit access to information and information processing systems, networks, and facilities to authorized parties in accordance with business objectives."
}
---
# Access control policy

- **Policy owner:** Pedro Piñera Buendía
- **Effective Date:** Oct 16, 2024

## Purpose

To limit access to information and information processing systems, networks, and facilities to authorized parties in
accordance with business objectives.

## Scope

All Tuist GmbH information systems that process, store, or transmit confidential data as defined in the Tuist GmbH Data
Management Policy. This policy applies to all employees of Tuist GmbH and to all external parties with access to Tuist
GmbH networks and system resources.

## General requirements

Access to information computing resources is limited to personnel with a business requirement for such access. Access
rights shall be granted or revoked in accordance with this Access Control Policy.

## Business requirements of Access Control Policy

Tuist GmbH shall determine the type and level of access granted to individual users based on the "principle of least
privilege." This principle states that users are only granted the level of access absolutely required to perform their job
functions, and is dictated by Tuist GmbH's business and security requirements. Permissions and access rights not
expressly granted shall be, by default, prohibited.

Tuist GmbH's primary method of assigning and maintaining consistent access controls and access rights shall be through
the implementation of Role-Based Access Control (RBAC). Wherever feasible, rights and restrictions shall be allocated to
groups. Individual user accounts may be granted additional permissions as needed with approval from the system owner or
authorized party.

All privileged access to production infrastructure shall use Multi-Factor Authentication (MFA).

## Access to networks and network services

The following security standards shall govern access to Tuist GmbH networks and network services:

- Technical access to Tuist GmbH networks must be formally documented including the standard role or approver,
grantor, and date
- Only authorized Tuist GmbH employees and third-parties working off a signed contract or statement of work, with a business need, shall be granted access to the Tuist GmbH production networks and resources
- Tuist GmbH guests may be granted access to guest networks after registering with office staff without a documented request
- Remote connections to production systems and networks must be encrypted

## Customer access management

When configuring cross-account access using AWS IAM roles, you must use a value you generate for the external ID,
instead of one provided by the customer, to ensure the integrity of the cross account role configuration. A partner-generated
external ID ensures that malicious parties cannot impersonate a customer's configuration and enforces uniqueness and
format consistency across all customers.

The external IDs used must be unique across all customers. Re-using external IDs for different customers does not solve
the confused deputy problem and runs the risk of customer A being able to view data of customer B by using the role ARN
of customer B along with the external ID of customer B.

Customers must not be able to set or influence external IDs. When the external ID is editable, it is possible for one
customer to impersonate the configuration of another.

## User access management

Tuist GmbH requires that all personnel have a unique user identifier for system access, and that user credentials and
passwords are not shared between multiple personnel. Users with multiple levels of access (e.g. administrators) should be
given separate accounts for normal system use and for administrative functions wherever feasible. Root, service, and
administrator accounts may use a password management system to share passwords for business continuity purposes
only. Administrators shall only use shared administrative accounts as needed. If a password is compromised or suspected
of compromise the incident should be escalated to the information security team immediately and the password must be
changed.

## User registration and deregistration

Only authorized administrators shall be permitted to create new user IDs, and may only do so upon receipt of a
documented request from authorized parties. User provisioning requests must include approval from data owners or Tuist
GmbH management authorized to grant system access. Prior to account creation, administrators should verify that the
account does not violate any Tuist GmbH security or system access control policies such as segregation of duties, fraud
prevention measures, or access rights restrictions.

User IDs shall be promptly disabled or removed when users leave the organization or contract work ends in accordance
with SLAs. User IDs shall not be re-used.

## User access provisioning

- New employees and/or contractors are not to be granted access to any Tuist GmbH production systems until after they have completed all HR on-boarding tasks, which may include but is not limited to signed employment agreement, intellectual property agreement, and acknowledgement of Tuist GmbH's information security policy
- Access should be restricted to only what is necessary to perform job duties
- No access may be granted earlier than official employee start date
- Access requests and rights modifications shall be documented in an access request ticket or email. No permissions shall be granted without approval from the system or data owner or management
- Records of all permission and privilege changes shall be maintained for no less than one year

## Management of privileged access

Tuist GmbH shall ensure that the allocation and use of privileged access rights are restricted and managed judiciously. The
objective is to ensure that only authorized users, software components, and services are granted privileged access rights.
Tuist GmbH will ensure that access and privileges conform to the following standard:

- Identify and Validate Users: Identify users who require privileged access for each system and process.
- Allocate Privileged Rights: Provision access rights basing allocations on specific needs and competencies, and adhering strictly to the access control policy.
- Maintain Authorization Protocols: maintain records of all privileged access allocations.
- Enforce Strong Authentication: Require MFA for all privileged access.
- Prevent Generic Admin ID Usage: prevent the usage of generic administrative user IDs
- Ensure Logging and Auditing: Log all privileged logins and activity

## User access reviews

Administrators shall perform access rights reviews of user, administrator, and service accounts on an annually basis to verify
that user access is limited to systems that are required for their job function. Access reviews shall be documented.

Access reviews may include group membership as well as evaluations of any specific or exception-based permission.
Access rights shall also be reviewed as part of any job role change, including promotion, demotion, or transfer within the
company.

## Removal & adjustment of access rights

The access rights of all users shall be promptly removed upon termination of their employment or contract, or when rights
are no longer needed due to a change in job function or role. The maximum allowable time period for access termination is
24 business hours.

## Access provisioning, deprovisioning, and change procedure

The Access Management Procedure for Tuist GmbH systems can be found in Appendix A to this policy.

## Segregation of duties

Conflicting duties and areas of responsibility shall be segregated to reduce opportunities for unauthorized or unintentional
modification or misuse of Tuist GmbH assets. When provisioning access, care should be taken that no single person can
access, modify or use assets without authorization or detection. The initiation of an event should be separated from its
authorization. The possibility of collusion should be considered when determining access levels for individuals and groups.

## User responsibility for the management of secret authentication information

Control and management of individual user passwords is the responsibility of all Tuist GmbH personnel and third-party
users. Users shall protect secret authentication information in accordance with the Information Security Policy.

## Password policy

- Where feasible, passwords for confidential systems shall be configured to have at least eight (8) or more characters, one upper case, one lower case, one special character, one number
- Systems shall be configured to remember and prohibit reuse of passwords for last 16 passwords used
- Passwords shall be set to lock out after 6 failed attempts
- For manual password resets, a user's identity must be verified prior to changing passwords
- Do not use secret questions (place of birth, etc.) as a sole password reset requirement

## Information access restriction

Applications must restrict access to program functions and information to authorized users and support personnel in
accordance with the defined access control policy. The level and type of restrictions applied by each application should be
based on the individual application requirements, as identified by the data owner. The application-specific access control
policy must also conform to Tuist GmbH policies regarding access controls and data management.

Prior to implementation, evaluation criteria are to be applied to application software to determine the necessary access
controls and data policies. Assessment criteria include, but are not limited to:

- Sensitivity and classification of data.
- Risk to the organization of unauthorized access or disclosure of data
- The ability to, and granularity of, control(s) on user access rights to the application and data stored within the application
- Restrictions on data outputs, including filtering sensitive information, controlling output, and restricting information access to authorized personnel
- Controls over access rights between the evaluated application and other applications and systems
- Programmatic restrictions on user access to application functions and privileged instructions
- Logging and auditing functionality for system functions and information access
- Data retention and aging features

All unnecessary default accounts must be removed or disabled before making a system available on the network.
Specifically, vendor default passwords and credentials must be changed on all Tuist GmbH systems, devices, and
infrastructure prior to deployment. This applies to ALL default passwords, including but not limited to those used by
operating systems, software that provides security services, application and system accounts, and Simple Network
Management Protocol (SNMP) community strings where feasible.

## Secure log-on procedures

Secure log-on controls shall be designed and selected in accordance with the sensitivity of data and the risk of
unauthorized access based on the totality of the security and access control architecture.

## Password management system

Systems for managing passwords should be interactive and assist Tuist GmbH personnel in maintaining password
standards by enforcing password strength criteria including minimum length, and password complexity where feasible.

All storage and transmission of passwords is to be protected using appropriate cryptographic protections, either through
hashing or encryption.

## Use of privileged utility programs

Use of utility programs, system files, or other software that might be capable of overriding system and application controls
or altering system configurations must be restricted to the minimum personnel required. Systems are to maintain logs of all
use of system utilities or alteration of system configurations. Extraneous system utilities or other privileged programs are to
be removed or disabled as part of the system build and configuration process.

Management approval is required prior to the installation or use of any ad hoc or third-party system utilities.

## Access to program source code

Access to program source code and associated items, including designs, specifications, verification plans, and validation
plans shall be strictly controlled in order to prevent the introduction of unauthorized functionality into software, avoid
unintentional changes, and protect Tuist GmbH intellectual property.

All access to source code shall be based on business need and must be logged for review and audit.

## Exceptions

Requests for an exception to this Policy must be submitted to the IT Manager for approval.

## Violations & enforcement

Any known violations of this policy should be reported to the IT Manager. Violations of this policy can result in immediate
withdrawal or suspension of system and network privileges and/or disciplinary action in accordance with company
procedures up to and including termination of employment.

## Version history

The version history of this document can be found in Tuist's [handbook](https://github.com/tuist/handbook) repository.

## APPENDIX A — Access management procedure

### 1. Access Request Process

#### 1.1 Standard Access Provisioning
- **Onboarding Completion:** HR sends an email to the IT Service Desk upon completion of the employee onboarding process, generating service tickets for access.
- **Standard Provisioning:** IT provisions access to company-wide systems based on the employee's role according to the Access Matrix (Appendix B).

#### 1.2 GitHub-Based Access Request Process
- **Request Creation:** For additional access beyond standard role-based access, employees must create an issue in the [access](https://github.com/tuist/access) repository using the provided template.
- **Required Information:** The request must include:
  - Requestor information (name, role, department, manager)
  - Specific systems or resources requested
  - Type of access needed (read, write, admin, etc.)
  - Business justification
  - Duration of access (permanent or temporary with end date)
  - Additional justification for privileged access, if applicable

#### 1.3 Review and Approval
- **Manager Approval:** The requestor's manager must review and approve the request by commenting on the GitHub issue.
- **System Owner Approval:** For sensitive systems, the system owner must also approve the request.
- **Documentation:** All approvals must be documented directly in the GitHub issue.

#### 1.4 Implementation
- **Provisioning:** Upon approval, IT will provision the requested access and document the implementation details in the GitHub issue.
- **Notification:** The requestor will be notified via a comment in the GitHub issue when access has been granted.
- **Issue Closure:** The GitHub issue will be closed only after access has been successfully granted and verified.

### 2. Access Review and Revocation

#### 2.1 Periodic Reviews
- **Regular Audits:** IT will conduct periodic reviews of access rights by auditing the GitHub issues repository.
- **Documentation:** Results of access reviews will be documented in separate GitHub issues tagged with "access-review".

#### 2.2 Role Changes and Departures
- **Role Change Process:** When an employee changes roles, a new GitHub issue must be created to document required access changes.
- **Departure Process:** When an employee leaves, HR will create a GitHub issue to initiate the access revocation process.
- **Timeframe:** All access revocation must be completed within 24 business hours of an employee's departure.

### 3. Audit Trail
- **Issue History:** All GitHub issues related to access requests will be maintained as a permanent record.
- **Retention:** Access request records will be retained for a minimum of one year.
- **Compliance Reporting:** The GitHub repository will serve as the primary source for access management during compliance audits.

## APPENDIX B — Access matrix

| Role | Email | Google Workspace | Slack | GitHub | CRM | Infrastructure | Supabase | Cloudflare |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Founder | x | x | x | x | x |x | x | x |
| Engineer | x | x | x | x | | x | | |
| Product designer | x | x | x | x | | | | |