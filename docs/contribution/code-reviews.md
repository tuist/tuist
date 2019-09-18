---
name: Code reviews
menu: Contributors
---

# Code reviews

Reviewing pull requests is a common type of contribution.
Despite continuous integration (CI) ensuring the code does what's supposed to do,
it's not enough.
There are contribution traits that can't be automated:
_design, code structure & architecture, tests quality, or typos._

This document puts together traits that we should look out for when reviewing pull requests:

- **Readability:** Does the code express its intention clearly?
  If you need to spend a bunch of time figuring out what the code does,
  the code implementation needs to be improved.
  Suggest splitting the code into smaller abstractions that are easier to understand.
  Alternative, and as a last resource,
  they can add a comment explaining the reasoning behind it.
  Ask yourself if you'd be able to understand the code in a near future,
  without any surrounding context like the pull request description.
- **Tests:** Tests allow changing code with confidence.
  The code on pull requests should be tested,
  and tests should be good.
  A good test is a test that consistently produces the same result and that it's easy to understand and maintain.
  Reviewers spend most of the review time in the implementation code,
  but tests are equally important because they are code too.

- **Breaking changes:**

- **Documentation:**
