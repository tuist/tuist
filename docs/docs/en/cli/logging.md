---
title: Logging
titleTemplate: :title · CLI · Tuist
description: Learn how to enable and configure logging in Tuist.
---

# Logging {#logging}

## Diagnosing with logs {#diagnosing-with-logs}

If a command invocation doesn't yield the intended results, you can diagnose the issue by inspecting the logs. The CLI forwards the logs to [OSLog](https://developer.apple.com/documentation/os/oslog) and the file-system. In every run, it creates a log file at `$XDG_STATE_HOME/tuist/logs/{uuid}.log` where `$XDG_STATE_HOME` takes the value `~/.local/state` if the environment variable is not set.

By default, the CLI outputs the logs path when the execution exits unexpectedly. If it doesn't, you can find the logs in the path mentioned above (i.e., the most recent log file).

> [!IMPORTANT]
> Sensitive information is not redacted, so be cautious when sharing logs.
