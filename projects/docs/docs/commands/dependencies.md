---
title: tuist fetch
slug: '/commands/dependencies'
description: "Learn how to use Tuist's fetch commands to manage external dependencies."
---

Tuist provides a first-class support for integrating external dependencies into your projects. External dependencies [are declared](guides/third-party-dependencies.md) in a `Tuist/Dependencies.swift` file, and through the commands described in this page you can **fetch, update, and clean** dependencies in your project's directory. Tuist integrates them automatically when generating the Xcode projects.

### Commands

#### Fetching

Dependencies can be fetched by running the following command. They are stored in your project's `Tuist/Dependencies` directory:

```bash
tuist fetch
```

| Argument | Short | Description                                                                                          | Default           | Required |
| -------- | ----- | ---------------------------------------------------------------------------------------------------- | ----------------- | -------- |
| `--path` | `-p`  | The path to the directory that contains the workspace or project whose dependencies will be fetched. | Current directory | No       |

#### Updating

Dependencies can be updated by running the following command:

```bash
tuist fetch --update
```

| Argument | Short | Description                                                                                          | Default           | Required |
| -------- | ----- | ---------------------------------------------------------------------------------------------------- | ----------------- | -------- |
| `--path` | `-p`  | The path to the directory that contains the workspace or project whose dependencies will be updated. | Current directory | No       |

#### Cleaning

Dependencies can be cleaned by running the following command:

```bash
tuist clean dependencies
```

| Argument | Short | Description                                                                                          | Default           | Required |
| -------- | ----- | ---------------------------------------------------------------------------------------------------- | ----------------- | -------- |
| `--path` | `-p`  | The path to the directory that contains the workspace or project whose dependencies will be cleaned. | Current directory | No       |
