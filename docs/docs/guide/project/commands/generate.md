---
title: Generate
description: Learn how to generate projects and workspaces with Tuist
---

# Generate

Project generation is the core feature of Tuist upon which all other features are built. Once the project is defined following the [directory structure](/guide/project/directory-structure) and manifest files, you can generate the project using the `tuist generate` command. This command reads the manifest files, generates the Xcode projects and workspace, writes it to the disk, and opens it in Xcode.

> [!NOTE] WORKSPACE GENERATION
> Tuist always generates a workspace, even if you have a single `Project.swift`. This is by design to ensure that the project is always generated in a consistent way.

## Generating a project

To generate a project, you can use the `tuist generate` command. This command will read the manifest files, generate the Xcode projects and workspace, write them to the disk, and open them in Xcode.

::: code-group
```bash [Generate and open]
tuist generate
```

```bash [Generate without opening]
tuist generate --no-open
```

```bash [Generate without cache binaries]
tuist generate --no-binary-cache
```
:::