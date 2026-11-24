---
{
  "title": "生成されたXcodeプロジェクト",
  "titleTemplate": ":title · スナップショット · 機能 · ガイド · Tuist",
  "description": "Tuistで生成したプロジェクトのSwiftUIプレビューをスナップショットとして保存し、Tuistで変更を確認します。"
}
---
# 生成されたXcodeプロジェクトのスナップショット {#generated-xcode-project-snapshots}

> [!IMPORTANT]
> **要件**
>
> - アカウントでスナップショットが有効になっていること。現在は招待制です。[お問い合わせ](mailto:contact@tuist.dev)いただくか、[コミュニティSlack](https://slack.tuist.dev)でアクセスリクエストを送ってください。
> - <.localized_link href="/guides/get-started/generated-xcode-project">Tuistに接続された</.localized_link>プロジェクト。
> - プレビューのレンダリングにはiOS 17またはmacOS 14が必要です。

[tuist/snapshots](https://github.com/tuist/snapshots)ライブラリはアプリ内のすべてのSwiftUIプレビューを画像としてレンダリングするため、手動でスナップショットテストを作成する必要がありません。`tuist test`は実行後に画像をアップロードし、Tuistがそれらを<.localized_link href="/guides/features/snapshots#how-it-works">ベースライン</.localized_link>と比較します。

## セットアップ {#set-up}

パッケージを`Tuist/Package.swift`に追加してください:

```swift
let package = Package(
    name: "App",
    dependencies: [
        .package(url: "https://github.com/tuist/snapshots", .upToNextMinor(from: "0.1.0")),
    ]
)
```

次に、アプリと`TuistSnapshotsTesting`に依存するユニットテストターゲットと、それを実行するスキームを追加します。スキームはスナップショットセットの名前を定義します:

```swift
import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        // Your app target, named "App".
        .target(
            name: "AppSnapshotTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.app-snapshot-tests",
            deploymentTargets: .iOS("17.0"),
            sources: ["Tests/AppSnapshotTests/**"],
            dependencies: [
                .target(name: "App"),
                .external(name: "TuistSnapshotsTesting"),
            ]
        ),
    ],
    schemes: [
        .scheme(
            name: "AppSnapshots",
            buildAction: .buildAction(targets: [.target("App")]),
            testAction: .targets([.testableTarget(target: "AppSnapshotTests")])
        ),
    ]
)
```

ターゲットにテストクラスを追加します。各プレビューが個別のテストになります:

```swift
import TuistSnapshotsTesting

final class PreviewSnapshotTests: PreviewSnapshotTestCase {}
```

パッケージを取得するために`tuist install`を実行してください。

## 実行 {#run}

`tuist test`でスキームを実行し、常に同じシミュレーターを使用してください。異なるデバイスでは異なるサイズの画像がレンダリングされるためです:

```bash
tuist test AppSnapshots --device "iPhone 17"
```

CIでは、テストがレンダリングした画像は実行後にアップロードされ、画像に変更があり誰も承認していない場合、コマンドは失敗します。ローカル実行では何もアップロードされません。コミットされていない変更がアップロードされてしまうのを防ぐためです。

> [!TIP]
> <.localized_link href="/guides/features/selective-testing">選択的テスト</.localized_link>を使用すると、スナップショットテストターゲットは画像が合格するか承認された場合にのみスキップされるため、誰もレビューしていない変更を含むターゲットが再実行でスキップされることはありません。実行がターゲットをスキップする場合、レンダリングされなかった画像は削除ではなくスキップとしてカウントされます。

<!-- @snippet: ./_previews-library -->
