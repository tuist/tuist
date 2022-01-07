---
title: Focus on targets
slug: '/commands/focus'
description: 'Learn how to generate projects with the focus on specific targets removing the unnecessary targets and schemes, and replacing direct and transitive dependencies with pre-compiled targets from the cache.'
---

### Context

In large Xcode projects that contain many targets and schemes, Xcode can be slow indexing the project.
Moreover, the build system, which needs to resolve implicit dependencies, might take longer to do so because there are more Xcode objects to analyze.
This is **not ideal for developers' productivity** and for that reason Tuist includes a command that allows users to focus on a specific target or set of targets.

```bash
tuist focus MyApp
```

The command generates and opens an Xcode workspace where the targets and schemes that are not directly related to `MyApp` are removed.
Moreover, if the direct and transitive dependencies exist in the [cache](building-at-scale/caching.md),
Tuist replaces them with their pre-compiled version.
Thanks to that developers can safely clean their Xcode environment because they'll only be building the target they are focusing on.

### Arguments

| Argument          | Short | Description                                                                                                    | Default           | Required |
| ----------------- | ----- | -------------------------------------------------------------------------------------------------------------- | ----------------- | -------- |
| `--path `         | `-p`  | The path to the directory that contains the manifest file.                                                     | Current directory | No       |
| `--no-open `      | `-n`  | Don't open the project after generating it.                                                                    | False             | No       |
| `--xcframeworks ` | `-x`  | When passed it uses xcframeworks (simulator and device) from the cache instead of frameworks (only simulator). |                   | No       |
| `--no-cache `     | `-x`  | Ignore cached targets, and use their sources instead.                                                          | False             | No       |
| `--profile `      | `-P`  | The name of the cache profile.                                                                                 |                   | No       |
