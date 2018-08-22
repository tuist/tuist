# Release

This document describes the process of releasing new versions of tuist.

1.  First make sure you are in master and the latest changes are pulled: `git pull origin master`
2.  Ensure that the project is in a releaseable state by running the tests: `swift test`.
3.  Determine the new version:

- Major if there's been a breaking change.
- Minor by default.
- Patch if it's a hotfix release.

4.  Update the version in the `Constants.swift` and `tuist.rb` files.
5.  Build `tuistenv` running `make build-env`, and update the `tuist.rb` file with the new sha256.
6.  Update the `CHANGELOG.md` to include the version section.
7.  Generate the documentation with `jazzy`.
8.  Commit the changes and tag the commit with the version `git tag x.y.z`.
9.  Bundle the release with `make zip-release`. It'll generate a `tuist.zip` file in the root directory.
10. Push the changes to remote and create a new release on GitHub including the changelog and the release bundle, the `tuist.zip` file.
