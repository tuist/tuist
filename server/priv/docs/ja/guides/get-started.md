---
{
  "title": "Get started",
  "titleTemplate": ":title · Get started · Guides · Tuist",
  "description": "Pick the Tuist path that matches how your app is built today: Xcode, generated Xcode projects, Gradle, Elixir, Rust, or Bazel."
}
---
# はじめに {#get-started}

現在のアプリのビルド方法に合ったパスを選択してください。各パスでは、インストールすべきもの、キャッシング、インサイト、テスト機能を有効にする方法、およびセットアップをエンドツーエンドで検証する方法を説明します。これらを個別に採用することも、複数のプラットフォームに出荷する場合は組み合わせて使用することもできます。

## Xcode プロジェクト {#existing-xcode-project}

既存の Xcode プロジェクトまたはワークスペースを維持し、Tuist の機能を一つずつ追加します。プロジェクトの生成は不要です。

<.localized_link href="/guides/get-started/existing-xcode-project">Start with an Xcode project →</.localized_link>

## 生成された Xcode プロジェクト {#generated-xcode-project}

Swift マニフェストから Tuist が Xcode プロジェクトを定義・生成できるようにします。生成されたプロジェクトは、モジュラーな Xcode プロジェクトの複雑さをグラフの簡潔で宣言的な記述に圧縮し、<.localized_link href="/guides/features/cache/module-cache">モジュールキャッシュ</.localized_link> および <.localized_link href="/guides/features/selective-testing/generated-xcode-project">選択的テスト</.localized_link> に必須となります。

<.localized_link href="/guides/get-started/generated-xcode-project">Start with a generated project →</.localized_link>

## Gradle プロジェクト {#gradle-project}

`dev.tuist` Gradle プラグインを通じて、Gradle プロジェクトを Tuist のリモートキャッシュ、ビルドインサイト、およびテストインサイトに接続します。

<.localized_link href="/guides/get-started/gradle-project">Start with a Gradle project →</.localized_link>

## Elixir プロジェクト {#elixir-project}

`tuist_ex` Hex パッケージを通じて、Elixir プロジェクトを Tuist のビルドインサイト、テストインサイト、不安定なテストの検出、およびテストシャーディングに接続します。

<.localized_link href="/guides/get-started/elixir-project">Start with an Elixir project →</.localized_link>

## Rust プロジェクト {#rust-project}

Tuist CLI を介して Cargo を実行し、doctests を含むビルドと個々のテスト結果を報告し、不安定なテストを調査します。

<.localized_link href="/guides/get-started/rust-project">Start with a Rust project →</.localized_link>

## Bazel プロジェクト {#bazel-project}

Bazel ワークスペースを Tuist の Remote Execution API キャッシュと Build Event Service に向け、チーム全体および CI でキャッシュヒットとインサイトを共有します。

<.localized_link href="/guides/get-started/bazel-project">Start with a Bazel project →</.localized_link>

これらのいずれかを行う前に、<.localized_link href="/guides/install-tuist">Tuist コマンドラインインターフェースをインストール</.localized_link>してください。Elixir プロジェクトは例外で、Hex パッケージだけで十分です。
