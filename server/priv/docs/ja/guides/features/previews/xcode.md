---
{
  "title": "Xcodeプレビュー",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "既存のXcodeプロジェクトおよびTuistで生成されたプロジェクトからアプリケーションのプレビューを共有します。"
}
---
# Xcode プレビュー

アプリケーションをビルドし、`tuist share` を使用して Tuist プロジェクトに公開します。まずは <.localized_link href="/guides/get-started/existing-xcode-project">既存の Xcode プロジェクト</.localized_link> または <.localized_link href="/guides/get-started/generated-xcode-project">生成されたプロジェクト</.localized_link> のガイドに従ってプロジェクトを接続してください。

## ビルドと共有

Tuist で生成されたプロジェクトの場合：

```bash
tuist generate App
tuist xcodebuild build -scheme App -workspace App.xcworkspace \
  -configuration Debug -sdk iphonesimulator
tuist share App
```

既存の Xcode プロジェクトの場合：

```bash
tuist xcodebuild build -scheme App -project App.xcodeproj \
  -configuration Debug -sdk iphonesimulator
tuist share App --configuration Debug --platforms iOS
```

スキーム、プロジェクト、ワークスペースの名前を自分のものに置き換えてください。Release ビルドを共有するには、ビルド時に `-configuration Release` を使用し、共有時に `--configuration Release` を使用します。

## 実機

受信者のデバイスにインストールできるプロビジョニングプロファイルで、デバイス向けビルドに署名する責任はあなたにあります。シミュレータ SDK ではなく、デバイス宛先を指定してビルドしてください：

```bash
tuist xcodebuild build -scheme App -project App.xcodeproj \
  -configuration Debug -destination 'generic/platform=iOS'
tuist share App --configuration Debug --platforms iOS
```

すでにエクスポート済みの IPA も共有できます：

```bash
tuist share App.ipa
```

受信者はモバイルデバイスで IPA プレビューリンクを開き、アプリケーションをインストールできます。認証とプロジェクトのプレビュー表示設定は引き続き適用されます。

## CI とビルド番号

既存の <.localized_link href="/guides/integrations/continuous-integration">CI 認証</.localized_link> を使用し、新しいビルドごとに `CFBundleVersion` を一意にしてください。例えば、GitHub Actions の <code v-pre>${{ github.run_number }}</code> を使用します。`tuist share` を介して同じバイナリとビルド番号を再度アップロードすると、重複が作成されるのではなく失敗します。

```bash
tuist share App --track beta --release-notes "Fix sign-in"
```

公開済みビルドの実行、アクセス、トラック、README バッジについては <.localized_link href="/guides/features/previews#run-a-preview">プレビューを実行</.localized_link> を参照してください。

<!-- @snippet: ./_tuist-share -->

受信者は、ビルドシステムの統合とは独立して <.localized_link href="/guides/features/previews/run/macos">Tuist macOS アプリ</.localized_link> または <.localized_link href="/guides/features/previews/run/ios">iPhone アプリ</.localized_link> を使用できます。iPhone ガイドでは、Tuist SDK を使用した <.localized_link href="/guides/features/previews/run/ios#in-app-update-notifications">アプリ内更新通知</.localized_link> についても説明しています。
