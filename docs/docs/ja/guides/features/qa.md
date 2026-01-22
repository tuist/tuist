---
{
  "title": "QA",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "AI-powered testing agent that tests your iOS apps automatically with comprehensive QA coverage."
}
---
# QA{#qa}

::: warning EARLY PREVIEW
<!-- -->
Tuist QAは現在早期プレビュー中です。アクセスするには[tuist.dev/qa](https://tuist.dev/qa)で登録してください。
<!-- -->
:::

高品質なモバイルアプリ開発には包括的なテストが不可欠ですが、従来の手法には限界があります。ユニットテストは高速かつ費用対効果が高いものの、実際のユーザーシナリオを捕捉できません。受け入れテストや手動QAではこれらのギャップを補えますが、リソースを大量に消費し、拡張性に欠けます。

TuistのQAエージェントは、本物のユーザー行動をシミュレートすることでこの課題を解決します。アプリを自律的に探索し、インターフェース要素を認識し、現実的な操作を実行し、潜在的な問題を指摘します。このアプローチにより、従来型の受け入れテストやQAテストに伴うオーバーヘッドや保守負担を回避しつつ、開発の早い段階でバグやユーザビリティの問題を特定できます。

## 前提条件{#prerequisites}

Tuist QAの利用を開始するには、以下の手順が必要です：
- PR
  CIワークフローから<LocalizedLink href="/guides/features/previews">プレビュー</LocalizedLink>のアップロードを設定し、エージェントがテストに使用できるようにする
- <LocalizedLink href="/guides/integrations/gitforge/github">Integrate</LocalizedLink>をGitHubと連携させ、プルリクエストから直接エージェントを起動できるようにする

## 使用法 {#usage}

Tuist
QAは現在、プルリクエスト（PR）から直接起動されます。PRにプレビューが関連付けられたら、以下のコメントをPRに投稿することでQAエージェントを起動できます：`/qa
test I want to test feature A`

![QA trigger comment](/images/guides/features/qa/qa-trigger-comment.png)

このコメントには、QAエージェントの進捗状況や検出された問題をリアルタイムで確認できるライブセッションへのリンクが含まれています。エージェントの実行が完了すると、結果の概要がプルリクエストに投稿されます：

![QAテスト概要](/images/guides/features/qa/qa-test-summary.png)

ダッシュボード内のレポート（PRコメントからリンクされているもの）では、問題の一覧とタイムラインが表示されるため、問題が具体的にどのように発生したかを確認できます：

![QAタイムライン](/images/guides/features/qa/qa-timeline.png)

当社の<LocalizedLink href="/guides/features/previews#tuist-ios-app">iOSアプリ</LocalizedLink>向けに実施する全QA実行内容は、公開ダッシュボードでご確認いただけます：https://tuist.dev/tuist/tuist/qa

::: info
<!-- -->
QAエージェントは自律的に動作し、開始後は追加のプロンプトで中断できません。
実行中の詳細なログを提供し、エージェントがアプリとどのようにやり取りしたかを理解する手助けをします。これらのログは、アプリのコンテキストを改善し、プロンプトをテストしてエージェントの動作をより適切に導くために役立ちます。エージェントのアプリでの動作に関するフィードバックがございましたら、[GitHub
Issues](https://github.com/tuist/tuist/issues)、[Slackコミュニティ](https://slack.tuist.dev)、または[コミュニティフォーラム](https://community.tuist.dev)を通じてお知らせください。
<!-- -->
:::

### アプリコンテキスト{#app-context}

エージェントがアプリを適切に操作するには、アプリに関する追加のコンテキストが必要になる場合があります。アプリコンテキストには以下の3種類があります：
- アプリの説明
- 認証情報
- 起動引数グループ

これらすべては、プロジェクトのダッシュボード設定で構成できます（`設定` >`QA` ）。

#### アプリの説明{#app-description}

アプリの説明文は、アプリの機能や動作について追加のコンテキストを提供するものです。これはエージェント起動時にプロンプトの一部として渡される長文テキストフィールドです。例としては以下のようなものがあります：

```
Tuist iOS app is an app that gives users easy access to previews, which are specific builds of apps. The app contains metadata about the previews, such as the version and build number, and allows users to run previews directly on their device.

The app additionally includes a profile tab to surface about information about the currently signed-in profile and includes capabilities like signing out.
```

#### 認証情報{#credentials}

エージェントがアプリの機能をテストするためにログインが必要な場合、エージェントが使用できる認証情報を提供できます。エージェントはログインが必要と判断した場合、これらの認証情報を入力します。

#### 起動引数グループ{#launch-argument-groups}

エージェント実行前のテストプロンプトに基づき、起動引数グループが選択されます。例えば、エージェントが繰り返しサインインしてトークンやランナー分数を無駄にしないよう、ここで認証情報を指定できます。エージェントがサインイン状態でセッションを開始すべきと認識した場合、アプリ起動時に認証情報起動引数グループを使用します。

![起動引数グループ](/images/guides/features/qa/launch-argument-groups.png)

これらの起動引数は標準的なXcode起動引数です。自動サインインに使用する例を以下に示します：

```swift
import ArgumentParser
import SwiftUI

@main
struct TuistApp: App {
    var body: some Scene {
        ContentView()
        #if DEBUG
            .task {
                await checkForAutomaticLogin()
            }
        #endif
    }
    /// When launch arguments with credentials are passed, such as when running QA tests, we can skip the log in and
    /// automatically log in
    private func checkForAutomaticLogin() async {
        struct LaunchArguments: ParsableArguments {
            @Option var email: String?
            @Option var password: String?
        }

        do {
            let parsedArguments = try LaunchArguments.parse(Array(ProcessInfo.processInfo.arguments.dropFirst()))

            guard let email = parsedArguments.email,
                  let password = parsedArguments.password
            else {
                return
            }

            try await authenticationService.signInWithEmailAndPassword(email: email, password: password)
        } catch {
            // Skipping automatic log in
        }
    }
}
```
