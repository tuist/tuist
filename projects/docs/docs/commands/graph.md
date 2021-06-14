---
title: Generate project graph
slug: '/commands/graph'
description: "Learn how to use the graph command to get a visual representation of your project's dependency graph"
---

### Graph

When projects grow, it becomes hard to visualize the dependencies between all the targets that are part of the project.
Fortunately, Tuist provides a command, `tuist graph`, that loads your project dependencies graph and exports it. As the
saying goes, "one image is worth a thousand words":

![Sample graph exported with the graph command](assets/GraphExample.png)

The command will output the dependency graph as an image, in the `png` format.
You can also change the format to `dot` (see [DOT](<https://en.wikipedia.org/wiki/DOT_(graph_description_language)>))
to get the raw contents of the graph.

### Command

Run the following command from a directory that contains a workspace or project manifest:

```bash
tuist graph
```

If you prefer to have the dot representation of the graph and render it separately, you can run:

```bash
tuist graph --format dot
```

To show the graph of only specific targets and their dependencies, you can run:

```
tuist graph FrameworkA FrameworkB
```

#### Legend

The graph command will style every type of target or dependency differently. This makes it easier to understand
and visualize the graph. App targets, swift packages, frameworks, and all other types will have different shapes and colors.
To better understand what which one means, you can use the following legend as a reference.

![Legend: different types of dependencies and targets and their styles in the graph](assets/Legend.png)

If you prefer the old style, without different colors and shapes, pass the `--simple` flag when creating the graph.

#### Arguments

| Argument                       | Short | Description                                                                                                      | Values                                                                                                                             | Default           | Required |
| ------------------------------ | ----- | ---------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- | ----------------- | -------- |
| `--skip-test-targets`          | `-t`  | Excludes test targets from the generated graph.                                                                  |                                                                                                                                    |                   | No       |
| `--skip-external-dependencies` | `-d`  | Excludes external dependencies from the generated graph.                                                         |                                                                                                                                    |                   | No       |
| `--format`                     | `-f`  | The format of the generated graph.                                                                               | `dot`, `png`                                                                                                                       | `png`             | No       |
| `--simple`                     | `-s`  | Simple graph: disable different shapes and colors.                                                               |                                                                                                                                    |                   | No       |
| `--algorithm`                  | `-a`  | The algorithm used for drawing the graph. For large graphs, it's recommended to use `fdp`.                       | `dot`, `neato`, `twopi`, `circo`, `fdp`, `sfdp`, `patchwork`                                                                       | `dot`             | No       |
| `--path`                       | `-p`  | The path to the directory that contains the definition of the project.                                           |                                                                                                                                    | Current directory | No       |
| `--output-path`                | `-o`  | The path to where the image will be exported. When not specified, it exports the image in the current directory. |                                                                                                                                    |                   | No       |
| `--targets`                    | `-t`  | The path to where the image will be exported. When not specified, it exports the image in the current directory. | A list of targets to filter. Those and their dependent targets will be showed in the graph. If empty, every target will be showed. |                   | No       |
