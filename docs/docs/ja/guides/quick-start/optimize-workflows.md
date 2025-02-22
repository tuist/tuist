---
title: ワークフローの最適化
titleTemplate: :title · クイックスタート · ガイド · Tuist
description: Tuistを使用してワークフローを最適化する方法を学びます。
---

# ワークフローの最適化 {#optimize-workflows}

Tuistはプロジェクトの説明と収集したインサイトを通じてあなたのプロジェクトを理解しているため、ワークフローを最適化してより効率的にすることができます。 いくつかの例を見てみましょう。

## スマートテスト実行 {#smart-test-runs}

再度 `tuist test` を実行してみましょう。 次のメッセージに気づくでしょう： 次のメッセージに気づくでしょう：

```bash
There are no tests to run, finishing early
```

Tuistは前回テストを実行してからプロジェクトに変更がないことを検出し、したがってテストを再実行する必要がないと判断しました。 そして、最も良い点は、これが異なるマシンやCI環境でも機能することです。

## キャッシュ {#cache}

プロジェクトをクリーンビルドする場合、通常はCI環境や不可解なコンパイルエラーを解決するためにグローバルキャッシュをクリアした後に、プロジェクト全体を最初からコンパイルし直さなければなりません。 プロジェクトが大きくなると、これには長い時間がかかることがあります。

Tuistは、以前のビルドからバイナリを再利用することでこれを解決します。 次のコマンドを実行してください：

```bash
tuist cache
```

このコマンドは、プロジェクト内のすべてのキャッシュ可能なターゲットをローカルおよびリモートキャッシュにビルドして共有します。 完了したら、プロジェクトを生成してみてください：

```bash
tuist generate
```

プロジェクトのグループにキャッシュからのバイナリを含む新しいグループ `Cache` が追加されていることに気づくでしょう。

<img src="/images/guides/quick-start/cache.png" alt="An screenshot of a project group structure where you can see XCFrameworks in a cache group" style="max-width: 300px;"/>

変更をリモートリポジトリにプッシュすると、他の開発者はプロジェクトをクローンし、次のコマンドを実行できます：

```bash
tuist install
tuist auth login
tuist generate
```

すると、依存関係がバイナリとして含まれるプロジェクトが手に入ります。

## CI 上での最適化 {#optimizations-on-ci}

CIでこれらの最適化にアクセスしたい場合は、CI環境でのリクエストを認証するためにプロジェクトスコープのトークンを生成する必要があります。

```bash
tuist project tokens create my-handle/MyApp
```

次に、このトークンをCI環境の環境変数 `TUIST_CONFIG_TOKEN` として公開します。 トークンが存在することで、自動的に最適化とインサイトが有効になります。

> [!IMPORTANT] CI 環境の検出
> Tuistは、CI環境で実行されていることを検出した場合にのみトークンを使用します。 CI環境が検出されない場合は、環境変数 `CI` を `1` に設定することでトークンの使用を強制できます。
