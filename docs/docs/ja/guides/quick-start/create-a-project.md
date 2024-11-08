---
title: プロジェクトの作成
titleTemplate: :title · クイックスタート · ガイド · Tuist
description: Tuistで最初のプロジェクトを作成する方法を学びます
---

# プロジェクトの作成 {#create-a-project}

Tuistをインストールしたら、次のコマンドを実行することで新しいプロジェクトを作成できます。

```bash
mkdir MyApp
cd MyApp
tuist init --name MyApp
```

By default it creates a project that represents an **iOS application.** The project directory will contain a `Project.swift`, which describes the project, a `Tuist.swift`, which contains project-scoped Tuist configuration, and a `MyApp/` directory, which contains the source code of the application.

Xcodeで作業するには、次のコマンドを実行してXcodeプロジェクトを生成できます。

```bash
tuist generate
```

Xcodeプロジェクトは直接開いて編集できますが、Tuistプロジェクトはマニフェストファイルから生成されます。  そのため、生成されたXcodeプロジェクトを直接編集しないでください。 そのため、生成されたXcodeプロジェクトを直接編集しないでください。 そのため、生成されたXcodeプロジェクトを直接編集しないでください。 そのため、生成されたXcodeプロジェクトを直接編集しないでください。

> [!TIP] コンフリクトのないユーザーフレンドリーな体験
> Xcodeプロジェクトはコンフリクトが発生しやすく、ユーザーにとって多くの複雑さを伴います。 Tuistはこれらを抽象化し、特にプロジェクトの依存関係グラフの管理において簡素化します。 Tuistはこれらを抽象化し、特にプロジェクトの依存関係グラフの管理において簡素化します。 Tuistはこれらを抽象化し、特にプロジェクトの依存関係グラフの管理において簡素化します。

## アプリのビルド {#build-the-app}

Tuistは、プロジェクトで必要となる最も一般的なタスクのためのコマンドを提供します。 アプリをビルドするには、次のコマンドを実行します。 アプリをビルドするには、次のコマンドを実行します。 アプリをビルドするには、次のコマンドを実行します。 アプリをビルドするには、次のコマンドを実行します。

```bash
tuist build
```

このコマンドは、プラットフォームのビルドシステム (例: `xcodebuild`) を使用し、Tuistの機能で拡張されています。

## アプリのテスト {#test-the-app}

同様に、テストを実行するには次のコマンドを使用します。

```bash
tuist test
```

`build` コマンドと同様に、`test` はプラットフォームのテストランナー (例: `xcodebuild test`) を使用しますが、Tuistのテスト機能と最適化の利点が加わります。

> [!TIP] 基盤となるビルドシステムへの引数の渡し方
> `build` と `test` は、`--` の後に追加の引数を受け取ることができ、これらは基盤となるビルドシステムに渡されます。
