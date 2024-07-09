---
title: tuist generate
description: "'tuist benerate' is a command to generate Xcode projects and workspaces to work with Tuist projects in Xcode."
---

# Generate

### Supported platforms

| Platform | Available |
|----- | ----- |
| Apple (Native) | This command is designed for the Apple platform whose build system doesn't provide the extensibility required to support the features Tuist offers. |

---

When using [Tuist Projects](/guide/project) to define your Xcode projects, you need to generate Xcode projects and workspaces to work with them in Xcode. Once the project is defined following the [directory structure](/guide/project/directory-structure) and manifest files, you can generate the project using the `tuist generate` command. This command reads the manifest files, generates the Xcode projects and workspace, writes it to the disk, and opens it in Xcode.

> [!NOTE] WORKSPACE GENERATION
> Tuist always generates a workspace, even if you have a single `Project.swift`. This is by design to ensure that the project is always generated in a consistent way.

## Usage

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