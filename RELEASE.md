# Release

This document describes the process of releasing new versions of tuist.

1.  Determine the new version:

- Major if there's been a breaking change.
- Minor by default.
- Patch if it's a hotfix release.
2. Run `tapestry github-release version-number` (eg `tapestry github-release 1.1.0`) *(Install [tapestry](https://github.com/ackeecz/tapestry) and [tuist](https://github.com/tuist/tuist) if you don't have them installed already)*.