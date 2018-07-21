# Release

This document describes the process of releasing new versions of xpm.

1.  First make sure you are in master and the latest changes are pulled: `git pull origin master`
2.  Ensure that the project is in a releaseable state by running the tests: `swift test`.
3.  Determine the new version:

- Major if there's been a breaking change.
- Minor by default.
- Patch if it's a hotfix release.

4.  Update the version in the `Constants.swift` file.
5.  Update the `CHANGELOG.md` to include the version section.
6.  Generate the referece with `swift run xpmtools reference`.
7.  Commit the changes and tag the commit with the version `git tag x.y.z`.
8.  Push the changes to remote and create a new release on GitHub including the changelog.
