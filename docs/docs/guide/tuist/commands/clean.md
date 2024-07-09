---
title: tuist clean
description: "'tuist clean' is a command to clean local and global caches managed by Tuist."
---

# Clean

Tuist relies on project-scoped and global caches to speed up some of its workflows. If for any reason you want to clean these caches, you can use the `tuist clean` command. When no argument is passed, the command cleans all the cache categories. Otherwise, you can pass the cache category you want to clean.

## Usage

You can pass one or multiple categories to the `tuist clean` command. For example, to clean the `binaries` and `plugins` categories, you can run:

::: code-group
```bash [Clean plugins and binaries]
tuist clean plugins binaries
```
:::

### Categories

The following are the categories of caches that Tuist manages:

| Category | Content | Scope |
| ---- | ---- | ---- |
| `binaries` | Local [cache](/guide/cache) binaries | Global |
| `selectiveTests` | Local [smart runner](/guide/tests/smart-runner) cache | Global |
| `plugins` | Pre-compiled plugins | Global |
| `generatedAutomationProjects` | Projects generated for automation tasks like `build` | Global |
| `projectDescriptionHelpers` | Pre-compiled modules for [project description helpers](/guide/project/code-sharing) | Global |
| `manifests` |  JSON-serialized manifest files to speed up project generation | Global | 
| `dependencies` | Dependencies fetched by Tuist | Project |