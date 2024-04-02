---
title: Graph
description: Tuist provides a command to output and visualize a project graph
---

# Graph

One of the advantages of extracting the project graph from from its implicitly codified form in Xcode projects and workspaces, is that Tuist knows it ahead of time and can provides useful features to developers. One of those features is the ability to export and visualize the graph through the `tuist graph` command.

## Graph image

By default, `tuist graph` outputs and opens the image `graph.png` at the root of the project:

::: code-group
```bash [Opening it]
tuist graph
```
```bash [Without opening it]
tuist graph --no-open
```
```bash [In a different directory]
tuist graph --output-path /tmp/graphs
```
:::

## Algorithms and formats

When the dependency graph is large, the generated image might be hard to visually parse.
In those scenarios, we recommend playing with other formats and algorithms and using interactive tools to work with them:

- **Formats:** `.dot`, `.json`, `.png`, and `.svg`
- **Algorithms:** `dot`, `neato`, `twoapi`, `circo`, `fdp`, `sfdp`, and `patchwork`.

## Filtering <Badge type="warning" text="Needs improvement" />

You can use some flags to filter nodes from the graph:

- `--skip-test-targets`: Skip Test targets during graph rendering.
- `--skip-external-dependencies`  Skip external dependencies.
- `--platform`:  A platform to filter. Only targets for this platform will be showed in the graph. Available platforms: `ios`, `macos`, `tvos`, `watchos`

> [!NOTE] PLANNED IMPROVEMENTS
> The filtering options are not flexible enough and can grow into an incosistent filtering interface. We are aware of that and we have plans to come up with a language that's universal across various commands.