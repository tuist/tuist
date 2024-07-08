---
title: Clean
description: Tuist provides a command to clean global caches and local caches
---

# Clean

Tuist relies on project-scoped and global caches to speed up some of its workflows. If for any reason you want to clean these caches, you can use the `tuist clean` command. When no argument is passed, the command cleans all the cache categories. Otherwise, you can pass the cache category you want to clean.

## Categories

The following are the categories of caches that Tuist manages:

| Category | Content | Scope |
| ---- | ---- | ---- |
| `binaries` | Binaries for [Tuist Cloud binary cache](/cloud/binary-caching) | Global |
| `selectiveTests` | State for [Tuist Cloud selective tests cache](/cloud/selective-testing) | Global |
| `plugins` | Pre-compiled plugins | Global |
| `generatedAutomationProjects` | Projects generated for automation tasks like `build` | Global |
| `projectDescriptionHelpers` | Pre-compiled modules for project description helpers | Global |
| `manifests` |  JSON-serialized manifest files to speed up project generation | Global | 
| `dependencies` | SPM dependencies fetched by Tuist | Project |

You can pass one or multiple categories to the `tuist clean` command. For example, to clean the `binaries` and `plugins` categories, you can run:

::: code-group
```bash [Clean plugins and binaries]
tuist clean plugins binaries
```
:::