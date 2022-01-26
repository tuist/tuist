---
title: tuist migration
slug: '/commands/migration'
description: 'Learn how to use the migration commands to smooth the adoption of Tuist from your projects.'
---

To help developers with the process of [adopting Tuist](guides/adopting-tuist.md),
Tuist provides a set of commands under `tuist migration`.

### Extract build settings into xcode build configuration files

It's recommended to make `.xcconfig` files the source of truth for build settings.
For that, Tuist provides a `tuist migration settings-to-xcconfig` command that extracts the build settings from targets and projects.

```bash
# Extract target build settings
tuist migration settings-to-xcconfig -p Project.xcodeproj -t MyApp -x MyApp.xcconfig

# Extract project build settings
tuist migration settings-to-xcconfig -p Project.xcodeproj -x MyAppProject.xcconfig
```

#### Arguments

| Argument           | Short | Description                                                                                                                    | Default | Required |
| ------------------ | ----- | ------------------------------------------------------------------------------------------------------------------------------ | ------- | -------- |
| `--xcodeproj-path` | `-p`  | Path to the Xcode project whose build settings will be extracted.                                                              |         | Yes      |
| `--xcconfig-path`  | `-x`  | Path to the .xcconfig file into which the build settings will be extracted.                                                    |         | Yes      |
| `--target`         | `-t`  | The name of the target whose build settings will be extracted. When not passed, it extracts the build settings of the project. |         | No       |

### Ensure project and target build settings are empty

After making `.xcconfig` files the source of truth for build settings,
it's important to ensure that build settings are no longer set to the project.
To help with that, Tuist includes a command that fails if the build settings of a project or a target are not empty:

```bash
tuist migration check-empty-settings -p Project.xcodeproj -t MyApp
```

##### Arguments

| Argument           | Short | Description                                                                                                                | Default | Required |
| ------------------ | ----- | -------------------------------------------------------------------------------------------------------------------------- | ------- | -------- |
| `--xcodeproj-path` | `-p`  | Path to the Xcode project whose build settings will be checked.                                                            |         | Yes      |
| `--target`         | `-t`  | The name of the target whose build settings will be checked. When not passed, it checks the build settings of the project. |         | No       |

### List targets sorted by topological order

Migration of big Xcode projects to Tuist can happen iteratively, one target at a time.
To help with that, Tuist includes a command that lists the targets of a project sorted by topological order, suggesting which target to resolve first.

```bash
tuist migration list-targets -p Project.xcodeproj
```

##### Arguments

| Argument           | Short | Description                                                     | Default | Required |
| ------------------ | ----- | --------------------------------------------------------------- | ------- | -------- |
| `--xcodeproj-path` | `-p`  | Path to the Xcode project whose build settings will be checked. |         | Yes      |
