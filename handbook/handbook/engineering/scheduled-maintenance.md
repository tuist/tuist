---
{
  "title": "Scheduled maintenance",
  "titleTemplate": ":title | Engineering | Tuist Handbook",
  "description": "This document outlines our company's approach to communicating scheduled maintenance activities to users."
}
---
## Scheduled Maintenance Guidelines

### Overview

This document outlines our company's approach to communicating scheduled maintenance activities to users.
Following these guidelines ensures transparent and timely communication about system maintenance and potential service interruptions.

| Category | Expected Impact                    | First Notice |
| -------- | ---------------------------------- | ------------ |
| Minor    | No expected downtime, minimal risk | 24 hours     |
| Standard | Limited service interruption       | 3 days       |
| Major    | Significant service interruption   | 7 days       |

### Scheduling

For activities that we expect to cause a service interruption (standard or major), we aim to place the maintenance window to not overlap
with business hours of our customers. This ensures that the interruption has minimal impact on the user experience.

Given the distributed nature of our customer base, planning should take into account all time zones of the affected users.

### Messaging

All maintenance announcements, regardless of category, should include:

- Start date and time (including timezone)
- Expected duration
- Components affected
- Expected user impact
- Link to status page for updates

### Maintenance Categories

The following categories should be considered as guidelines for scheduling maintenance activities. Depending on the activities and
associated risks, the category may be adjusted accordingly.

#### Minor Maintenance

**Expected Impact**: No expected downtime, minimal risk

Minor maintenance is a low-risk maintenance activity that we do not expect to cause a service interruption. We communicate these activities
for transparency and for risk management.

##### Communication Timeline

- First notice: 24 hours before
- Reminder: 1 hour before

##### Communication Channels

- Status page
- Slack announcement
- Community forum post (optional)

#### Standard Maintenance

**Expected Impact**: Limited service interruption  
**Duration**: 5-60 minutes

Standard maintenance is an activity that we expect to cause a limited service interruption, meaning that at least part of the service
is unavailable for a short period of time.

##### Communication Timeline

- First notice: 3 days before
- Reminders:
  - 24 hours before
  - 1 hour before

##### Communication Channels

- Status page
- Slack announcement
- Community forum post

#### Major Maintenance

**Expected Impact**: Significant service interruption  
**Duration**: 1 hour or longer

A major maintenance activity is an activity that we expect to cause a significant service interruption, meaning that part or the entirety of
the service is unavailable for an extended period of time.

##### Communication Timeline

- First notice: 7 days before
- Reminders:
  - 3 days before
  - 24 hours before
  - 1 hour before

##### Communication Channels

- Status page
- Slack announcement
- Social media announcement
- Community forum post
- Email notification for all affected users
