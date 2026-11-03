---
{
  "title": "macOSアプリでプレビューを実行",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "TuistのmacOSメニューバーアプリを使用して、デバイスやシミュレータ上で互換性のあるAppleプレビューを実行します。"
}
---
# macOSアプリでプレビューを実行

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/logo.png" style="height: 100px;" />
    <a href="https://tuist.dev/download" style="text-decoration: none;">Download Tuist for macOS</a>
    <img src="/images/guides/features/menu-bar-app.png" style="width: 300px;" />
</div>

Appleのプレビューでは、ビルドがXcode、Bazel、Onceのいずれから生成されたかに関わらず、TuistのmacOSメニューバーアプリはCLIの代替手段となります。公開ワークフローの署名と対象要件は引き続き適用されます。

## インストール {#install}

[アプリをダウンロード](https://tuist.dev/download)するか、`brew install --cask tuist/tuist/tuist`でインストールします。

## ビルドを実行 {#run-a-build}

メニューバーアプリで互換性のあるデバイスまたはシミュレータを選択し、プレビューページで**実行**をクリックします。

macOSアプリはまず、アプリごとに最新の互換性のあるプレビューをリクエストします。プラットフォームフィルタを適用する前に個別のアプリを選択する古いサーバーの場合、利用可能なビルドを隠してしまうカットオフを設けることなく、ページ分割された履歴にフォールバックします。

アクセス権限と整理については、<.localized_link href="/guides/features/previews#visibility">可視性とトラック</.localized_link>をご覧ください。
