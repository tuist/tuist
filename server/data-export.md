# Data Export Documentation

This document outlines all data that Tuist can export for customers upon legal request (GDPR, CCPA). **Data is exported for the specific account associated with the requesting user or organization**.

## Export Format

Data is provided in a single compressed archive containing:
- **Database data**: JSON files with account information, projects, command events, and analytics
- **Binary files**: All uploaded files (cache artifacts, app previews, icons, QA screenshots)
- **Manifest**: Index of all included files and data

Sensitive authentication data (passwords, tokens) are excluded from exports.

## Exportable Data

### Account & User Data
- User profiles (email, account settings)
- Organization memberships and roles
- Account billing information and subscriptions
- API tokens and project tokens (existence only, not values)
- Custom cache endpoint configurations

### Projects & Development
- Project information (names, settings, repositories)
- Command events (CLI usage, build data, performance metrics)
- Cache events and cache action items
- Test cases and test execution results
- Build system data (Xcode graphs, projects, targets)
- Cacheable tasks (Xcode cache analytics: type, status, keys)

### App Previews & Builds
- Preview metadata (versions, platforms, git info)
- App build information
- QA test runs and screenshots

### Analytics Data
- Build performance metrics
- Build issues and compilation data
- QA testing logs and results
- Build runs with cache hit/miss statistics (cacheable_task_remote_hits_count, cacheable_task_local_hits_count, cacheable_tasks_count)

### Non-Exportable Data
- Swift package registry data (shared community resources)
- Encrypted passwords and authentication secrets

## Binary Files

All uploaded files associated with the account are included:
- **Cache artifacts**: Build caches and compiled binaries
- **App previews**: iOS app bundles (.app/.ipa files) and icons  
- **QA screenshots**: Test run screenshots and reports

**Note**: Package registry files are not included (shared community resources).

## Export Process

1. Verify user identity and account ownership
2. Collect all database records for the account and associated organizations  
3. Collect all binary files owned by the account
4. Create compressed archive with JSON data files and binary files
5. Provide secure download link

The archive contains everything needed to understand the account's complete data footprint within Tuist.