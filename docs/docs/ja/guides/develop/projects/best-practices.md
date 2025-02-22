---
title: ベストプラクティス
titleTemplate: :title · Projects · Develop · Guides · Tuist
description: Tuist プロジェクトと Xcode プロジェクトのベストプラクティスについて学ぶ
---

# ベストプラクティス {#best-practices}

Over the years working with different teams and projects, we've identified a set of best practices that we recommend following when working with Tuist and Xcode projects. These practices are not mandatory, but they can help you structure your projects in a way that makes them easier to maintain and scale.

## Xcode {#xcode}

### 避けるべきパターン {#discouraged-patterns}

#### リモート環境をモデル化するための設定 {#configurations-to-model-remote-environments}

多くの組織は、異なるリモート環境（例: Debug-Production や Release-Canary）をモデル化するためにビルド設定を使用しますが、このアプローチにはいくつかの欠点があります：

- **Inconsistencies:** If there are configuration inconsistencies throughout the graph, the build system might end up using the wrong configuration for some targets.
- **Complexity:** Projects can end up with a long list of local configurations and remote environments that are hard to reason about and maintain.

Build configurations were designed to embody different build settings, and projects rarely need more than just `Debug` and `Release`. The need to model different environments can be achieved by using schemes:

- **In Debug builds:** You can include all the configurations that should be accessible in development in the app (e.g. endpoints), and switch them at runtime. The switch can happen either using scheme launch environment variables, or with a UI within the app.
- **In Release builds:** In case of release, you can only include the configuration that the release build is bound to, and not include the runtime logic for switching configurations by using compiler directives.
