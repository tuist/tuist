# Shared test-report identities

- These reports and their expected suite/name pairs are consumed by both the
  Swift failure-reader tests and the Elixir report-parser tests.
- Every case is a failure so the failure reader exposes every identity.
- Keep expected.json explicit, including the Unicode boundary expectations.
  Do not generate expected values using either parser under test.
- Duplicate local attribute names across namespaces are ambiguous in Swift's
  attribute dictionary and must be rejected by the failure reader, not guessed.
