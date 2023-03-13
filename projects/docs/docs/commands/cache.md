---
title: tuist cache
slug: '/commands/cache'
description: "Learn how to use Tuist's cache command to generate binary artifacts for your targets."
---

Target caching is one of Tuist's distinctive features.
Caching creates binary artifacts of your targets, which can later be used in your project if your generation is focused on other targets.
For more details on the caching workflow, please refer to the [caching](building-at-scale/caching.md) documentation.

### Warm

To generate the cache for all the target of your project, you can simply run:

```bash
tuist cache warm
```

You can even select a subset of targets to be cached, by passing them as command arguments:

```bash
tuist cache warm TargetA TargetB
```

The cached artifacts are stored in the Tuist cache at `~/.tuist/Cache/BuildCache/<target-hash>`.
If a target is already present in the cache, it will not be built again by the command.

### Arguments

| Argument              | Short | Description                                                                                                                    | Default                                         | Required |
| --------------------- | ----- | ------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------- | -------- |
| `--path`              | `-p`  | The path to the directory that contains the definition of the project.                                                         | Current directory                               | No       |
| `--profile`           | `-P`  | The name of the profile to be used when warming up the cache.                                                                  |                                                 | No       |
| `--xcframeworks`      | `-x`  | When passed it builds xcframeworks (simulator and/or device) instead of frameworks (only simulator).                           | False                                           | No       |
| `--destination`       | `N/A` | Output type of xcframeworks when `--xcframeworks` is passed (device/simulator)                                                 | Both device and simulator                       | No       |
| `--dependencies-only` | `N/A` | If passed, the command caches only the dependencies of the list of targets passed to the cache command.                        | False                                           | No       |
| No argument           |       | A list of targets to cache. Those and their dependent targets will be cached. If empty, every cacheable target will be cached. | Empty list, which means project defined targets | No       |

### Print hashes

Targets are uniquely identified in the cache. The identifier (hash) is obtained by hashing the attributes of the target, its project,
the environment (e.g. Tuist version) and the hashes of its dependencies.
To facilitate debugging, Tuist exposes a command that prints the hash of every target of the dependency tree:

```bash
tuist cache print-hashes
```

### Arguments

| Argument              | Short | Description                                                                                                       | Default               | Required |
| --------------------- | ----- | ----------------------------------------------------------------------------------------------------------------- | -----------------     | -------- |
| `--path`              | `-p`  | The path to the directory that contains the definition of the project.                                            | Current directory     | No       |
| `--profile`           | `-P`  | The name of the profile to be used when warming up the cache.                                                     |                       | No       |
| `--xcframeworks`      | `-x`  | When passed it builds xcframeworks (simulator and device) instead of frameworks (only simulator).                 | False                 | No       |
| `--destination`       | `N/A` | Output type of xcframeworks when `--xcframeworks` is passed (device/simulator)                                    |                       | No       |
