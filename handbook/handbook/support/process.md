---
{
  "title": "Support process",
  "titleTemplate": ":title | Support | Tuist Handbook",
  "description": "Learn how we provide support to developers and organizations using Tuist."
}
---
# Support process

Developers and organizations might run into issues or have questions while using Tuist.
When that happens, we need to ensure their input is processed promptly and the proper context is captured to understand the problem or need and prioritize it accordingly.
This page outlines the processes that we have in place for providing the best support.

## Default to GitHub

By default, we use GitHub to provide support through [GitHub Issues](https://github.com/features/issues),
and we expect developers and organizations to create issues in the repository associated with the project they are having issues with.
Most will do so in the [tuist/tuist](https://github.com/tuist/tuist) repository to provide support,
which takes priority over issues in other open-source repositories that we maintain.

When providing support:

- Ensure the issue contains all the necessary information to understand the problem or need and includes a [reproducible project](https://docs.tuist.io/contributors/issue-reporting.html#reproducible-project) and steps. If it doesn't, assign the status `Needs reproduction/response` in the Tuist GitHub project.
- If the person is blocked, provide a workaround if possible.
- Assign the priority based on the following criteria:
  - **P0**: Critical issue that prevents them from using a paid feature or the tool.
  - **P1**: Critical issue that prevents them from using the tool (no workaround exists).
  - **P2**: Important issue that doesn't prevent them from using the tool.
  - **P3**: Nice-to-have feature or improvement.

> [!IMPORTANT] P0 ISSUES
> P0 Issues should become an immediate priority and be worked on as soon as possible.

> [!NOTE] SLACK
> We should expect that people might use the community Slack to seek support. We should monitor the Slack channel and redirect them to GitHub Issues if they haven't already created an issue. Slack is not the best support channel to use at scale.

## Priority support

**Tuist Enterprise organizations** can use the cross-Slack channel to get priority support. Tickets reported through this channel get the highest priority.

**Tuist Pro organizations** can use the `support@tuist.io` email to get priority support and a cross-slack channel.
We process those emails through [Intercom](https://intercom.com),
so if you are expected to provide support, you'll have access to the Intercom inbox.
Assign new tickets to you to signal that you are working on them.