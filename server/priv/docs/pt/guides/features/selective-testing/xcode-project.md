---
{
  "title": "Xcode project",
  "titleTemplate": ":title · Selective testing · Features · Guides · Tuist",
  "description": "Learn how to leverage selective testing with `xcodebuild`."
}
---
# Xcode project {#xcode-project}

::: warning REQUIREMENTS
<!-- -->
- A <LocalizedLink href="/guides/server/accounts-and-projects">Tuist account and project</LocalizedLink>
<!-- -->
:::

You can run the tests of your Xcode projects selectively through the command
line. For that, you can prepend your `xcodebuild` command with `tuist` – for
example, `tuist xcodebuild test -scheme App`. The command hashes your project
and on success, it persists the hashes to determine what has changed in future
runs.

In future runs `tuist xcodebuild test` transparently uses the hashes to filter
down the tests to run only the ones that have changed since the last successful
test run.

For example, assuming the following dependency graph:

- `FeatureA` has tests `FeatureATests`, and depends on `Core`
- `FeatureB` has tests `FeatureBTests`, and depends on `Core`
- `Core` has tests `CoreTests`

`tuist xcodebuild test` will behave as such:

| Action                             | Descrição                                                           | Internal state                                                                 |
| ---------------------------------- | ------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| `tuist xcodebuild test` invocation | Runs the tests in `CoreTests`, `FeatureATests`, and `FeatureBTests` | The hashes of `FeatureATests`, `FeatureBTests` and `CoreTests` are persisted   |
| `FeatureA` is updated              | The developer modifies the code of a target                         | Same as before                                                                 |
| `tuist xcodebuild test` invocation | Runs the tests in `FeatureATests` because it hash has changed       | The new hash of `FeatureATests` is persisted                                   |
| `Core` is updated                  | The developer modifies the code of a target                         | Same as before                                                                 |
| `tuist xcodebuild test` invocation | Runs the tests in `CoreTests`, `FeatureATests`, and `FeatureBTests` | The new hash of `FeatureATests` `FeatureBTests`, and `CoreTests` are persisted |

To use `tuist xcodebuild test` on your CI, follow the instructions in the
<LocalizedLink href="/guides/integrations/continuous-integration">Continuous integration guide</LocalizedLink>.

Check out the following video to see selective testing in action:

<iframe title="Run tests selectively in your Xcode projects" width="560" height="315" src="https://videos.tuist.dev/videos/embed/1SjekbWSYJ2HAaVjchwjfQ" frameborder="0" allowfullscreen="" sandbox="allow-same-origin allow-scripts allow-popups allow-forms"></iframe>
