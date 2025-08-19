---
{
  "title": "Logging",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Learn how to enable and configure logging in Tuist."
}
---
# Logging {#logging}

The CLI logs messages internally to help you diagnose issues.

## Diagnose issues using logs {#diagnose-issues-using-logs}

If a command invocation doesn't yield the intended results, you can diagnose the issue by inspecting the logs. The CLI forwards the logs to [OSLog](https://developer.apple.com/documentation/os/oslog) and the file-system.

In every run, it creates a log file at `$XDG_STATE_HOME/tuist/logs/{uuid}.log` where `$XDG_STATE_HOME` takes the value `~/.local/state` if the environment variable is not set.

By default, the CLI outputs the logs path when the execution exits unexpectedly. If it doesn't, you can find the logs in the path mentioned above (i.e., the most recent log file).

> [!IMPORTANT]
> Sensitive information is not redacted, so be cautious when sharing logs.

### Continuous integration {#diagnose-issues-using-logs-ci}

In CI, where environments are disposable, you might want to configure your CI pipeline to export Tuist logs.
Exporting artifacts is a common capability across CI services, and the configuration depends on the service you use.
For example, in GitHub Actions, you can use the `actions/upload-artifact` action to upload the logs as an artifact:

```yaml
name: Node CI

on: [push]

env:
  XDG_STATE_HOME: /tmp

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
      # ... other steps
      - run: tuist generate
      # ... do something with the project
      - name: Export Tuist logs
        uses: actions/upload-artifact@v4
        with:
          name: tuist-logs
          path: /tmp/tuist/logs/*.log
```
