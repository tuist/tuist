---
title: Changelog guidelines
slug: /contributors/changelog-guidelines
description: Read about the guidelines that the project embrace for the style of the CHANGELOG file. Every user-facing change added to the project requires changes in this file that is useful for users to know what's coming with every new version of Tuist.
---

Here you can find the general guidelines for maintaining the Changelog (or adding new entry). We follow the guidelines from [Keep a Changelog](http://keepachangelog.com/en/1.0.0/) with few additions.

### Guiding Principles

- Changelogs are for humans, not machines.
- There should be an entry for every single version.
- The same types of changes should be grouped.
- Versions and sections should be linkable.
- The latest version comes first.
- The release date of each versions is displayed.
- Mention whether you follow Semantic Versioning.
- Keep an unreleased section at the top.
- Add PR number and a GitHub tag at the end of each entry.
- Each breaking change entry should have **Breaking Change** label at the beginning of this entry.
- **Breaking Change** entries should be placed at the top of the section it's in.

## Types of changes

- **Added** for new features.
- **Changed** for changes in existing functionality.
- **Deprecated** for soon-to-be removed features.
- **Removed** for now removed features.
- **Fixed** for any bug fixes.
- **Security** in case of vulnerabilities.

### Example:

```
## [9.0.0] - 2017-09-04

### Added

- Added tests for `Single<Response>` operators. [#1229](https://github.com/Moya/Moya/pull/1229) by [@freak4pc](http://github.com/freak4pc)

### Changed

- **Breaking Change** Changed the `TargetType` so it doesn't have `parameters` & `parameterEncoding`. Instead, `task` property offer similar functionalities. [#1147](https://github.com/Moya/Moya/pull/1147) by [@Dschee](http://github.com/Dschee)
- Changed the `Endpoint` initializer so it doesn't have default `task` argument. [#1252](https://github.com/Moya/Moya/pull/1252) by [@SD10](http://github.com/SD10)
```
