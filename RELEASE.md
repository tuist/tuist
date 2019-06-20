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
7.  Package the release running `bundle exec rake package`.
8.  Push the changes to remote and create a new release on GitHub including the changelog. Attach all the files in the `build/` directory.
9.  Deploy the documentation website to [Netlify](https://app.netlify.com/sites/peaceful-fermat-c0d5d7/deploys).
