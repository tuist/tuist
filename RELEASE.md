# Release

This document describes the process of releasing new versions of tuist.

1.  First make sure you are in main and the latest changes are pulled: `git checkout main && git pull origin main`
2.  Determine the new version:

- Major if there's been a breaking change.
- Minor by default.
- Patch if it's a hotfix release.

3.  Update the version in the `Constants.swift` file.
4.  Update the `CHANGELOG.md` to include the version section.
5.  Commit the changes and tag the commit with the version `git tag x.y.z`.
6.  Build the release artifacts by running `./fourier bundle all`.
7.  Upload the installation scripts to GCS by running `./fourier release tuist x.y.z`.
8.  Create a release on GitHub with the version as a title, the body from the CHANGELOG file, and attach the artifacts in the `build/` directory.
9.  Run `tuist update` and verify that the new version is installed and runs.
