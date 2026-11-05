### When the gate doesn't run {#when-the-gate-does-not-run}

- The first pass already failed. Fix those tests first.
- The project has no default branch, or nothing has run in CI on it yet.
- More than 30% of the project's test cases look new. Rerunning that many would take longer than it's worth. Expect this on a project that only just started reporting to Tuist, or after a rename that moves a lot of tests at once.
