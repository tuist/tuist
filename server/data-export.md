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

### Alerts & Monitoring
- Alert rules (name, category, metric, deviation thresholds, Slack channel configuration)
- Alert history (triggered alerts with current/previous values, timestamps)

### Analytics Data (ClickHouse)
The following data is stored in ClickHouse for analytics purposes:
- **Build runs** (`build_runs` table): Complete build execution data including duration, status, cache statistics, CI metadata, git information, and custom tags
- **Build issues** (`build_issues` table): Compilation warnings and errors from builds
- **Build files** (`build_files` table): Individual file compilation metrics
- **Build targets** (`build_targets` table): Target/module build performance
- **Cacheable tasks** (`cacheable_tasks` table): Xcode cache task analytics with hit/miss status
- **CAS outputs** (`cas_outputs` table): Content-addressable storage upload/download records
- Build performance metrics
- QA testing logs and results

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