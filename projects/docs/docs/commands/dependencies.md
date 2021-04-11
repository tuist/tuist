---
title: Manage third-party dependencies
slug: '/commands/dependencies'
description: "Learn how to use Tuist's dependencies commands to manage third-party dependencies."
---

### Context

Third-party dependencies are represented by another graph. Dependency managers like [CocoaPods](https://cocoapods.org) integrate it when running `pod install` leverating Xcode workspaces, and Swift Package Manager does it at build time leveraging Xcode's closed build system. Both approaches might lead to integration issues that can cause compilation issues down the road. We are aware that's not a great developer experience and thus we take a different approach to managing third party dependencies that allows leverating Tuist features such as linting and caching. The idea is simple, developers define their Carthage and Package dependencies in a `Dependencies.swift` file. They are fetched by running `tuist dependencies fetch` and integrated into the generated Xcode project at generation time. Because we merge your project and the third-party dependencies' graph into a single graph, we validate and fail early if the resulting graph is invalid.

Learn how to get started with `Dependencies.swift` [here](/features/third-party-dependencies/).

:::warning Work in progress
This feature is currently being worked on and is not ready to be used yet.
:::

### Commands

#### Fetching

Dependencies can be fetched by running the following command. They are stored in your project's `Tuist/Dependencies` directory:

```bash
tuist dependencies fetch
```

| Argument | Short | Description                                                                                          | Default           | Required |
| -------- | ----- | ---------------------------------------------------------------------------------------------------- | ----------------- | -------- |
| `--path` | `-p`  | The path to the directory that contains the workspace or project whose dependencies will be fetched. | Current directory | No       |

#### Updating

Dependencies can be updated by running the following command:

```bash
tuist dependencies update
```

| Argument | Short | Description                                                                                          | Default           | Required |
| -------- | ----- | ---------------------------------------------------------------------------------------------------- | ----------------- | -------- |
| `--path` | `-p`  | The path to the directory that contains the workspace or project whose dependencies will be updated. | Current directory | No       |
