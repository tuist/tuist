---
{
  "title": "Selective testing",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Use Tuist Selective Testing to run only the Xcode tests affected by your latest changes."
}
---
# Selective testing {#selective-testing}

Tuist Selective Testing helps you run only the tests affected by your latest changes, both for generated projects and standard Xcode projects.

As your project grows, so does the amount of your tests. For a long time, running all tests on every PR or push to `main` takes tens of seconds. But this solution does not scale to thousands of tests your team might have.

On every test run on the CI, you most likely re-run all the tests, regardless of the changes. Tuist's selective testing helps you to drastically speed up running the tests themselves by running only the tests that have changed since the last successful test run based on our <LocalizedLink href="/guides/features/projects/hashing">hashing algorithm</LocalizedLink>.

To run tests selectively with your <LocalizedLink href="/guides/features/projects">generated project</LocalizedLink>, use the `tuist test` command. The command <LocalizedLink href="/guides/features/projects/hashing">hashes</LocalizedLink> your Xcode project the same way it does for the <LocalizedLink href="/guides/features/cache/module-cache">module cache</LocalizedLink>, and on success, it persists the hashes to determine what has changed in future runs. In future runs, `tuist test` transparently uses the hashes to filter down the tests and run only the ones that have changed since the last successful test run.

`tuist test` integrates directly with the <LocalizedLink href="/guides/features/cache/module-cache">module cache</LocalizedLink> to use as many binaries from your local or remote storage to improve the build time when running your test suite. The combination of selective testing with module caching can dramatically reduce the time it takes to run tests on your CI.

::: warning MODULE VS FILE-LEVEL GRANULARITY
<!-- -->
Due to the impossibility of detecting the in-code dependencies between tests and sources, the maximum granularity of selective testing is at the target level. Therefore, we recommend keeping your targets small and focused to maximize the benefits of selective testing.
<!-- -->
:::

::: warning TEST COVERAGE
<!-- -->
Test coverage tools assume that the whole test suite runs at once, which makes them incompatible with selective test runs—this means the coverage data might not reflect reality when using test selection. That’s a known limitation, and it doesn’t mean you’re doing anything wrong. We encourage teams to reflect on whether coverage is still bringing meaningful insights in this context, and if it is, rest assured that we’re already thinking about how to make coverage work properly with selective runs in the future.
<!-- -->
:::


## Pull/merge request comments {#pullmerge-request-comments}

::: warning INTEGRATION WITH GIT PLATFORM REQUIRED
<!-- -->
To get automatic pull/merge request comments, integrate your <LocalizedLink href="/guides/server/accounts-and-projects">Tuist project</LocalizedLink> with a <LocalizedLink href="/guides/server/authentication">Git platform</LocalizedLink>.
<!-- -->
:::

Once your Tuist project is connected with your Git platform such as [GitHub](https://github.com), and you start using `tuist test` as part of your CI workflow, Tuist will post a comment directly in your pull/merge requests, including which tests were run and which skipped:
![GitHub app comment with a Tuist Preview link](/images/guides/features/selective-testing/github-app-comment.png)
