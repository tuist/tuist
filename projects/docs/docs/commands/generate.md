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

To generate the project in the current directory, youn can simply run:

```
tuist generate
```

The command accepts the `--path` argument, which can be used to generate the project in a different directory.

There might be situations when you are only interested in generating the project in a given directory, and not the projects it depends on. For that, you can pass the argument `--project-only`.

### Arguments

| Argument         | Short | Description                                                            | Default           | Required |
| ---------------- | ----- | ---------------------------------------------------------------------- | ----------------- | -------- |
| `--path`         | `-p`  | The path to the directory that contains the definition of the project. | Current directory | No       |
| `--project-only` | `-P`  | Only generate the local project (without generating its dependencies). | False             | No       |
| `--open`         | `-o`  | Open the project after generating it.                                  | False             | No       |
