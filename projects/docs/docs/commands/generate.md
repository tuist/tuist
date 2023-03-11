---
title: tuist generate
slug: '/commands/generate'
description: "Learn how to use one of Tuist's core features, the generation of projects."
---

Project generation is one of Tuist's core features.
It loads your project's dependency graph by reading the manifest files _(e.g. Project.swift, Workspace.swift)_, and translates it into
Xcode projects and workspaces.
You can think of manifest files as an simple and approachable abstraction of Xcode projects' intricacies,
and Xcode projects and workspaces as a implementation detail to edit your project's code.

### Command

To generate the project in the current directory, you can simply run:

```bash
tuist generate
```

Moreover, if external dependencies exist in the [cache](building-at-scale/caching.md), Tuist replaces them with their pre-compiled version.

In large Xcode projects that contain many targets and schemes, Xcode can be slow indexing the project.
The build system, which needs to resolve implicit dependencies, might take longer to do so because there are more Xcode objects to analyze.
This is **not ideal for developers' productivity** and for that reason Tuist allows users to focus on a specific target or set of targets.

```bash
tuist generate MyApp
```

The command generates and opens an Xcode workspace where the targets and schemes not directly related to `MyApp` are removed.
If the direct and transitive dependencies exist in the [cache](building-at-scale/caching.md), Tuist replaces them with their pre-compiled version.
Thanks to that developers can safely clean their Xcode environment because they'll only be building the target they are focusing on.

### Arguments

| Argument          | Short | Description                                                                                                    | Default           | Required |
| ----------------- | ----- | -------------------------------------------------------------------------------------------------------------- | ----------------- | -------- |
| `--path`          | `-p`  | The path to the directory that contains the definition of the project.                                         | Current directory | No       |
| `--no-open `      | `-n`  | Don't open the project after generating it.                                                                    | False             | No       |
| `--xcframeworks ` | `-x`  | When passed it uses xcframeworks (simulator and device) from the cache instead of frameworks (only simulator). | False             | No       |
| `--destination`   | `N/A` | Type of cached xcframeworks to use when `--xcframeworks` is passed (device/simulator)                          |               | No       |
| `--no-cache `     | `-x`  | Ignore cached targets, and use their sources instead.                                                          | False             | No       |
| `--profile `      | `-P`  | The name of the cache profile.                                                                                 |                   | No       |
