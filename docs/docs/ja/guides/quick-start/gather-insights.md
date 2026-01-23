---
{
  "title": "Gather insights",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to gather insights about your project."
}
---
# 洞察を集める{#gather-insights}

Tuistはサーバーと連携して機能を拡張できます。その機能の一つが、プロジェクトやビルドに関するインサイトの収集です。必要なのは、サーバー上にプロジェクトを持つアカウントを持つことだけです。

まず最初に、以下のコマンドを実行して認証を行う必要があります：

```bash
tuist auth login
```

## プロジェクトを作成する{#create-a-project}

プロジェクトを作成するには、次のコマンドを実行します：

```bash
tuist project create my-handle/MyApp

# Tuist project my-handle/MyApp was successfully created 🎉 {#tuist-project-myhandlemyapp-was-successfully-created-}
```

コピー`my-handle/MyApp` 、これはプロジェクトの完全なハンドルを表します。

## プロジェクトを接続する{#connect-projects}

サーバー上でプロジェクトを作成した後、ローカルプロジェクトに接続する必要があります。`tuist edit` を実行し、`Tuist.swift`
ファイルを編集して、プロジェクトの完全なハンドルを含めてください：

```swift
import ProjectDescription

let tuist = Tuist(fullHandle: "my-handle/MyApp")
```

さあ！これでプロジェクトとビルドに関するインサイトを収集する準備が整いました。テストを実行し結果をサーバーに報告するには、``tuist test` `
を実行してください。

::: info
<!-- -->
Tuistは結果をローカルにキューイングし、コマンドをブロックせずに送信を試みます。そのため、コマンド終了直後に送信されない場合があります。CIでは結果は即時送信されます。
<!-- -->
:::


![サーバー内の実行リストを示す画像](/images/guides/quick-start/runs.png)

プロジェクトやビルドからのデータは、情報に基づいた意思決定に不可欠です。Tuistは機能を拡張し続け、プロジェクト設定を変更することなくその恩恵を受けられます。魔法のようでしょう？
🪄
