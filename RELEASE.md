# Release

This document describes the process of releasing new versions of tuist.

1. Determine the new version:
    - Major if there's been a breaking change (`+.x.x`).
    - Minor by default (`x.+.x`).
    - Patch if it's a hotfix release (`x.x.+`).
    - Reach out to the core team if you have questions.
2. Go to the Actions tab in GitHub
3. Select the "Tuist Release" action
4. Select Run Workflow
5. Input the version from #1 into the action prompt and provide a title
6. Run the workflow
7. Wait for the workflow to run and succeed and verify with `tuist update`

## Back releases

If you are releasing a version that is older than the latest version you will need to manually create the release, to do this:

1.  First, make sure you are in `main` branch and the latest changes are pulled
    - `git checkout main && git pull origin main`
2.  Determine the new version:
    - Major if there's been a breaking change.
    - Minor by default.
    - Patch if it's a hotfix release.
3.  Update the version in the `Constants.swift` file.
4.  Update the `CHANGELOG.md` to include the version section.
5.  Commit the changes and tag the commit with the version `git tag x.y.z`.
6.  Build tuist artifacts by running `./fourier release tuist x.y.z`.
7.  Create a release on GitHub with the version as a title, the body from the CHANGELOG file, and attach the artifacts in the `build/` directory.
8.  Run `tuist update` and verify that the new version is installed and runs.
