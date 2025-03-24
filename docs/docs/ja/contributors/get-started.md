---
title: はじめに
titleTemplate: :title · コントリビューター · Tuist
description: このガイドに従って、Tuistへのコントリビューションを始めましょう。
---

# はじめに {#get-started}

iOS などの Apple プラットフォーム向けのアプリ開発経験がある場合、Tuist にコードを追加することもそれほど違いはないでしょう。 アプリ開発と比べて、触れておくべき違いが2点あります。

- **CLIとのやり取りはターミナルを通じて行われます。** ユーザーはTuistを実行し、指定したタスクを実行した後、正常に終了するか、またはステータスコードを返します。 実行中は、標準出力や標準エラーに情報を出力することで、ユーザーに通知を行うことができます。 ジェスチャーやグラフィカルな操作はなく、あるのはユーザーの意図だけです。

- **プロセスを保持して入力待ちをするランループはありません。** これはiOSアプリがシステムやユーザーのイベントを受け取るときの挙動とは異なります。  CLIはそのプロセス内で実行され、タスクが完了すると終了します。  非同期処理は、[DispatchQueue](https://developer.apple.com/documentation/dispatch/dispatchqueue) や [構造化並行処理](https://developer.apple.com/tutorials/app-dev-training/managing-structured-concurrency) などのシステムAPIを使用して実行できますが、非同期処理が実行されている間はプロセスが稼働していることを確認する必要があります。  さもなければ、プロセスが終了し、非同期処理も中断されてしまいます。

Swiftに関する経験がない場合は、言語と Foundation API の主要な要素に慣れるために、[Appleの公式ブック](https://docs.swift.org/swift-book/)をお勧めします。

## 最小要件 {#minimum-requirements}

Tuist に貢献するには、最低限の要件があります。

- macOS 14.0 以上
- Xcode 16.0 以上

## ローカルでプロジェクトをセットアップする {#set-up-the-project-locally}

プロジェクトの作業を開始するには、以下の手順に従います。

- `git clone git@github.com:tuist/tuist.git` を実行してリポジトリをクローンします。
- 開発環境を整えるため、Mise を [インストール](https://mise.jdx.dev/getting-started.html) します。
- Tuist が必要とするシステム依存関係をインストールするため、 `mise install` を実行します。
- Tuist が必要とする外部依存関係をインストールするため、 `tuist install` を実行します。
- (任意) `tuist auth login` を実行して、 <LocalizedLink href="/guides/develop/build/cache">Tuist Cache</LocalizedLink> へのアクセスを取得します
- `tuist generate` を実行して、Tuist の Xcode プロジェクトを生成します。

**生成されたプロジェクトは自動的に開きます。** 再生成せずにもう一度開くには、`open Tuist.xcworkspace` を実行するか、Finderを使ってください。

> [!NOTE] XED .
> `xed .` を使ってプロジェクトを開いた場合、Tuist が生成したプロジェクトではなく、パッケージが開きます。  Tuist で生成されたプロジェクトを使って、自分でツールを試すことを推奨します。

## プロジェクトの編集 {#edit-the-project}

依存関係の追加やターゲットの調整など、プロジェクトを編集する必要がある場合は、<LocalizedLink href="/guides/develop/projects/editing">`tuist edit` コマンド</LocalizedLink>を使用できます。  あまり使われることはありませんが、知っておいて損はありません。

## Tuist を実行する {#run-tuist}

### Xcode 経由 {#from-xcode}

生成されたXcodeプロジェクトから `tuist` を実行するには、`tuist` スキームを編集し、コマンドに渡す引数を設定します。 例えば、`tuist generate` コマンドを実行する際に、引数を `generate --no-open` に設定すると、生成後にプロジェクトが開かれるのを防げます。

![Tuist で生成コマンドを実行するためのスキーム設定例](/images/contributors/scheme-arguments.png)

また、生成されるプロジェクトのルートを作業ディレクトリに設定する必要があります。 `--path` 引数を使用して設定することも、以下のようにスキームで作業ディレクトリを設定することもできます。

![Tuistを実行するための作業ディレクトリの設定例](/images/contributors/scheme-working-directory.png)

> [!WARNING] PROJECTDESCRIPTION COMPILATION
> `tuist` CLI は、ビルドされたプロダクトのディレクトリにある `ProjectDescription` フレームワークの存在に依存します。 `ProjectDescription` フレームワークが見つからずに `tuist` の実行が失敗した場合は、まず `Tuist-Workspace` スキームをビルドしてください。

### ターミナル経由 {#from-the-terminal}

Tuist 自体の `run` コマンドを使って `tuist` を実行できます。

```bash
tuist run tuist generate --path /path/to/project --no-open
```

または、Swift Package Manager で直接実行することもできます。

```bash
swift build --product ProjectDescription
swift run tuist generate --path /path/to/project --no-open
```
