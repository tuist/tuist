---
{
  "title": "Directories",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Learn how Tuist organizes its configuration, cache, and state directories."
}
---
# Directories {#directories}

Tuist organizes its files across several directories on your system, following the [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html). This provides a clean, standard way to manage configuration, cache, and state files.

## Supported environment variables {#supported-environment-variables}

Tuist supports both standard XDG variables and Tuist-specific prefixed variants. The Tuist-specific variants (prefixed with `TUIST_`) take precedence, allowing you to configure Tuist separately from other applications.

### Configuration directory {#configuration-directory}

**Environment variables:**
- `TUIST_XDG_CONFIG_HOME` (takes precedence)
- `XDG_CONFIG_HOME`

**Default:** `~/.config/tuist`

**Used for:**
- Server credentials (`credentials/{host}.json`)

**Example:**
```bash
# Set Tuist-specific config directory
export TUIST_XDG_CONFIG_HOME=/custom/config
tuist auth login

# Or use standard XDG variable
export XDG_CONFIG_HOME=/custom/config
tuist auth login
```

### Cache directory {#cache-directory}

**Environment variables:**
- `TUIST_XDG_CACHE_HOME` (takes precedence)
- `XDG_CACHE_HOME`

**Default:** `~/.cache/tuist`

**Used for:**
- **Plugins**: Downloaded and compiled plugin cache
- **ProjectDescriptionHelpers**: Compiled project description helpers
- **Manifests**: Cached manifest files
- **Projects**: Generated automation project cache
- **EditProjects**: Cache for edit command
- **Runs**: Test and build run analytics data
- **Binaries**: Build artifact binaries (not shareable across environments)
- **SelectiveTests**: Selective testing cache

**Example:**
```bash
# Set Tuist-specific cache directory
export TUIST_XDG_CACHE_HOME=/tmp/tuist-cache
tuist cache

# Or use standard XDG variable
export XDG_CACHE_HOME=/tmp/cache
tuist cache
```

### State directory {#state-directory}

**Environment variables:**
- `TUIST_XDG_STATE_HOME` (takes precedence)
- `XDG_STATE_HOME`

**Default:** `~/.local/state/tuist`

**Used for:**
- **Logs**: Log files (`logs/{uuid}.log`)
- **Locks**: Authentication lock files (`{handle}.sock`)

**Example:**
```bash
# Set Tuist-specific state directory
export TUIST_XDG_STATE_HOME=/var/log/tuist
tuist generate

# Or use standard XDG variable
export XDG_STATE_HOME=/var/log
tuist generate
```

## Precedence order {#precedence-order}

When determining which directory to use, Tuist checks environment variables in the following order:

1. **Tuist-specific variable** (e.g., `TUIST_XDG_CONFIG_HOME`)
2. **Standard XDG variable** (e.g., `XDG_CONFIG_HOME`)
3. **Default location** (e.g., `~/.config/tuist`)

This allows you to:
- Use standard XDG variables to organize all your applications consistently
- Override with Tuist-specific variables when you need different locations for Tuist
- Rely on sensible defaults without any configuration

## Common use cases {#common-use-cases}

### Isolating Tuist per project {#isolating-tuist-per-project}

You might want to isolate Tuist's cache and state per project:

```bash
# In your project's .envrc (using direnv)
export TUIST_XDG_CACHE_HOME="$PWD/.tuist/cache"
export TUIST_XDG_STATE_HOME="$PWD/.tuist/state"
export TUIST_XDG_CONFIG_HOME="$PWD/.tuist/config"
```

### CI/CD environments {#ci-cd-environments}

In CI environments, you might want to use temporary directories:

```yaml
# GitHub Actions example
env:
  TUIST_XDG_CACHE_HOME: /tmp/tuist-cache
  TUIST_XDG_STATE_HOME: /tmp/tuist-state

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - run: tuist generate
      - name: Upload logs
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: tuist-logs
          path: /tmp/tuist-state/logs/*.log
```

### Debugging with isolated directories {#debugging-with-isolated-directories}

When debugging issues, you might want a clean slate:

```bash
# Create temporary directories for debugging
export TUIST_XDG_CACHE_HOME=$(mktemp -d)
export TUIST_XDG_STATE_HOME=$(mktemp -d)
export TUIST_XDG_CONFIG_HOME=$(mktemp -d)

# Run Tuist commands
tuist generate

# Clean up when done
rm -rf $TUIST_XDG_CACHE_HOME $TUIST_XDG_STATE_HOME $TUIST_XDG_CONFIG_HOME
```
