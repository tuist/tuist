---
{
  "title": "はじめに",
  "titleTemplate": ":title · はじめに · ガイド · Tuist",
  "description": "現在のアプリのビルド方法に合わせて、Tuist の利用方法を選択してください。Xcode、生成された Xcode プロジェクト、Gradle、Elixir、Rust、または Bazel が対象です。"
}
---
# はじめに {#get-started}

現在のアプリのビルド方法に合ったパスを選択してください。各パスでは、インストールすべきもの、キャッシング、インサイト、テスト機能を有効にする方法、そしてセットアップをエンドツーエンドで検証する方法を順を追って説明します。これらを個別に導入することも、複数のプラットフォームでリリースしている場合は組み合わせて利用することもできます。

## Xcode プロジェクト {#existing-xcode-project}

既存の Xcode プロジェクトまたはワークスペースを維持したまま、Tuist の機能を一つずつ追加できます。プロジェクトの生成は不要です。

<.localized_link href="/guides/get-started/existing-xcode-project">Start with an Xcode project →</.localized_link>

## 生成された Xcode プロジェクト {#generated-xcode-project}

Swift マニフェストから Tuist が Xcode プロジェクトを定義・生成します。生成されたプロジェクトは、モジュール化された Xcode プロジェクトの複雑さをグラフの簡潔な宣言的記述に圧縮し、<.localized_link href="/guides/features/cache/module-cache">モジュールキャッシュ</.localized_link> および <.localized_link href="/guides/features/selective-testing/generated-xcode-project">選択的テスト</.localized_link> に不可欠な要件となります。

<.localized_link href="/guides/get-started/generated-xcode-project">Start with a generated project →</.localized_link>

## Gradle プロジェクト {#gradle-project}

`dev.tuist` Gradle プラグインを通じて、Gradle プロジェクトを Tuist のリモートキャッシュ、ビルドインサイト、テストインサイトに接続します。

<.localized_link href="/guides/get-started/gradle-project">Start with a Gradle project →</.localized_link>

## Elixir プロジェクト {#elixir-project}

`tuist_ex` Hex パッケージを通じて、Elixir プロジェクトを Tuist のビルドインサイト、テストインサイト、不安定なテストの検出、テストシャーディングに接続します。

<.localized_link href="/guides/get-started/elixir-project">Start with an Elixir project →</.localized_link>

## Rust プロジェクト {#rust-project}

Tuist CLI を介して Cargo を実行し、doctest を含むビルドと個々のテスト結果を報告し、不安定なテストを調査します。

<.localized_link href="/guides/get-started/rust-project">Start with a Rust project →</.localized_link>

## Bazel プロジェクト {#bazel-project}

Bazel ワークスペースを Tuist の Remote Execution API キャッシュと Build Event Service に向け、チームと CI でキャッシュヒットとインサイトを共有します。

<.localized_link href="/guides/get-started/bazel-project">Start with a Bazel project →</.localized_link>

いずれの場合も、まず <.localized_link href="/guides/install-tuist">Tuist コマンドラインインターフェースをインストール</.localized_link> してください。Elixir プロジェクトは例外で、Hex パッケージだけで十分です。
