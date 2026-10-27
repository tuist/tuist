---
{
  "title": "Data labelling policy",
  "titleTemplate": ":title | Business continuity and data protection | Security | Tuist Handbook",
  "description": "This policy defines how Tuist GmbH identifies sensitive information and applies the correct label to it according to the company's information classification scheme."
}
---
# Data labelling policy

- **Policy owner:** Pedro Piñera Buendía
- **Effective date:** August 14, 2026

## Purpose

To ensure that sensitive information held by Tuist GmbH is identified and receives the correct label according to the company's information classification scheme, so that everyone handling that information knows which protection and handling requirements apply to it.

The classification scheme itself, and the handling requirements attached to each class, are defined in the [Data Management Policy](/pdfs/security/business-continuity-and-data-protection/data-management-policy-bsi.pdf). This policy covers the process of identifying and labelling: how information gets assigned to a class, how the label is applied and made visible, and how labels are kept correct over time.

## Scope

All information created, received, stored, processed, or transmitted by Tuist GmbH, in any form: documents, source code, repositories, databases, object storage, messages, tickets, dashboards, exports, and physical records. This policy applies to all employees, contractors, and third parties handling Tuist GmbH information.

## Classification scheme

Tuist GmbH uses three classes. The definitions below are summarized from the Data Management Policy, which remains the authoritative source.

| Class | Definition | Typical examples |
| --- | --- | --- |
| **Confidential** | Highly sensitive data requiring the highest level of protection. Access restricted to specific people; onward sharing requires data owner or executive approval. | Customer data, personally identifiable information, financial and banking data, payroll data, strategic plans, authentication credentials, secrets and private keys, unpublished source code, incident reports, risk assessments, vulnerability reports, litigation data |
| **Restricted** | Proprietary information requiring thorough protection. Access restricted on a need-to-know basis. **This is the default for all company information unless stated otherwise.** | Internal policies, legal documents, contracts, meeting notes, internal reports, Slack messages, email |
| **Public** | Information intended for public consumption that can be freely distributed. | Marketing materials, product descriptions, release notes, externally published policies |

## 1. Identifying sensitive information

### 1.1 Default classification

All Tuist GmbH information is **Restricted** by default. Information is only Public once it has been deliberately reviewed and released as such. Information falls into **Confidential** whenever it meets any of the criteria below, regardless of where it is stored.

### 1.2 Identification criteria

Information shall be identified as Confidential when it contains any of the following:

- Data belonging to or describing a customer, including project, build, and usage data
- Personal data of any identified or identifiable person, including employees, candidates, and users, whether or not it is regulated as personal data in a given jurisdiction
- Authentication material: passwords, API tokens, private keys, certificates, session material, signing material
- Financial data: banking details, payroll, compensation, revenue figures not yet published
- Security findings: vulnerability reports, penetration test results, incident reports, risk assessments
- Source code that has not been deliberately published, and infrastructure configuration. Tuist GmbH develops much of its product in the open, and publishing source is a deliberate act of publication, governed by the Publication requirement in section 3, rather than an exception to this rule. Anything not published stays Confidential.
- Information subject to a confidentiality obligation under a contract, NDA, or legal hold

Where a set of information mixes classes, the whole set takes the highest class present. A document containing one paragraph of customer data is Confidential in its entirety. A system takes the highest classification of any data it stores or processes.

### 1.3 Who decides

The person who creates or first receives a piece of information is responsible for classifying it at that moment. The data owner for the relevant system or business area is responsible for resolving ambiguous cases and may reclassify.

Where classification is genuinely unclear, the information shall be treated as Confidential until the data owner decides. Under-classification is treated as a security issue; over-classification is treated as an inconvenience.

## 2. Applying labels

Labels shall be applied at the point where information is created or ingested, not retroactively at the point of sharing.

### 2.1 Documents and written content

- Documents and presentations shall carry the label in the document header, footer, or title block: `Confidential`, `Restricted`, or `Public`.
- Documents in shared drives shall additionally live under a folder whose access controls match the class. Folder-level classification acts as an inherited label for everything inside it.
- Handbook and other externally published pages are implicitly `Public` by virtue of being published, and require no inline label. Nothing Confidential or Restricted may be published to a public surface.

### 2.2 Source code and repositories

- Repository visibility is the label. Private repositories are `Confidential`. Public repositories are `Public`, having been published deliberately.
- Making a repository public, or opening a previously private component, is a publication decision under section 3 and requires data owner approval. The review shall confirm that no credentials, customer data, or personal data are present anywhere in the history, not only at the current commit.
- Files containing secrets shall never be committed, regardless of repository visibility. Secrets are stored in the secret manager and are `Confidential` by definition.
- Configuration and infrastructure-as-code files that reference production systems shall carry a comment identifying them as `Confidential` where the repository is not itself already private.

### 2.3 Databases, object storage, and data pipelines

- Database tables and columns holding Confidential data shall be identifiable from `server/data-export.md`, the register of the personal and organizational data Tuist GmbH stores, which is kept current as the schema changes. Data recorded there as belonging to a customer or to an identifiable person is Confidential under the criteria in section 1.2.
- Object storage buckets and prefixes shall be classified as a whole, and the classification shall be recorded alongside the bucket's access policy. Buckets holding customer artifacts are `Confidential`.
- Data exports and reports inherit the highest classification of their inputs, and the label shall be carried into the filename or the export's header.

### 2.4 Communications and tickets

- Slack channels shall be classified at the channel level. Private channels default to `Confidential` when used to discuss customer data, security findings, or personnel matters. Public channels within the workspace are `Restricted`. Community Slack channels open to non-employees are `Public`.
- Issues, pull requests, and tickets in private repositories are `Restricted` by default and `Confidential` when they contain customer data or security findings. Security findings shall use private security advisories rather than open issues.
- Email carrying Confidential information shall state the classification in the subject line or the first line of the body.

### 2.5 Physical records

Confidential information printed to paper shall be labelled "Confidential" on every page, shall only be produced where there is a genuine business need, and shall be stored and destroyed in accordance with the Data Management Policy.

## 3. Handling labels through the information lifecycle

- **Derivation.** Any copy, extract, summary, screenshot, or export of labelled information inherits the label of its source. Removing context does not lower the class.
- **Reclassification.** Information may be reclassified downward only by the data owner, and only once the sensitivity that justified the original class no longer applies. Reclassification of Confidential information shall be recorded with who approved it and why.
- **Publication.** Moving information to `Public` is a deliberate act requiring data owner approval. Publishing customer data, security findings, or personal data requires the affected party's consent or a documented legal basis.
- **Disposal.** Labelled information shall be disposed of in accordance with the retention and disposal requirements of the Data Management Policy.

## 4. Verification

- Labelling is checked as part of the annual review of the Data Management Policy and this policy.
- Access reviews under the [Access control policy](/security/access-and-risk-management/access-control-policy) shall confirm that access granted to a system is consistent with the classification of the data that system holds.
- Automated secret scanning runs in continuous integration against the main repository, on every pull request and on every merge to the default branch, so that Confidential authentication material committed in error is detected. Detections are handled under the [Incident Response Management](/security/human-and-incident-management/incident-response-management) policy.
- Mislabelled or unlabelled information found by anyone shall be reported to the data owner and corrected. Discovery of Confidential information in a Public location is a security incident.

## 5. Training

Classification and labelling are covered in security onboarding and in the annual security awareness refresher. Personnel are expected to know the three classes, the default class, and the criteria that make information Confidential.

## Roles and responsibilities

**Security lead.** Owns this policy and the classification scheme, resolves escalated classification disputes, approves reclassification of Confidential information.

**Data owners.** Classify the information in their systems and business areas, approve reclassification and publication, and confirm labelling during reviews.

**All personnel.** Classify what they create at the point of creation, apply the correct label, honour the handling requirements of the label, and report labelling errors they find.

## Exceptions

Requests for an exception to this policy must be submitted to the IT Manager for approval and shall be reviewed at least annually.

## Violations and enforcement

Any known violations of this policy should be reported to the IT Manager. Violations can result in immediate withdrawal or suspension of system and network privileges and disciplinary action in accordance with company procedures up to and including termination of employment.

## Review

This policy shall be reviewed annually, or whenever the classification scheme in the Data Management Policy changes.

## Version history

The version history of this document can be found in Tuist's [handbook](https://github.com/tuist/handbook) repository.
