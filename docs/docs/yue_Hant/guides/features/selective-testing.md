---
{
  "title": "Selective testing",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Use selective testing to run only the tests that have changed since the last successful test run."
}
---
# Selective testing {#selective-testing}

As your project grows, so does the amount of your tests. For a long time,
running all tests on every PR or push to `main` takes tens of seconds. But this
solution does not scale to thousands of tests your team might have.

On every test run on the CI, you most likely re-run all the tests, regardless of
the changes. Tuist's selective testing helps you to drastically speed up running
the tests themselves by running only the tests that have changed since the last
successful test run based on our
<LocalizedLink href="/guides/features/projects/hashing">hashing algorithm</LocalizedLink>.

Selective testing works with `xcodebuild`, which supports any Xcode project, or
if you generate your projects with Tuist, you can use the `tuist test` command
instead that provides some extra convenience such as integration with the
<LocalizedLink href="/guides/features/cache">binary cache</LocalizedLink>. To
get started with selective testing, follow the instructions based on your
project setup:

- <LocalizedLink href="/guides/features/selective-testing/xcode-project">xcodebuild</LocalizedLink>
- <LocalizedLink href="/guides/features/selective-testing/generated-project">Generated project</LocalizedLink>

::: warning MODULE VS FILE-LEVEL GRANULARITY
<!-- -->
Due to the impossibility of detecting the in-code dependencies between tests and
sources, the maximum granularity of selective testing is at the target level.
Therefore, we recommend keeping your targets small and focused to maximize the
benefits of selective testing.
<!-- -->
:::

::: warning TEST COVERAGE
<!-- -->
Test coverage tools assume that the whole test suite runs at once, which makes
them incompatible with selective test runs—this means the coverage data might
not reflect reality when using test selection. That’s a known limitation, and it
doesn’t mean you’re doing anything wrong. We encourage teams to reflect on
whether coverage is still bringing meaningful insights in this context, and if
it is, rest assured that we’re already thinking about how to make coverage work
properly with selective runs in the future.
<!-- -->
:::


## Pull/merge request comments {#pullmerge-request-comments}

::: warning INTEGRATION WITH GIT PLATFORM REQUIRED
<!-- -->
To get automatic pull/merge request comments, integrate your
<LocalizedLink href="/guides/server/accounts-and-projects">Tuist project</LocalizedLink> with a
<LocalizedLink href="/guides/server/authentication">Git platform</LocalizedLink>.
<!-- -->
:::

Once your Tuist project is connected with your Git platform such as
[GitHub](https://github.com), and you start using `tuist xcodebuild test` or
`tuist test` as part of your CI wortkflow, Tuist will post a comment directly in
your pull/merge requests, including which tests were run and which skipped:
![GitHub app comment with a Tuist Preview
link](/images/guides/features/selective-testing/github-app-comment.png)
