---
{
  "title": "Get started",
  "titleTemplate": ":title · Contributors · Tuist",
  "description": "Get started contributing to Tuist by following this guide."
}
---
# スタート{#get-started}

iOSのようなアップル・プラットフォーム向けのアプリを作った経験があれば、Tuistにコードを追加することはそれほど変わらないはずだ。アプリの開発と比べて、特筆すべき違いが2つある：

- **CLIとのやりとりはターミナルを通して行われる。**
  ユーザーはTuistを実行し、目的のタスクを実行し、成功するかステータスコードとともに戻る。実行中、標準出力と標準エラーに出力情報を送ることでユーザーに通知することができる。ジェスチャーやグラフィカルなインタラクションはなく、ユーザーの意図だけがある。

- **iOSアプリでアプリがシステム・イベントやユーザー・イベントを受信したときに起こるような、入力待ちでプロセスを存続させるランループ（**
  ）はない。CLIはそのプロセスの中で実行され、作業が終わると終了する。非同期作業は、[DispatchQueue](https://developer.apple.com/documentation/dispatch/dispatchqueue)
  や [structured
  concurrency](https://developer.apple.com/tutorials/app-dev-training/managing-structured-concurrency)のようなシステムAPIを使用して行うことができますが、非同期作業が実行されている間、プロセスが実行されていることを確認する必要があります。そうしないと、プロセスは非同期作業を終了してしまいます。

Swiftの経験がない場合は、言語とFoundationのAPIから最も使用される要素に慣れるために、[Appleの公式本](https://docs.swift.org/swift-book/)をお勧めします。

## 最低条件{#minimum-requirements}

Tuistに貢献するための最低条件は以下の通り：

- macOS 14.0+
- Xcode 16.3+

## プロジェクトをローカルにセットアップする{#set-up-the-project-locally}

プロジェクトを開始するには、以下のステップを踏む：

- `git clone git@github.com:tuist/tuist.git を実行してリポジトリをクローンします。`
- [インストール](https://mise.jdx.dev/getting-started.html)。開発環境のプロビジョニングを行います。
- `mise install` を実行し、Tuistが必要とするシステム依存関係をインストールする。
- `tuist install` を実行し、Tuistが必要とする外部依存関係をインストールする。
- (オプション)`tuist auth login` を実行して
  <LocalizedLink href="/guides/features/cache">Tuist Cache にアクセスする。</LocalizedLink>
- `tuist generate` を実行し、Tuist自身を使用してTuist Xcodeプロジェクトを生成する。

**生成されたプロジェクトは自動的に開きます** 。生成せずに再度開く必要がある場合は、`open Tuist.xcworkspace`
を実行する（またはFinderを使用する）。

::: info XED .
<!-- -->
`xed .`
を使ってプロジェクトを開こうとすると、パッケージが開かれ、Tuistが生成したプロジェクトは開かれない。ツールのドッグフードにはTuistが生成したプロジェクトを使うことを推奨する。
<!-- -->
:::

## プロジェクトの編集{#edit-the-project}

依存関係の追加やターゲットの調整など、プロジェクトの編集が必要な場合は、<LocalizedLink href="/guides/features/projects/editing">`tuist edit` command</LocalizedLink>を使うことができる。これはほとんど使われませんが、存在を知っておくのは良いことです。

## ラン・トゥイスト{#run-tuist}

### Xcodeから{#from-xcode}

生成されたXcodeプロジェクトから`tuist` を実行するには、`tuist` スキームを編集し、コマンドに渡したい引数を設定します。例えば、`tuist
generate` コマンドを実行するには、`generate --no-open` に引数を設定して、生成後にプロジェクトが開かないようにします。

![Tuistでgenerateコマンドを実行するスキーム設定の例](/images/contributors/scheme-arguments.png)。

また、作業ディレクトリを生成されるプロジェクトのルートに設定する必要があります。すべてのコマンドが受け入れる`--path`
引数を使うか、以下のようにスキームで作業ディレクトリを設定することでできます：


![Tuistを実行するための作業ディレクトリの設定例](/images/contributors/scheme-working-directory.png)。

::: warning PROJECTDESCRIPTION COMPILATION
<!-- -->
`tuist` CLIは、`ProjectDescription`
フレームワークがビルドされたproductsディレクトリに存在するかどうかに依存します。`tuist` が`ProjectDescription`
フレームワークが見つからないために実行に失敗する場合は、まず`Tuist-Workspace` スキームをビルドしてください。
<!-- -->
:::

### ターミナルから{#from-the-terminal}

`run` コマンドでTuistそのものを使って`tuist` を実行することができる：

```bash
tuist run tuist generate --path /path/to/project --no-open
```

あるいは、Swift パッケージマネージャを通して直接実行することもできます：

```bash
swift build --product ProjectDescription
swift run tuist generate --path /path/to/project --no-open
```
