---
{
  "title": "Bundle insights",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Find out how to make and keep your app's memory footprint as small as possible."
}
---
# バンドル・インサイト{#bundle-size}

警告 要件
<!-- -->
- A<LocalizedLink href="/guides/server/accounts-and-projects">トゥイストのアカウントとプロジェクト</LocalizedLink>
<!-- -->
:::

アプリに機能を追加していくと、アプリのバンドルサイズはどんどん大きくなっていきます。より多くのコードやアセットを出荷するため、バンドルサイズの増加は避けられない部分もありますが、バンドル間でアセットが重複しないようにしたり、未使用のバイナリシンボルを削除したりするなど、その増加を最小限に抑える方法はたくさんあります。Tuistは、アプリのサイズを小さく保つためのツールとインサイトを提供し、アプリのサイズを長期的に監視します。

## 使用法 {#usage}

バンドルを分析するには、`tuist inspect bundle` コマンドを使います：

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
コマンドはバンドルを分析し、バンドルの内容のスキャンやモジュールの内訳を含むバンドルの詳細な概要を見るためのリンクを提供します：

分析されたバンドル](/images/guides/features/bundle-size/analyzed-bundle.png)。

## 継続的インテグレーション{#continuous-integration}

バンドルのサイズを経時的に追跡するには、CI上のバンドルを分析する必要があります。まず、CIが<LocalizedLink href="/guides/integrations/continuous-integration#authentication">認証済み</LocalizedLink>であることを確認する必要があります：

GitHub Actions のワークフローの例は次のようになります：

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

一度設定すれば、時間の経過とともにバンドルサイズがどのように変化していくかを確認することができる：

![バンドルサイズグラフ](/images/guides/features/bundle-size/bundle-size-graph.png)。

## プル/マージリクエストのコメント{#pullmerge-request-comments}

::: warning INTEGRATION WITH GIT PLATFORM REQUIRED
<!-- -->
プル/マージリクエストのコメントを自動的に取得するには、<LocalizedLink href="/guides/server/accounts-and-projects">Tuistプロジェクト</LocalizedLink>を<LocalizedLink href="/guides/server/authentication">Gitプラットフォーム</LocalizedLink>と統合してください。
<!-- -->
:::

Tuistプロジェクトが[GitHub](https://github.com)のようなGitプラットフォームと接続されると、`tuist inspect
bundle`: ![GitHub app comment with inspected
bundles](/images/guides/features/bundle-size/github-app-with-bundles.png)を実行するたびに、Tuistはプル/マージリクエストに直接コメントを投稿します。
