---
{
  "title": "Debugging",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Learn how to debug issues with Tuist using logs and network recordings."
}
---
# Debugging {#debugging}

Tuist provides several tools to help you diagnose issues when commands don't behave as expected.

::: warning
<!-- -->
Session data may contain sensitive information such as file paths, project names, and request/response bodies. While sensitive headers (like Authorization) are redacted, be mindful when sharing session data with others.
<!-- -->
:::

## Session data {#session-data}

If a command invocation doesn't yield the intended results, you can diagnose the issue by inspecting the session data. The CLI forwards the logs to [OSLog](https://developer.apple.com/documentation/os/oslog) and the file-system.

In every run, it creates a session directory at `$XDG_STATE_HOME/tuist/sessions/{uuid}/` where `$XDG_STATE_HOME` takes the value `~/.local/state` if the environment variable is not set. You can also use `$TUIST_XDG_STATE_HOME` to set a Tuist-specific state directory, which takes precedence over `$XDG_STATE_HOME`.

Each session directory contains:
- **`logs.txt`** - Text logs from the CLI session
- **`network.har`** - [HTTP Archive (HAR)](https://w3c.github.io/web-performance/specs/HAR/Overview.html) file containing all network requests and responses made during the session

### Visualizing HAR files {#visualizing-har-files}

The HAR file records all HTTP requests and responses made during the session, which is useful for debugging server communication issues. You can open HAR files with several tools:

- **[Proxyman](https://proxyman.io/)**: A native macOS app for viewing and analyzing HTTP traffic. Import the HAR file via File > Import.
- **Browser Developer Tools**: Chrome, Firefox, and Safari all support importing HAR files in their Network tab.
- **[HAR Viewer](http://www.softwareishard.com/har/viewer/)**: A web-based HAR file viewer.

::: tip
<!-- -->
Learn more about Tuist's directory organization and how to configure custom directories in the <LocalizedLink href="/cli/directories">Directories documentation</LocalizedLink>.
<!-- -->
:::

By default, the CLI outputs the session path when the execution exits unexpectedly. If it doesn't, you can find the session data in the path mentioned above (i.e., the most recent session directory).

Session directories older than 5 days are automatically cleaned up.

### Continuous integration {#diagnose-issues-using-logs-ci}

In CI, where environments are disposable, you might want to configure your CI pipeline to export Tuist session data.
Exporting artifacts is a common capability across CI services, and the configuration depends on the service you use.
For example, in GitHub Actions, you can use the `actions/upload-artifact` action to upload the session data as an artifact:

```yaml
name: Node CI

on: [push]

env:
  TUIST_XDG_STATE_HOME: /tmp

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
      # ... other steps
      - run: tuist generate
      # ... do something with the project
      - name: Export Tuist session data
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: tuist-sessions
          path: /tmp/tuist/sessions/
```

### Cache daemon debugging {#cache-daemon-debugging}

For debugging cache-related issues, Tuist logs cache daemon operations using `os_log` with the subsystem `dev.tuist.cache`. You can stream these logs in real-time using:

```bash
log stream --predicate 'subsystem == "dev.tuist.cache"' --debug
```

These logs are also visible in Console.app by filtering for the `dev.tuist.cache` subsystem. This provides detailed information about cache operations, which can help diagnose cache upload, download, and communication issues.
