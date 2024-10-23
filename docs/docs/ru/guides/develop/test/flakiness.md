---
title: Test flakiness
description: Prevent, detect, and fix flaky tests with Tuist.
---

<h1 id="test-flakiness">Test flakiness</h1>

> [!IMPORTANT] REMOTE PROJECT REQUIRED
> This feature requires a <LocalizedLink href="/server/introduction/accounts-and-projects">remote project</LocalizedLink>.

It's common in test suite to have flaky tests. Those are tests that sometimes pass and sometimes fail, even though the code under test hasn't changed. Flaky tests are a problem because **they reduce the trust in the test suite and make it harder to detect real regressions.** Moreover, they might slow down the development process because developers might need to rerun the tests multiple times until they pass.

Luckily, Tuist provides a solution to detect flay tests.

<h2 id="detecting-flakiness">Detecting flakiness</h2>

When running tests with <LocalizedLink href="/guides/develop/test">`tuist test`</LocalizedLink>, Tuist persists the result of each test case along with a unique hash that identifies the test state. The unique hash changes if either the module containing the test or any of its dependencies change. Thanks to the unique hash and the results, Tuist can determine if a test is flaky. A test case is flaky if it has yielded different results for the same hash.

In the project dashboard, you can see a list of flaky tests along with the test runs whose result bundles you can download to investigate the flakiness. For example, the image below shows a test case, `test_create_list_and_revoke_project_token`, that has been flagged as flaky:

<img src="/images/guides/develop/test/flaky-test-case.png" alt="An image that shows the Tuist dashboard where one can see a test case named test_create_list_and_revoke_project_token and all their test runs where one of them shows as failing."/>
