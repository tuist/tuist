---
{
  "title": "QA",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "AI-powered testing agent that tests your iOS apps automatically with comprehensive QA coverage."
}
---
# 品質保証{#qa}

::: warning EARLY PREVIEW
<!-- -->
Tuist QAは現在早期プレビュー中です。アクセスするには[tuist.dev/qa](https://tuist.dev/qa)にサインアップしてください。
<!-- -->
:::

高品質のモバイルアプリ開発は包括的なテストに依存しているが、従来のアプローチには限界がある。ユニットテストは高速でコスト効率に優れていますが、実際のユーザーシナリオを見逃してしまいます。受け入れテストと手動QAは、これらのギャップを捉えることができますが、リソースを大量に消費し、うまく拡張できません。

TuistのQAエージェントは、本物のユーザー行動をシミュレートすることで、この課題を解決します。アプリを自律的に探索し、インターフェース要素を認識し、現実的なインタラクションを実行し、潜在的な問題にフラグを立てます。このアプローチにより、従来の受け入れテストやQAテストのオーバーヘッドやメンテナンスの負担を回避しながら、開発の早い段階でバグやユーザビリティの問題を特定することができます。

## 前提条件{#prerequisites}

Tuist QAを使い始めるには、以下のことが必要です：
- PR
  CIワークフローから<LocalizedLink href="/guides/features/previews">プレビュー</LocalizedLink>をアップロードするように設定します。
- <LocalizedLink href="/guides/integrations/gitforge/github">GitHubとの統合</LocalizedLink>により、PRから直接エージェントを起動することができます。

## 使用法 {#usage}

Tuist QAは現在、PRから直接トリガーされます。PRにプレビューを関連付けたら、`/qa test I want to test feature A`
とPRにコメントすることで、QAエージェントを起動することができます：

QAトリガーコメント](/images/guides/features/qa/qa-trigger-comment.png)。

コメントにはライブセッションへのリンクが含まれており、QAエージェントの進行状況や発見された問題をリアルタイムで確認することができます。エージェントが実行を完了すると、結果の概要をPRに投稿します：

QAテストの概要](/images/guides/features/qa/qa-test-summary.png)。

PRコメントがリンクしているダッシュボードのレポートの一部として、問題のリストとタイムラインが表示されます：

QAタイムライン](/images/guides/features/qa/qa-timeline.png)。

iOSアプリのすべてのQA実行は、公開ダッシュボードでご覧いただけます:
https://tuist.dev/tuist/tuist/qa

::: info
<!-- -->
QAエージェントは自律的に実行され、一度開始すると追加のプロンプトで中断することはできません。エージェントがあなたのアプリとどのように相互作用したかを理解するのを助けるために、実行を通して詳細なログを提供します。これらのログは、アプリのコンテキストを反復し、エージェントの動作をよりよくガイドするためにプロンプトをテストするのに役立ちます。エージェントの動作に関するフィードバックがありましたら、[GitHub
Issues](https://github.com/tuist/tuist/issues)、[Slack
コミュニティ](https://slack.tuist.dev) または [コミュニティフォーラム](https://community.tuist.dev)
までお知らせください。
<!-- -->
:::

### アプリのコンテキスト{#app-context}

エージェントは、アプリをうまくナビゲートするために、アプリに関するより多くのコンテキストを必要とするかもしれません。アプリコンテキストには3つのタイプがあります：
- アプリの説明
- 資格証明書
- 引数グループを立ち上げる

これらはすべて、プロジェクトのダッシュボード設定で設定できます (`設定` >`QA`)。

#### アプリの説明{#app-description}

アプリの説明は、アプリが何をするのか、どのように動作するのかについての追加コンテキストを提供するためのものです。これは、エージェントをキックオフするときに、プロンプトの一部として渡される長文のテキストフィールドです。例として、次のようなものがあります：

```
Tuist iOS app is an app that gives users easy access to previews, which are specific builds of apps. The app contains metadata about the previews, such as the version and build number, and allows users to run previews directly on their device.

The app additionally includes a profile tab to surface about information about the currently signed-in profile and includes capabilities like signing out.
```

#### 資格証明書{#credentials}

エージェントがいくつかの機能をテストするためにアプリにサインインする必要がある場合、エージェントが使用する認証情報を提供することができます。エージェントは、サインインする必要があると認識した場合、これらの認証情報を入力します。

#### 引数グループを立ち上げる{#launch-argument-groups}

起動引数グループは、エージェントを実行する前のテストプロンプトに基づいて選択されます。例えば、エージェントにサインインを繰り返させ、トークンとランナー分を浪費させたくない場合、代わりに認証情報をここで指定することができます。エージェントがサインインしてセッションを開始すべきであると認識した場合、アプリを起動するときに認証情報の起動引数グループを使用します。

起動引数グループ](/images/guides/features/qa/launch-argument-groups.png)。

これらの起動引数は、標準的な Xcode の起動引数です。以下は、自動的にサインインするための使用例です：

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
