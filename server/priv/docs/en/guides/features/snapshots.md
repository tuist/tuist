---
{
  "title": "Snapshots",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Catch visual regressions in Xcode and Gradle projects: Tuist stores your snapshot images, compares each pull request with its baseline, and lets you approve or reject changes from the dashboard or the pull request."
}
---
# Snapshots {#snapshots}

> [!IMPORTANT]
> **Invite-only**
>
> Snapshots are currently invite-only. [Reach out](mailto:contact@tuist.dev) or ping us in the [community Slack](https://slack.tuist.dev) to request access for your account.

Snapshot tests render your UI to images and compare them with reference images to catch visual regressions. Instead of committing those reference images to your repository, you upload the images every test run renders to Tuist. Tuist compares them with a **baseline**, shows what changed in the dashboard, and fails the run until someone approves the changes.

- No reference images in Git, so checkouts stay small and nobody resolves conflicts in PNG files.
- Reviewers see the changes next to the code: side by side, as a diff, or with a wipe or onion skin overlay.
- Changes are approved or rejected in the dashboard or on the pull request, and the approval becomes the new baseline once the branch merges.

## How it works {#how-it-works}

1. Your tests render images, for example of every SwiftUI or Compose preview.
2. The Tuist CLI or Gradle plugin uploads them as a **snapshot build** of the current commit.
3. Tuist picks the baseline: the build of your default branch at the commit your branch started from.
4. Every image is compared with its baseline and marked as changed, added, removed, or unchanged.
5. The build gets a verdict:

| Verdict | Run | When |
| --- | --- | --- |
| Baseline | Passes | The build is from the default branch, so later builds compare with it. |
| Passed | Passes | No image changed or was removed. New images need no review. |
| Needs review | Fails | Images changed or were removed, and nobody reviewed them yet. |
| Approved | Passes | Someone approved the changes. |
| Rejected | Fails | Someone rejected the changes. |

Builds are compared within a **set**, such as `ios-iphone` or `android-phone`. Use one set per device configuration, so images rendered at different sizes are never compared with each other.

## Set up {#set-up}

Pick the integration for your project:

<.home_cards>
  <.home_card
    title="Xcode"
    details="Snapshot every SwiftUI preview of an Xcode project with tuist xcodebuild test."
    link="/guides/features/snapshots/xcode"
/>
  <.home_card
    title="Generated projects"
    details="Snapshot every SwiftUI preview of a Tuist generated project with tuist test."
    link="/guides/features/snapshots/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="Snapshot every Compose preview, or upload what Paparazzi and Roborazzi record, with the Tuist Gradle plugin."
    link="/guides/features/snapshots/gradle"
/>
</.home_cards>

## Review changes in the dashboard {#dashboard}

Every snapshot build has a page under **Tests → Snapshots** in your project's dashboard. It shows the build's verdict, branch, commit, pull request, and baseline, and lists the images by status and group. Use **Approve changes** or **Reject changes** to review the build. You can change a review later.

![A snapshot build that needs review, with a changed image side by side with its baseline](/images/guides/features/snapshots/review.png)

Switch between **Side by side**, **Diff**, which highlights the changed pixels, **Wipe**, which slides between the baseline and the new image, and **Onion**, which fades one into the other. Each image can be opened full screen.

![The wipe mode, sliding between the baseline and the new image](/images/guides/features/snapshots/wipe.png)

## Review changes on the pull request {#pull-request}

With the <.localized_link href="/guides/integrations/gitforge/github">GitHub app</.localized_link> installed, every snapshot build of a pull request gets a check named `tuist/snapshots (<set>)`. While changes need review, or after a reviewer rejected them, the check fails and blocks merging if it's required:

![The pull request's merge box with the snapshots check failing because the changes were rejected](/images/guides/features/snapshots/github-pr-checks.png)

The check counts the changed, added, and removed images of the set and links to the build in the dashboard. Approve or reject the changes from the check's page, without leaving GitHub. The check updates with the reviewer's name, and a rejected build can still be approved later.

![The snapshots check on GitHub after the changes were rejected, with the button to approve them](/images/guides/features/snapshots/github-check-run.png)

Approving doesn't rerun your tests: it passes the check. Later builds of the same branch keep the approval as long as they have exactly the same changes, so rerunning CI or pushing a commit that doesn't touch the reviewed images passes too. Any other change to the images needs a new review. Once the branch merges, the default branch's build becomes the new baseline.
