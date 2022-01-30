---
title: Caching
slug: '/building-at-scale/caching'
description: 'Learn how to use caching of targets to speed up build times in your projects.'
---

Tuist has support for caching a pre-compiled version of your project targets locally and remotely.
When targets are cached, developers can generate projects where the targets they don't plan to work on are replaced with their pre-compiled version.
In modular apps, this feature yields significant improvements in build times.

Unlike [Bazel](https://bazel.build/) or [Buck](https://buck.build/) that replace Xcode's build system to cache individual build steps,
we do caching at the module level. That means developers can use Xcode and its build system and don't have to develop tooling around alternative build systems to integrate them with developers tooling.

![An image that shows how the caching feature works](./assets/cache.png)

### Warming the cache

Warming the cache is the process of building, hashing, and storing cacheable targets in the cache.
We recommend setting up a continuous integration pipeline that runs on every main branch commit and executes the [cache](commands/cache.md) command:

```bash
tuist cache warm
```

To warm the cache with only specific targets and their dependencies, you can run:

```bash
tuist cache warm FrameworkA FrameworkB
```

To warm the cache with only targets not defined in your project or workspace (for example, external dependencies), you can run:

```bash
tuist cache warm --dependencies-only
```

### Using cached artifacts

Once the cache is warmed, you can use the [generate](commands/generate.md) command to generate a project, replacing external dependencies with artifacts from the cache:

```bash
tuist generate
```

Or you can specify the list of targets you are interested in, so that all other targets are replaced with binary artifacts

```bash
tuist generate FrameworkA FrameworkB
```

If you need to use the app on a real device, remember to pass the `--xcframeworks` argument to both `tuist cache warm` and `tuist generate`.

### External dependencies and cache

In general, developers do not need to view the source code of their [external dependencies](guides/dependencies.md). To import them as binaries:

1. Fetch the dependencies

```bash
tuist fetch
```

2. Build their cache if needed

```bash
tuist cache warm --dependencies-only
```

3. Generate the project, using binary artifacts for external dependencies

```bash
tuist generate
```

#### Caching profile

The caching profile allows users to specify how targets will be cached, for example setting a configuration. Instead of passing the configuration through CLI arguments, developers can define a profile and reference it with `tuist cache warm --profile MyProfile`.
You can define a caching profile in `Config.swift`, for example:

```swift
let config = Config(
    cache: .cache(profiles: [
        .profile(name: "Simulator", configuration: "Debug")
    ])
)
```

Additionally, you can specify a device and OS in a caching profile: 

```swift
let config = Config(
    cache: .cache(profiles: [
        .profile(name: "Simulator", configuration: "Debug", device: "iPhone 11 Pro", os: "15.0")
    ])
)
```

You can change the cache directory in `Config.swift`, for example:

```
let config = Config(cache: .cache(path: .relativeToRoot("Cache"))]))
```

### Debugging

#### Print target hashes

Targets are uniquely identified in the cache. The identifier (hash) is obtained by hashing the attributes of the target, its project,
the environment (e.g. Tuist version) and the hashes of its dependencies.
To facilitate debugging, Tuist exposes a command that prints the hash of every target of the dependency tree:

```
tuist cache print-hashes
```

### Unsupported configurations

- **Dynamic Swift Packages and packages with modulemaps if not imported via Dependencies.swift:** Due to the approach that Xcode follows for integrating Swift packages, Tuist doesn't have enough details about the SPM dependency graph, and can't ensure the generated project is valid. If you try, you'll likely get `module not found` errors.
