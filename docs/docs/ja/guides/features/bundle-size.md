---
{
  "title": "Bundle insights",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Find out how to make and keep your app's memory footprint as small as possible."
}
---
# インサイトをバンドルする{#bundle-size}

警告 要件
<!-- -->
- <LocalizedLink href="/guides/server/accounts-and-projects">Tuistアカウントとプロジェクト</LocalizedLink>
<!-- -->
:::

アプリに機能を追加するにつれ、アプリバンドルのサイズは増大し続けます。コードやアセットの増加に伴いバンドルサイズが膨らむのは避けられない部分もありますが、バンドル間でアセットが重複しないようにしたり、未使用のバイナリシンボルを削除したりするなど、その増加を抑える方法は数多く存在します。Tuistはアプリサイズを小さく保つためのツールと分析機能を提供し、さらに時間の経過に伴うアプリサイズの推移も監視します。

## 使用法 {#usage}

バンドルを解析するには、`tuist inspect bundle` コマンドを使用できます:

コードグループ
```bash [Analyze an .ipa]
tuist inspect bundle App.ipa
```
```bash [Analyze an .xcarchive]
tuist inspect bundle App.xcarchive
```
```bash [Analyze an app bundle]
tuist inspect bundle App.app
```
<!-- -->
:::

`tuist inspect bundle`
コマンドはバンドルを分析し、バンドルの詳細概要（バンドル内容のスキャンやモジュール内訳を含む）を確認できるリンクを提供します：

![Analyzed bundle](/images/guides/features/bundle-size/analyzed-bundle.png)

## 継続的インテグレーション{#continuous-integration}

バンドルサイズを時間経過とともに追跡するには、CI上でバンドルを分析する必要があります。まず、CIが<LocalizedLink href="/guides/integrations/continuous-integration#authentication">認証済み</LocalizedLink>であることを確認してください：

GitHub Actionsのワークフロー例は以下のようになります：

```yaml
name: Build

jobs:
  build:
    steps:
      - # Build your app
      - name: Analyze bundle
        run: tuist inspect bundle App.ipa
        env:
          TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}
```

設定が完了すると、バンドルサイズが時間とともにどのように変化するかを確認できます：

![バンドルサイズグラフ](/images/guides/features/bundle-size/bundle-size-graph.png)

## プル/マージリクエストのコメント{#pullmerge-request-comments}

::: warning INTEGRATION WITH GIT PLATFORM REQUIRED
<!-- -->
自動プルリクエスト/マージリクエストコメントを取得するには、<LocalizedLink href="/guides/server/accounts-and-projects">Tuistプロジェクト</LocalizedLink>を<LocalizedLink href="/guides/server/authentication">Gitプラットフォーム</LocalizedLink>と連携させてください。
<!-- -->
:::

Tuistプロジェクトが[GitHub](https://github.com)などのGitプラットフォームと連携されると、`tuist inspect
bundle` を実行するたびに、Tuistがプルリクエスト/マージリクエストに直接コメントを投稿します：
![GitHubアプリへの検査済みバンドルコメント](/images/guides/features/bundle-size/github-app-with-bundles.png)
