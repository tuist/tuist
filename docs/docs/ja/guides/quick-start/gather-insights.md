---
{
  "title": "インサイトを収集する",
  "titleTemplate": ":title · クイックスタート · ガイド · Tuist",
  "description": "プロジェクトに関するインサイトを収集する方法を学びます。"
}
---
# インサイトを収集する {#gather-insights}

Tuistはサーバーと統合してその機能を拡張できます。 その機能の一つは、プロジェクトやビルドに関するインサイトを収集することです。 サーバー上にプロジェクトのアカウントを持っているだけで済みます。

まず最初に、次のコマンドを実行して認証を行う必要があります：

```bash
tuist auth login
```

## プロジェクトの作成 {#create-a-project}

次に、次のコマンドを実行してプロジェクトを作成できます：

```bash
tuist project create my-handle/MyApp

# Tuist project my-handle/MyApp was successfully created 🎉 {#tuist-project-myhandlemyapp-was-successfully-created-}
```

`my-handle/MyApp` をコピーします。これはプロジェクトの完全なハンドルを表します。

## プロジェクトを接続する {#connect-projects}

サーバー上にプロジェクトを作成した後、ローカルプロジェクトに接続する必要があります。 サーバー上にプロジェクトを作成した後、ローカルプロジェクトに接続する必要があります。 サーバー上にプロジェクトを作成した後、ローカルプロジェクトに接続する必要があります。 サーバー上にプロジェクトを作成した後、ローカルプロジェクトに接続する必要があります。 サーバー上にプロジェクトを作成した後、ローカルプロジェクトに接続する必要があります。 サーバー上にプロジェクトを作成した後、ローカルプロジェクトに接続する必要があります。 Run `tuist edit` and edit the `Tuist.swift` file to include the full handle of the project:

```swift
import ProjectDescription

let tuist = Tuist(fullHandle: "my-handle/MyApp")
```

ほら！ これで、プロジェクトやビルドに関するインサイトを収集する準備が整いましたよ。 `tuist test` を実行してテストを実行し、結果をサーバーに報告します。

> [!NOTE]
> Tuistは結果をローカルにキューイングし、コマンドをブロックすることなく送信しようとします。 したがって、コマンドが終了した直後に結果が送信されない場合があります。 CIでは結果が即座に送信されます。

![An image that shows a list of runs in the server](/images/guides/quick-start/runs.png)

プロジェクトやビルドからデータを取得することは、情報に基づいた意思決定を行う上で重要です。
Tuistはその機能を拡張し続け、プロジェクトの設定を変更することなくその恩恵を受けることができます。 魔法のようですね？ 🪄
