---
{
  "title": "Business continuity and disaster recovery plan",
  "titleTemplate": ":title | Business continuity and data protection | Security | Tuist Handbook",
  "description": "The purpose of this business continuity plan is to prepare Tuist GmbH in the event of service outages caused by factors beyond our control (e.g., natural disasters, man-made events), and to restore services to the widest extent possible in a minimum time frame."
}
---
# Business continuity and disaster recovery plan

- **Policy owner:** Pedro Piñera Buendía
- **Policy owner:** Effective Date: Oct 16, 2024

## Purpose

The purpose of this business continuity plan is to prepare Tuist GmbH in the event of service outages caused by factors
beyond our control (e.g., natural disasters, man-made events), and to restore services to the widest extent possible in a
minimum time frame.

## Scope

All Tuist GmbH IT systems that are business critical. This policy applies to all employees of Tuist GmbH and to all relevant
external parties, including but not limited to Tuist GmbH consultants and contractors.

In the event of a loss of availability of a hosting service provider, the CTO will confer with the CTO to determine an
appropriate response strategy.

## General requirements

In the event of a major disruption to production services and a disaster affecting the availability and/or security of the Tuist
GmbH office, senior managers and executive staff shall determine mitigation actions.

A disaster recovery test, including a test of backup restoration processes, shall be performed on an annual basis.

## Alternate work facilities

If the Tuist GmbH office becomes unavailable due to a disaster, all staff shall work remotely from their homes or any safe
location.

## Communications and escalation

Executive staff and senior managers should be notified of any disaster affecting Tuist GmbH facilities or operations.

Communications shall take place over approved channels such as email and [the status page](https://status.tuist.io).

Key communication contacts are maintained in [this list](/security/human-and-incident-management/incident-response-management).

## Roles and responsibilities

| Role                 | Responsibility                                                                                                                                                                                                                                                           |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| IT Manager           | The IT Manager shall lead BC/DR efforts to mitigate losses and recover the corporate network and information systems.                                                                                                                                                    |
| Departmental Heads   | Each department head shall be responsible for communications with their departmental staff and any actions needed to maintain continuity of their business functions. Departmental heads shall communicate regularly with executive staff and the IT Manager.            |
| Managers             | Managers shall be responsible for communicating with their direct reports and providing any needed assistance for staff to continue working from alternative locations.                                                                                                  |
| VP of Global Support | The VP of Global Support, in conjunction with the CEO and CFO shall be responsible for any external and client communications regarding any disaster or business continuity actions that are relevant to customers and third parties.                                    |
| VP of Engineering    | The VP of Engineering, in conjunction with the VP of Global Support, shall be responsible for leading efforts to maintain continuity of Tuist GmbH services to customers during a disaster.                                                                              |
| Chief HR Officer     | The CHRO shall be responsible for internal communications to employees as well as any action needed to maintain physical health and safety of the workforce. The CHRO shall work with the IT Manager to ensure continuity of physical security at the Tuist GmbH office. |

## Continuity of critical services

Procedures for maintaining continuity of critical services in a disaster can be found in Appendix A.

Recovery Time Objectives (RTO) and Recovery Point Objects (RPO) can be found in Appendix B.

Strategy for maintaining continuity of services can be seen in the following table:

## Plan activation

This BC/DR shall be automatically activated in the event of the loss or unavailability of the Tuist GmbH office, or a natural
disaster (i.e., severe weather, regional power outage, earthquake) affecting the larger Berlin, Germany region.

## Version history

The version history of this document can be found in Tuist's [handbook](https://github.com/tuist/handbook) repository.

## Appendix A - Business continuity procedures by scenario

**Business Continuity Scenarios**

### HQ Offline (power and/or network)

- CRM, Telephony, Video Conferencing/Screen Share & Corp Email unaffected
- SUPPORT unaffected
- HQ Staff offline (30-60 minutes)
- Remote Staff unaffected (EU)

#### Procedure:

1. HQ Staff relocate to home offices (30-60 minutes)
2. Verify Telephony, CRM, & Email Connectivity at home offices (10 minutes)
3. Remotely resume normal operations

### Colo Offline (power and/or network)

- CRM, Telephony, Video Conferencing/Screen Share & Corp Email unaffected
- SUPPORT Offline
- Production Database offline (redundant)
- HQ Staff unaffected
- Remote Staff unaffected (EU)

#### Procedure:

1. Notify Customer Base that proactive monitoring is offline
2. Normal operations continue

### Disaster Event at HQ

- CRM, Telephony, Video Conferencing/Screen Share & Corp Email unaffected
- SUPPORT offline
- HQ Staff offline (variable impact)
- Remote Staff unaffected (EU)

#### Procedure:

1. Activate Remote Staff (EU)
2. Notify Customer Base of impaired functions & potential delays
3. Commandeer Field Resources for Critical Response (SE Teams)

### SaaS Tools Down

- CRM, Telephony, Video Conferencing/Screen Share, or Corp Email Affected
- SUPPORT partially affected (no new cases, manual triage required)
- HQ Staff unaffected
- Remote Staff unaffected (EU)

#### Procedure:

##### Telephony Down

1. Notify Customer Base to use Support Portal or Email
2. Support Staff use Mobile Phones and/or Land Lines as needed

##### Email Down (Gmail/Corp Email)

1. Support Staff manually manage 'case' related communications
2. Support Staff use alternate email accounts as needed (Hotmail)

##### CRM Down

1. Notify Customer Base that CRM is down
2. Activate 'Spreadsheet' Case Tracking (Google Sheets)
3. Leverage 'Production' Database for Entitlements, Case History, Configuration data.

##### Video Conferencing/ScreenShare Down (Zoom)

1. Support Staff utilize alternate service as needed

## Appendix B - RTOs/RPOs

| Rank | Asset | Affected Assets | Business Impact | Users | Owners | Recovery Time Objective (RTO) | Recovery Point Objective (RPO) | Comments / Gaps |
| ---- | ------------ | ----------- | ----  | ----- | ----------- | ----------------------------- | ------------------------------ | --------------- |
| 1 | Fly servers | Network | Core services | All | Engineering | 1 hour  |  | The recovery might depend on the vendor. |
| 2 | Tigris Storage | Network | Core services | All | Engineering | 1 hour | | The recovery might depend on the vendor. |
| 3 | Supabase Database | Network | Core services | All | Engineering | 1 hour | | The recovery might depend on the vendor. |
| 4 | GitHub | Network | Inability to deploy critical fixes to our production infrastructure | All | Engineering | 30 min | | The recovery might depend on the vendor. |
| 5 | Slack | Network | Inability to communicate with the team | All | Engineering | 30 min | | The recovery might depend on the vendor. |
| 6 | Google Workspace | Network | Inability to perform administrative tasks | All | Engineering | 30 min | | The recovery might depend on the vendor. |
| 7 | Company laptops | Hardware | Inability to work | All | IT Ops | 1 hour | | The recovery might depend on the vendor. |
| 8 | Corporate office | Site | Inability to work | All | IT Ops | 1 hour | | The recovery might depend on the vendor. |
| 9 | Corporate network | Network | Inability to work | All | IT Ops | 1 hour | | The recovery might depend on the vendor. |
