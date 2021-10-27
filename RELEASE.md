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
