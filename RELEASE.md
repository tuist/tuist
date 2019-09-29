# Release

This document describes the process of releasing new versions of tuist.

1.  First make sure you are in master and the latest changes are pulled: `git pull origin master`
2.  Ensure that the project is in a releasable state by running the tests: `swift test` and `bundle exec rake features`.
3.  Determine the new version:

- Major if there's been a breaking change.
- Minor by default.
- Patch if it's a hotfix release.

4.  Update the version in the `Constants.swift` file.
5.  Update the `CHANGELOG.md` to include the version section.
6.  Commit the changes and tag the commit with the version `git tag x.y.z`.
7.  Package and upload the release to GCS by running `bundle exec rake release`.
8.  Upload the installation scripts to GCS 0.18.by running `bundle exec rake release_scripts`.
9.  Create a release on GitHub with the version as a title, the body from the CHANGELOG file, and attach the artifacts in the `build/` directory.
10. Deploy the documentation website to [Netlify](https://app.netlify.com/sites/peaceful-fermat-c0d5d7/deploys).
11. Run `tuist update` and verify that the new version is installed and runs.
