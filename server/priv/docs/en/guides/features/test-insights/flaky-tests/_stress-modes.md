### Enabling it {#enabling-stress-testing}

The gate is off by default. Set a mode:

- **`report`**: warns about each flaky test case. The run still exits on its own result.
- **`enforce`**: a flaky test case fails the run, with the same exit code as a failed test.

Start with `report` for a couple of weeks to see what `enforce` would have blocked.
