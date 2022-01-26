---
title: tuist build
slug: '/commands/build'
description: 'Learn how to build your Tuist projects by simply using the build command that is optimized for minimal configuration.'
---

Traditionally,
teams have resorted to scripts and programmable DSLs to define a command line interface to interact with their projects.
At scale,
that approach results in complex, error-prone, untested, and hard to reason about automation code.
It's not the tools' fault though;
small teams don't have enough resources to keep tooling in a good shape and end up disregarding the quality of the automation code.
This often leads to frustration:
_release pipelines failing because of signing issues, unreproducible issues on CI, or non-deterministic results across environments._

**What if Tuist could take care of automation for you?**
That's what commands like build are for.
Tuist takes advantage of knowing the structure of your project, that is described in the manifest files.
Using this information, Tuist can offer simple and streamlined workflows that are standard across all projects.
And because Tuist owns those workflows,
it can optimize them without you having to do anything on your end.

> Manifest files become the source of truth for both,
> editing the projects in Xcode,
> and interacting with them from the terminal.

### Command

Build is designed for zero-arguments.
If it's executed without passing any arguments,
we assume the intent of the developer is to build the project in the current directory, and we infer the arguments from there:

**Build the project in the current directory**

```bash
tuist build
```

**Build a scheme**

```bash
tuist build MyScheme
```

:::note Standard commands
One of the benefits of using Tuist over other automation tools is that developers can get familiar with a set of commands that they can use in any Tuist project.
:::

#### Customizing builds

Sometimes for CI or when creating automations you may like to customize the build more. 

**Build the project to a custom directory**

`tuist build --build-output-path .build`

