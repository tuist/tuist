# Release
This document describes all the steps that you need to go through to release a new version of the app:

> Note: Only an authorized person with access to the private keys can release new version of the app. All the necessary keys are encrypted in the directory `/keys`.

1. Being on `master`, pull the latest changes.
2. Create a new branch with the name `version/x.y.z` where `x.y.z` is the new version.
3. Update the [CHANGELOG.md](CHANGELOG.md) file adding a new section at the top for the next version *(if the version that is about to be released includes breaking changes, the new version should be a major version)*. Commit the changes in the file.
4. Run the command `bundle exec rake release`. If it succeeds, it'll create a new release on GitHub containing the changelog and a zip with the app binary.
5. Rebase this branch into `master` and push the changes to the GitHub repository.