---
title: Service Level Addendum
description: This Service Level Addendum defines the availability, error classes, response and recovery times, and service level credits for the Tuist platform.
last_updated: 2025-08-08
---

## 1. General

1.1. This SLA is entered into between Tuist GmbH ("**Tuist**") and the Customer (as defined in the Agreement), and will be subject to, and governed by, the terms of the Terms of Service - Online (the "**Agreement**").

1.2. In the event of a conflict between this SLA, the Agreement or any Addenda or other schedule to the Agreement (other than the Data Processing Addendum), this Addendum will prevail.

1.3. Unless otherwise defined in this SLA, capitalized terms shall have the meaning assigned to them in the Agreement.

## 2. Definitions

**"Availability"** means the ratio of actual uptime (i.e., uptime less downtime) to the uptime during which the Software as a Service can be used (including in cases of occurrence of Error Classes 3 and 4 but excluding Error Classes 1 and 2). Availability shall be measured in each case on a monthly basis. Coordinated Maintenance Windows are not taken into account when determining availability, i.e., they have no influence on availability. The following formula applies:

> Availability in % = (Operating Hours minus Downtime) / Operating Hours

**"Downtime"** means the periods of time during which the Software as a Service cannot be used or cannot be used completely due to a failure of Error Class 1 or 2. The respective downtime is calculated as the sum of actual response time and actual recovery time. Downtime in the sense of availability does not include downtime due to (i) Maintenance Windows during which access to the Software as a Service is not possible, (ii) unforeseen maintenance work that becomes necessary, if such work was not caused by a breach of Tuist's obligations to provide the Software as a Service (e.g., force majeure, in particular unforeseeable hardware failures, strikes, natural events), (iii) from virus or hacker attacks, insofar as Tuist has taken the agreed protective measures or, in the absence of an agreement, the usual protective measures, (iv) of the Customer's specifications, due to unavailability of the Customer's equipment or due to other interruptions caused by the Customer (e.g., failure of the Customer to cooperate), (v) unavailable or defective third-party services attributable to the Customer (in particular the interfaces (APIs) to connected third-party systems), (vi) the application of urgently needed security patches, and (vii) of errors in Customer applications or due to errors in the Software as a Service triggered by Customer applications or data.

**"Error Classes"** means the categorization of the significance of various errors or faults in the Software as a Service into four Error Classes, in which the errors or faults are classified according to their impact on Customer's business processes.

- **Error Class 1** (critical malfunction): refers to errors that preclude or make it impossible to use the Software, e.g., the Software as a Service cannot be started.
- **Error Class 2** (serious malfunction): refers to errors that significantly impede or severely restrict the use of the software in essential parts, e.g., the complete failure of the communication function of the Software.
- **Error Class 3** (moderate malfunction): refers to errors that restrict the functionality of the Software only in partial areas so that use is still possible, e.g., real-time functions do not ensure real-time transmission.
- **Error Class 4** (minimal malfunction): refers to errors that do not fundamentally restrict use but rather involve losses in convenience, e.g., speed impairments or display errors.

**"Maintenance Window"** means the period of time during which Software as a Service may be taken out of service for maintenance or updates.

**"Operating Hours"** means the scheduled times (target time) during which the Software as a Service ordered by Customer can be used. Regular business hours (as specified herein) and Maintenance Windows are within the Operating Hours.

**"Response Time"** means the effective period of time between the detection of a malfunction/error report within the scope of the self-test and the start of the work of the body and/or person commissioned by Tuist to rectify the error, or the receipt of a fault/error report from the Customer by Tuist on the one hand and the first contact between the office and/or person charged with troubleshooting by Tuist and the Customer on the other hand.

**"Recovery Time"** shall mean the start of the error elimination immediately following the Response Time. The recovery time ends with the successful elimination of the error or, in individual cases, with an objectively reasonable workaround solution.

**"Service Level Credits"** means a credit, determined by Tuist, to be applied against the agreed compensation if Tuist fails to perform the Software as a Service as agreed in this SLA.

**"Times"** refers in each case to the time zone of Berlin.

**"Updates"** means any modification, enhancement, or improvement made to the Software that is intended to maintain, improve, or expand its functionality, performance, or security. Updates may include bug fixes, patches, minor feature additions, or performance optimizations. Updates are typically provided to ensure the Software remains current with technological advancements and continues to meet the agreed-upon service levels.

## 3. Ticket System

For each request of Customer, Tuist shall assign a processing number ("**Ticket**"). At its own discretion, Tuist will implement an electronic ticket system for this purpose, which will enable traceability of the status of the processing of the Tickets.

## 4. Business Hours

Regular business hours are 8:00 a.m. to 5:00 p.m. from Monday to Friday, except for public holidays in Berlin, Germany.

## 5. Availability

The Software as a Service is provided with an Availability of 95% per month.

## 6. Error Reporting

Customer shall report to Tuist any impairments of Availability, errors or other disruptions of which Customer becomes aware. Tuist will endeavor to eliminate the disruptions without undue delay.

## 7. Maintenance Windows

Scheduled maintenance window for maintenance work and data backups of the Software as a Service is daily in the time from 0:00 to 2:00. During this time, operation of the Software as a Service may not be possible. Additional Maintenance Windows will be communicated by Tuist to Customer regarding the intended date (date, start time and scheduled duration) in a timely manner and in any case at least three (3) days in advance.

## 8. Error Classification and Response Times

The classification of the errors shall be made by Tuist in its reasonable discretion with due regard to the impact that the relevant error has on Customer's business operations and the interests of Tuist. Upon becoming aware of an error through Tuist's routine self-inspection or notification by the Customer, Tuist will begin problem analysis and respond to Customer, and if already available, provide information about possible solutions, as follows:

**Discovery within regular business hours (Error Classes 1 and 2):**

| Error Class | Response Time |
|---|---|
| Error Class 1 | Max. 2 hours from error detection/reporting |
| Error Class 2 | Max. 4 hours from fault detection/notification |

**Discovery between 6 a.m. and 9 p.m. but outside regular business hours (Error Classes 1 and 2):**

| Error Class | Response Time |
|---|---|
| Error Class 1 | Max. 4 hours from error detection/reporting |
| Error Class 2 | Max. 8 hours from error detection/reporting |

**Discovery between 9 p.m. and 6 a.m. (Error Classes 1 and 2):**

| Error Class | Response Time |
|---|---|
| Error Class 1 | Max. 4 hours, starting at 6 a.m. |
| Error Class 2 | Max. 8 hours, starting at 6 a.m. |

**Error Classes 3 and 4:**

| Error Class | Response Time |
|---|---|
| Error Class 3 | Max. 2 hours from start of regular business hours |
| Error Class 4 | Max. 4 hours from start of regular business hours |

## 9. Recovery Times for Software as a Service

The following recovery times are deemed agreed for Software as a Service:

| Error Class | Recovery Time |
|---|---|
| Error Class 1 | 12 hours |
| Error Class 2 | 1 working day |
| Error Class 3 | 20 working days |
| Error Class 4 | With the next update |

## 10. Recovery Times for On-Premise Software

The following recovery times are deemed agreed for On-Premise Software. Recovery in terms of On-Premise Software means the provision of an updated version of the Software:

| Error Class | Recovery Time |
|---|---|
| Error Class 1 | 1 working day |
| Error Class 2 | 3 working days |
| Error Class 3 | 20 working days |
| Error Class 4 | With the next update |

## 11. Error Report Requirements

All error and fault reports from Customer must be adequately described and contain the following information in particular: (i) comprehensible description of the error or fault, (ii) time of the fault or malfunction, (iii) information on the IT system used by Customer, (iv) non-binding proposal for the classification of the fault or malfunction, and (v) designation of a qualified contact person of Customer, including contact possibility.

## 12. Error Reporting Channels

All error and fault reports detected by Customer shall be submitted immediately to Tuist via one of the following means of communication:

- Email: contact@tuist.dev

## 13. Update Frequency

Tuist shall deliver Updates to the Software on a regular basis to ensure optimal functionality, performance, and security. Updates shall be provided at least 12 times per year ("**Update Frequency**"), or as necessary to address critical issues, vulnerabilities, or compliance requirements. The Provider will notify the Customer in advance of any scheduled Updates, including details of the changes and potential impacts on service availability. The Provider will make reasonable efforts to minimize disruption during the implementation of Updates. Emergency Updates may be deployed without prior notice to address urgent security or operational issues.

## 14. Customer Obligations

Customer will create all technical conditions and grant access necessary for the provision of services by Tuist.

## 15. Service Level Credits

To the extent Tuist fails to provide the services under this SLA as agreed, Tuist will provide Service Level Credits to Customer in accordance with the following.

15.1. In order to receive Service Level Credits, Customer must submit a notice of noncompliance to Tuist within 24 hours using the contact options provided in Section 12. Tuist will issue Service Level Credits only if Tuist can verify the notice of noncompliance.

15.2. Service-Level Credits are charged as part of the billing for the following billing period. Service Level Credits cannot be paid out.

15.3. The maximum amount of eligible Service-Level Credits is limited to 25% of each billing period.

15.4. Service-Level Credits granted by Tuist shall be credited against any further claims of the Customer.

15.5. If the Software as a Service fails to meet the agreed Availability, Tuist shall grant Service Level Credits for each 0.1% deviation from the agreed availability for that period in the amount of 0.1% of the agreed remuneration for that period, but in total not more than 20% of the agreed remuneration for that period.

15.6. If Tuist exceeds the agreed upon response time, Tuist will grant Service-Level Credits for each 1 hour(s) overrun equal to 0.1% of the agreed upon compensation for that period, but not to exceed a total of 5% of the agreed upon compensation for that period.

15.7. If Tuist exceeds the agreed upon recovery time, Tuist will grant Service-Level Credits for each 2 hour(s) overrun equal to 0.1% of the agreed upon compensation for that period, but not to exceed a total of 5% of the agreed upon compensation for that period.

*Last updated August 8, 2025*
