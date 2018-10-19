# Release

This document describes the process of releasing new versions of tuist.

1.  First make sure you are in master and the latest changes are pulled: `git pull origin master`
2.  Ensure that the project is in a releaseable state by running the tests: `swift test`.
3.  Determine the new version:

- Major if there's been a breaking change.
- Minor by default.
- Patch if it's a hotfix release.

4.  Update the version in the `Constants.swift` file.
5.  Update the `CHANGELOG.md` to include the version section.
6.  Generate the documentation by running [this script](https://github.com/tuist/jazzy-theme).
7.  Commit the changes and tag the commit with the version `git tag x.y.z`.
8.  Package the release running `make package-release`.
9.  Push the changes to remote and create a new release on GitHub including the changelog. Attach all the files in the `build/` directory.
