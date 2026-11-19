---
{
  "title": "macOSアプリでプレビューを実行",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "TuistのmacOSメニューバーアプリを使用して、デバイスやシミュレーター上で互換性のあるAppleプレビューを実行します。"
}
---
# macOSアプリでプレビューを実行

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/logo.png" style="height: 100px;" />
    <a href="https://tuist.dev/download" style="text-decoration: none;">Download Tuist for macOS</a>
    <img src="/images/guides/features/menu-bar-app.png" style="width: 300px;" />
</div>

Apple向けプレビューの場合、TuistのmacOSメニューバーアプリはCLIの代替手段です。ビルドがXcode、Bazel、Onceのいずれから生成された場合でも利用できます。公開ワークフローの署名および Eligibility 要件は引き続き適用されます。

## インストール {#install}

[アプリをダウンロード](https://tuist.dev/download)するか、`brew install --cask tuist/tuist/tuist`でインストールします。

## ビルドを実行 {#run-a-build}

メニューバーアプリで互換性のあるデバイスまたはシミュレータを選択し、プレビューページで**Run**をクリックします。

macOSアプリはまず、アプリごとに最新かつ互換性のあるプレビューをリクエストします。プラットフォームフィルタを適用する前に個別のアプリを選択する古いサーバーでは、利用可能なビルドを隠してしまうカットオフを設けずに、ページネーション付きの履歴にフォールバックします。

アクセスと整理については、<.localized_link href="/guides/features/previews#visibility">可視性とトラック</.localized_link>をご覧ください。
