---
title: Lint code and project
slug: '/commands/linting'
description: 'Learn how to use the lint command to validate your projects and catch errors before building them with Xcode and enforce Swift style and conventions using SwiftLint.'
---

### Project linting

One of the benefits of making the definition of projects explicit,
is that we can run checks on them and uncover configuration issues that otherwise would be bubbled up by the build system later on.
Tuist follows the principle of the sooner we detect the errors,
the less time developers will have to spend.
For that reason,
we provide a command that developers can run either locally or on CI to ensure their projects have a valid configuration:

```bash
tuist lint project
```

:::note
Please note that there are checks that only the compiler and the build system can do.
In other words,
those will only be uncovered by compiling the app with Xcode or `xcodebuild`.
:::

### Code linting

Tuist provides a command for linting the Swift code of your projects by leveraging [SwiftLint](https://github.com/realm/SwiftLint). All you need to do is run the following command:

```bash
tuist lint code # All the targets
tuist lint code MyTarget
```

You can provide your SwiftLint configuration file by placing it under the root `/Tuist` directory.

### Arguments

| Argument   | Short | Description                                                                                 | Default | Required |
| ---------- | ----- | ------------------------------------------------------------------------------------------- | ------- | -------- |
| `--path`   | `-p`  | The path to the directory that contains the workspace or project whose code will be linted. |         | No       |
| `--strict` | `-s`  | Fails on warnings.                                                                          |         | No       |
