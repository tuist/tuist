# Binary Caching

Speeding up your clean build and test runs across environments

## Overview

Xcode's build system is designed for incremental builds, enhancing efficiency under normal circumstances. However, this feature falls short in Continuous Integration (CI) environments, where data essential for incremental builds is not shared across different builds. Additionally, developers often reset this data locally to troubleshoot complex compilation problems, leading to more frequent clean builds. This results in teams spending excessive time waiting for local builds to finish or for Continuous Integration pipelines to provide feedback on pull requests. Furthermore, the frequent context switching in such an environment compounds this unproductiveness.

Tuist addresses these challenges effectively with its binary caching feature. This tool optimizes the build process by caching compiled binaries, significantly reducing build times both in local development and CI environments. This approach not only accelerates feedback loops but also minimizes the need for context switching, ultimately boosting productivity.

### Cache warming

Tuist efficiently utilizes **hashes** for each target in the dependency graph to detect changes. Utilizing this data, it builds and assigns unique identifiers to binaries derived from these targets. At the time of graph generation, Tuist then seamlessly substitutes the original targets with their corresponding binary versions.

This operation, known as *"warming,"* produces binaries for local use or for sharing with teammates and CI environments via Tuist Cloud. The process of warming the cache is straightforward and can be initiated with a simple command:


```bash
tuist cache
```

The command re-uses binaries to speed up the process.

> Tip: We recommend setting up a CI pipeline exclusively to keep the cache warmed. That way developers in your team will have access to those binaries, thereby reducing their local build times.

### Using the cache binaries

By default, when Tuist commands necessitate project generation, they automatically substitute dependencies with their binary equivalents from the cache, if available. Additionally, if you specify a list of targets to focus on, Tuist will also replace any dependent targets with their cached binaries, provided they are available. For those who prefer a different approach, there is an option to opt out of this behavior entirely by using a specific flag:

```bash
# Generating projects
tuist generate # Only dependencies
tuist generate Search # Dependencies + Search dependencies
tuist generate Search Settings # Dependencies, and Search and Settings dependencies
tuist generate --no-binary-cache # No cache at all

# Testing projects
tuist test
```

> Warning: Binary caching is a feature designed for development workflows such as running the app on a simulator or device, or running tests. It is not intended for release builds. When archiving the app, generate a project with the sources by using the `--no-binary-cache` flag.
