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

Appleプレビューの場合、TuistのmacOSメニューバーアプリはCLIの代替手段となります。ビルドがXcode、Bazel、Struoのいずれから生成された場合でも利用できます。公開ワークフローの署名および適格性の要件は引き続き適用されます。

## インストール {#install}

[アプリをダウンロード](https://tuist.dev/download)するか、`brew install --cask tuist/tuist/tuist`でインストールします。

## ビルドを実行 {#run-a-build}

メニューバーアプリで互換性のあるデバイスまたはシミュレータを選択し、プレビューページで**実行**をクリックします。

macOSアプリはまず、アプリごとに最新の互換性のあるプレビューをリクエストします。プラットフォームフィルタを適用する前に個別のアプリを選択する古いサーバーでは、利用可能なビルドを隠してしまうようなカットオフを設けずに、ページ分割された履歴にフォールバックします。

アクセス権限と整理については、<.localized_link href="/guides/features/previews#visibility">可視性とトラック</.localized_link>を参照してください。
