---
{
  "title": "Xcodeプレビュー",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "既存のXcodeプロジェクトやTuistで生成されたプロジェクトからアプリのプレビューを共有します。"
}
---
# Xcodeプレビュー

アプリケーションをビルドし、`tuist share`を使用してTuistプロジェクトに公開します。まず、<.localized_link href="/guides/get-started/existing-xcode-project">既存のXcodeプロジェクト</.localized_link>または<.localized_link href="/guides/get-started/generated-xcode-project">生成されたプロジェクト</.localized_link>のガイドに従ってプロジェクトを接続してください。

## ビルドと共有

Tuistで生成されたプロジェクトの場合：

```bash
tuist generate App
tuist xcodebuild build -scheme App -workspace App.xcworkspace \
  -configuration Debug -sdk iphonesimulator
tuist share App
```

既存のXcodeプロジェクトの場合：

```bash
tuist xcodebuild build -scheme App -project App.xcodeproj \
  -configuration Debug -sdk iphonesimulator
tuist share App --configuration Debug --platforms iOS
```

スキーム、プロジェクト、ワークスペースの名前を各自のものに置き換えてください。Releaseビルドを共有するには、ビルド時に`-configuration Release`を使用し、共有時に`--configuration Release`を使用します。

## 実機デバイス

受信者のデバイスへのインストールを許可するプロビジョニングプロファイルを使用して、デバイス用ビルドに署名する責任はあなたにあります。シミュレータSDKではなく、デバイス宛先を指定してビルドしてください：

```bash
tuist xcodebuild build -scheme App -project App.xcodeproj \
  -configuration Debug -destination 'generic/platform=iOS'
tuist share App --configuration Debug --platforms iOS
```

すでにエクスポート済みのIPAも共有できます：

```bash
tuist share App.ipa
```

受信者はモバイルデバイスでIPAプレビューリンクを開き、アプリケーションをインストールできます。認証とプロジェクトのプレビュー表示設定は引き続き適用されます。

## CIとビルド番号

既存の<.localized_link href="/guides/integrations/continuous-integration">CI認証</.localized_link>を使用し、新しいビルドごとに`CFBundleVersion`を一意にしてください。例えば、GitHub Actionsの<code v-pre>${{ github.run_number }}</code>を使用します。`tuist share`を通じて同じバイナリとビルド番号を再度アップロードしても、重複が作成されるのではなく失敗します。

```bash
tuist share App --track beta --release-notes "Fix sign-in"
```

公開されたビルドの実行、アクセス、トラック、およびREADMEバッジについては、<.localized_link href="/guides/features/previews#run-a-preview">プレビューを実行</.localized_link>を参照してください。

<!-- @snippet: ./_tuist-share -->

受信者は、ビルドシステム統合とは独立して、<.localized_link href="/guides/features/previews/run/macos">Tuist macOSアプリ</.localized_link>または<.localized_link href="/guides/features/previews/run/ios">iPhoneアプリ</.localized_link>を使用できます。iPhoneガイドでは、Tuist SDKを使用した<.localized_link href="/guides/features/previews/run/ios#in-app-update-notifications">アプリ内更新通知</.localized_link>についても説明しています。
