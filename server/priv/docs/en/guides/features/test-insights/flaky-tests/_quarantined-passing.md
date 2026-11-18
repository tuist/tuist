### Why quarantined tests can appear as passing {#quarantined-passing}

- **Muted tests** still execute. A muted test that fails is recorded as **failed** on the test case run and flagged as flaky; the per-test status is not rewritten. What gets overridden is the **overall test run**: if every failing test case in the run is muted, the run as a whole is reported as passed, so muted failures don't break CI.
- **Skipped tests** don't run at all, so the dashboard keeps showing the status from the test's last actual execution. That snapshot can be weeks old.
