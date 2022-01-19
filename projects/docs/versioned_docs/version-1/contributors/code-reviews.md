---
title: Code reviews
slug: /contributors/code-reviews
description: For contributors and maintainers that help review pull requests on GitHub, this page includes a checklist with some important aspects that they should look at. It's not meant to be an exhaustive checklist but rather a reference.
---

Reviewing pull requests is a common type of contribution.
Despite continuous integration (CI) ensuring the code does what's supposed to do,
it's not enough.
There are contribution traits that can't be automated:
_design, code structure & architecture, tests quality, or typos._

This document puts together traits that we should look out for when reviewing pull requests:

**👀 Readability:** Does the code express its intention clearly?
If you need to spend a bunch of time figuring out what the code does,
the code implementation needs to be improved.
Suggest splitting the code into smaller abstractions that are easier to understand.
Alternative, and as a last resource,
they can add a comment explaining the reasoning behind it.
Ask yourself if you'd be able to understand the code in a near future,
without any surrounding context like the pull request description.

**🌱 Small pull request:** Large pull requests are hard to review and it's easier to miss out details.
If a pull request becomes too large and unmanageable,
suggest the author to break it down.

**📦 Consistency:** It's important that the changes are consistent with the rest of the project.
Inconsistencies complicate maintenance, and therefore we should avoid them.
If there's an approach to output messages to the user,
or report errors,
we should stick to that.
If the author disagrees with the project's standards,
suggest them to open an issue where we can discuss them further.

**🔬 Tests:** Tests allow changing code with confidence.
The code on pull requests should be tested,
and all tests should pass.
A good test is a test that consistently produces the same result and that it's easy to understand and maintain.
Reviewers spend most of the review time in the implementation code,
but tests are equally important because they are code too.

**⚠️ Breaking changes:** Breaking changes are a bad user experience for users of Tuist.
Contributions should avoid introducing breaking changes unless it's strictly necessary.
There are many language features that we can leverage to evolve the interface of Tuist without resorting to a breaking change.
Whether a change is breaking or not might not be obvious.
A method to verify whether the change is breaking is running Tuist against the fixture projects in the `fixtures` directory.
It requires putting ourselves in the user's shoes and imagine how the changes would impact them.

**📝 Documentation:** As the project grows and we continue to add more features,
keeping the documentation up to date is crucial for developers to adopt them.
Moreover,
it's a very valuable asset for new adopters that are giving Tuist a try.
Pull requests that change the user interface of Tuist,
for example adding support for a new argument,
must include documentation.

**📝 Changelog:** The `CHANGELOG.md` file contains a list of changes that are released with new versions.
Pull requests should add an entry to that file describing in one sentence what the change is about.
They should link to the pull request and mention the author or authors of the changes.

**🚦 Continuous integration:** Continuous integration must be happy with the changes.
The pipelines are designed to bring an extra level of confidence and validate that the changes are right.
A red CI blocks the merge of the pull request.

**✅ Merging:** A pull request is ready to be merged once there are at least 2 approvals from [Tuist core members](contributors/core-team.md).
When merging a pull request, prefer to use `Squash and merge` to keep the git history cleaner.
