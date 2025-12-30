---
{
  "title": "Gather insights",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to gather insights about your project."
}
---
# 洞察を集める{#gather-insights}

Tuistはサーバーと統合してその機能を拡張することができる。その機能のひとつが、プロジェクトやビルドに関するインサイトを収集することだ。必要なのは、サーバーにプロジェクトを持つアカウントがあることだけだ。

まず、認証を実行する必要がある：

```bash
tuist auth login
```

## プロジェクトを作成する{#create-a-project}

プロジェクトを作成するには

```bash
tuist project create my-handle/MyApp

# Tuist project my-handle/MyApp was successfully created 🎉 {#tuist-project-myhandlemyapp-was-successfully-created-}
```

コピー`my-handle/MyApp` 、これはプロジェクトの完全なハンドルを表す。

## コネクト・プロジェクト{#connect-projects}

サーバー上にプロジェクトを作成したら、それをローカル・プロジェクトに接続する必要があります。`tuist edit` を実行し、`Tuist.swift`
ファイルを編集して、プロジェクトの完全なハンドルを含めます：

```swift
import ProjectDescription

let tuist = Tuist(fullHandle: "my-handle/MyApp")
```

完了です！これで、プロジェクトとビルドに関する情報を収集する準備が整いました。`tuist test` を実行して、結果をサーバーに報告するテストを実行します。

::: info
<!-- -->
Tuistは結果をローカルにキューに入れ、コマンドをブロックすることなく送信しようとする。そのため、コマンドの終了直後に送信されないことがある。CIでは、結果は直ちに送信される。
<!-- -->
:::


サーバー内のランのリストを表示する画像](/images/guides/quick-start/runs.png)。

プロジェクトやビルドからデータを得ることは、情報に基づいた意思決定を行う上で非常に重要です。Tuistはその機能を拡張し続け、あなたはプロジェクト構成を変更することなく、その恩恵を受けることができる。魔法のようでしょう？🪄
