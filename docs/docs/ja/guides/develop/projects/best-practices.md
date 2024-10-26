---
title: ベストプラクティス
titleTemplate: :title | プロジェクト | Tuist
description: Tuist プロジェクトと Xcode プロジェクトのベストプラクティスについて学ぶ
---

# ベストプラクティス {#best-practices}

Over the years working with different teams and projects, we've identified a set of best practices that we recommend following when working with Tuist and Xcode projects. These practices are not mandatory, but they can help you structure your projects in a way that makes them easier to maintain and scale.

## Xcode {#xcode}

### Discouraged patterns {#discouraged-patterns}

#### Configurations to model remote environments {#configurations-to-model-remote-environments}

Many organizations use build configurations to model different remote environments (e.g., `Debug-Production` or `Release-Canary`), but this approach has some downsides:

- **Inconsistencies:** If there are configuration inconsistencies throughout the graph, the build system might end up using the wrong configuration for some targets.
- **Complexity:** Projects can end up with a long list of local configurations and remote environments that are hard to reason about and maintain.

Build configurations were designed to embody different build settings, and projects rarely need more than just `Debug` and `Release`. The need to model different environments can be achieved by using schemes:

- Set a scheme environment variable: `REMOTE_ENV=production`.
- Add a new key to the `Info.plist` of the bundle that will use the environment information (e.g., app bundle): `REMOTE_ENV=${REMOTE_ENV}`.
- You can then read the value at runtime:

  ```swift
  let remoteEnvString = Bundle.main.object(forInfoDictionaryKey: "REMOTE_ENV") as? String
  ```

Thanks to the above, you can keep the list of configurations simple, preventing the aforementioned downsides, and give developers the flexibility to customize things like the remote environment via schemes.
