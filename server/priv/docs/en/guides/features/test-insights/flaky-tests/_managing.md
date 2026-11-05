## Managing flaky tests {#managing-flaky-tests}

### Automatic clearing {#automatic-clearing}

Detection and clearing run through an **automation alert** on the project. Every project gets a default "Flaky test detection" automation whose *trigger* marks a test as flaky and whose *recovery* clears the flag once the test has gone the configured recovery window (default **14 days**) without re-triggering. Edit it under **Settings → Automations** to change the recovery window, change the recovery actions (for example, also release the test from quarantine), or disable recovery entirely so tests stay marked flaky until you clear them by hand.

### Manual management {#manual-management}

You can also manually mark or unmark tests as flaky from the test case detail page. This is useful when:
- You want to acknowledge a known flaky test while working on a fix
- A test was incorrectly flagged due to infrastructure issues
