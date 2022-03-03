# Release

This document describes the process of releasing new versions of Tuist.

1. Determine the new version:
    - Major if there's been a breaking change (`+.0.0`).
    - Minor by default (`x.+.0`).
    - Patch if it's a hotfix release (`x.x.+`).
    - Reach out to the core team if you have questions.
2. Select the [Tuist Release](https://github.com/tuist/tuist/actions/workflows/release.yml) action in the GitHub `Actions` tab
3. Select `Run workflow`
4. Input the version from #1 into the action prompt and provide a title
5. Run the workflow
6. Wait for release workflow to finish
7. Merge the PR created by the workflow
8. Clone [ProjectAutomation](https://github.com/tuist/ProjectAutomation) repository and run `./release.sh x.y.z`
9. Clone [ProjectDescription](https://github.com/tuist/ProjectDescription) repository and run `./release.sh x.y.z`
10. Once merged verify with `tuist update`
