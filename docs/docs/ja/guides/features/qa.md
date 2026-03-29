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
Tuist QAは現在、早期プレビュー段階です。[tuist.dev/qa](https://tuist.dev/qa) から登録してアクセスしてください。
<!-- -->
:::

高品質なモバイルアプリ開発には包括的なテストが不可欠ですが、従来のアプローチには限界があります。ユニットテストは迅速かつ費用対効果が高いものの、実際のユーザーシナリオを網羅できていません。受け入れテストや手動による品質保証（QA）はこうしたギャップを補うことができますが、リソースを大量に消費し、拡張性に欠けます。

TuistのQAエージェントは、実際のユーザーの行動をシミュレートすることでこの課題を解決します。アプリを自律的に探索し、インターフェース要素を認識し、現実的な操作を実行し、潜在的な問題を特定します。このアプローチにより、従来の受け入れテストやQAテストに伴うオーバーヘッドやメンテナンスの負担を回避しつつ、開発の早い段階でバグやユーザビリティの問題を特定することができます。

## 前提条件{#prerequisites}

Tuist QAを使い始めるには、以下の手順が必要です：
- プルリクエストのCIワークフローから<LocalizedLink href="/guides/features/previews">プレビュー</LocalizedLink>のアップロードを設定し、エージェントがテストに使用できるようにしてください
- <LocalizedLink href="/guides/integrations/gitforge/github"></LocalizedLink>をGitHubと連携させ、プルリクエストから直接エージェントを起動できるようにします

## 使用法 {#usage}

Tuist QAは現在、プルリクエスト（PR）から直接トリガーされます。PRに関連付けられたプレビューが作成されたら、PRに「`/qa test I want
to test feature A` 」とコメントすることで、QAエージェントをトリガーできます。

![QAトリガーコメント](/images/guides/features/qa/qa-trigger-comment.png)

このコメントには、QAエージェントの進捗状況や検出した問題をリアルタイムで確認できるライブセッションへのリンクが含まれています。エージェントの実行が完了すると、結果の概要がプルリクエストに投稿されます:

![QAテスト概要](/images/guides/features/qa/qa-test-summary.png)

PRのコメントからリンクされているダッシュボードのレポートには、課題の一覧とタイムラインが表示されるため、課題がどのように発生したかを詳細に確認できます：

![QAタイムライン](/images/guides/features/qa/qa-timeline.png)

当社の
<LocalizedLink href="/guides/features/previews#tuist-ios-app">iOSアプリ</LocalizedLink>
に対して実施しているすべてのQA実行状況は、公開ダッシュボードでご確認いただけます：https://tuist.dev/tuist/tuist/qa

::: info
<!-- -->
QAエージェントは自律的に動作するため、一度開始すると追加のプロンプトで中断することはできません。
実行中は、エージェントがアプリとどのようにやり取りしたかを把握できるよう、詳細なログを提供します。これらのログは、アプリのコンテキストを調整したり、プロンプトをテストしてエージェントの動作をより適切に誘導したりする際に役立ちます。エージェントのアプリでの動作に関するフィードバックがございましたら、[GitHub
Issues](https://github.com/tuist/tuist/issues)、[Slackコミュニティ](https://slack.tuist.dev)、または[コミュニティフォーラム](https://community.tuist.dev)を通じてお知らせください。
<!-- -->
:::

### アプリのコンテキスト{#app-context}

エージェントがアプリを適切に操作するには、アプリに関する詳細なコンテキストが必要になる場合があります。アプリコンテキストには以下の3種類があります：
- アプリの説明
- 認証情報
- 起動引数グループ

これらはすべて、プロジェクトのダッシュボード設定（`Settings` >`QA` ）で設定可能です。

#### アプリの説明{#app-description}

アプリの説明は、アプリの機能や仕組みに関する追加情報を提供するためのものです。これは、エージェントを起動する際にプロンプトの一部として渡される長文テキストフィールドです。例としては次のようなものがあります：

```
Tuist iOS app is an app that gives users easy access to previews, which are specific builds of apps. The app contains metadata about the previews, such as the version and build number, and allows users to run previews directly on their device.

The app additionally includes a profile tab to surface about information about the currently signed-in profile and includes capabilities like signing out.
```

#### 認証情報{#credentials}

エージェントが一部の機能をテストするためにアプリにサインインする必要がある場合は、エージェントが使用する認証情報を提供してください。エージェントは、サインインが必要であると認識した場合、これらの認証情報を入力します。

#### 引数グループの起動{#launch-argument-groups}

エージェントの実行前に、テストプロンプトに基づいて起動引数グループが選択されます。たとえば、エージェントが繰り返しサインインしてトークンやランナーの時間を無駄にしないようにしたい場合は、代わりにここで認証情報を指定できます。エージェントがサインインした状態でセッションを開始すべきであると認識した場合、アプリを起動する際に認証情報の起動引数グループを使用します。

![引数グループの起動](/images/guides/features/qa/launch-argument-groups.png)

これらの起動引数は、標準的な Xcode の起動引数です。これらを使用して自動的にサインインする方法の例を以下に示します：

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
