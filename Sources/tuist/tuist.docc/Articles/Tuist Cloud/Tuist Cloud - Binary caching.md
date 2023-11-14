# Binary Caching

Speeding up your clean build and test runs across environments

## Overview

Xcode's build system is designed for incremental builds, enhancing efficiency under normal circumstances. However, this feature falls short in Continuous Integration (CI) environments, where data essential for incremental builds is not shared across different builds. Additionally, developers often reset this data locally to troubleshoot complex compilation problems, leading to more frequent clean builds. This results in teams spending excessive time waiting for local builds to finish or for Continuous Integration pipelines to provide feedback on pull requests. Furthermore, the frequent context switching in such an environment compounds this unproductiveness.

Tuist addresses these challenges effectively with its binary caching feature. This tool optimizes the build process by caching compiled binaries, significantly reducing build times both in local development and CI environments. This approach not only accelerates feedback loops but also minimizes the need for context switching, ultimately boosting productivity.

### Cache warming

Tuist efficiently utilizes **fingerprints** for each target in the dependency graph to detect changes. Utilizing this data, it builds and assigns unique identifiers to binaries derived from these targets. At the time of graph generation, Tuist then seamlessly substitutes the original targets with their corresponding binary versions.

This operation, known as *"warming,"* produces binaries for local use or for sharing with teammates and CI environments via Tuist Cloud. The process of warming the cache is straightforward and can be initiated with a simple command:


```bash
tuist cache warm
```

### Using the cache binaries

By default, when Tuist commands necessitate project generation, they automatically substitute dependencies with their binary equivalents from the cache, if available. Additionally, if you specify a list of targets to focus on, Tuist will also replace any dependent targets with their cached binaries, provided they are available. For those who prefer a different approach, there is an option to opt out of this behavior entirely by using a specific flag:

```bash
tuist generate # Only dependencies
tuist generate Search # Dependencies + Search dependencies
tuist generate Search Settings # Dependencies, and Search and Settings dependencies
tuist generate --no-cache # No cache at all
```

### Sharing binaries across environments

To facilitate the sharing of binaries across different environments, you'll require a [Tuist Cloud](https://tuist.io/cloud) account and a designated project. You have the option to create this project directly under your personal account, or alternatively, you can establish an organization. Creating an organization allows you to invite your team members to collaborate within a unified framework:

```bash
tuist cloud auth # Authenticate
tuist cloud organization create my-organization # Create organization
tuist cloud project create my-project -o my-organization # Create a project
```

After creating the project, modify your `Tuist/Config.swift` file to reference the new project:

```swift
import ProjectDescription

let config = Config(cloud: .cloud(projectId: "my-organization/my-project"))
```

Developers on your team can access the cache if they are authenticated and added as members of the organization, which you can do using the Tuist CLI. For CI environments, authentication is managed differently; it's done using **project-scoped tokens**. These tokens possess restricted permissions compared to those of the organization, including the ability to warm the cache with binaries. To obtain this token, you can execute the following command:


```swift
tuist cloud project token my-project -o my-organization
```

You will then need to set the token as an environment variable named `TUIST_CONFIG_CLOUD_TOKEN` to make it accessible.

> Tip: While utilizing the cache for release builds is feasible, we advise restricting binary usage to debug builds only. This approach ensures absolute certainty that the compiled code corresponds exactly to the version intended for release.

