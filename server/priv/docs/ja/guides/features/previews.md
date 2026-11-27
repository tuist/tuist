---
{
  "title": "プレビュー",
  "titleTemplate": ":title · 機能 · ガイド · Tuist",
  "description": "Tuist Previews を使ってモバイルアプリ、デスクトップアプリ、コマンドラインツールを共有し、チームメンバーがローカルで再ビルドせずにビルドを試せるようにします。"
}
---
# Previews {#previews}

Tuist Previews を使えば、チームメンバーはモバイルアプリ、デスクトップアプリ、コマンドラインツールをローカルで再ビルドすることなく試せます。ビルドを Tuist プロジェクトに公開し、そのプレビューリンクを共有してください。

## プレビューできるもの {#what-you-can-preview}

- **モバイルアプリ:** Android APK および Apple アプリケーションバンドルまたは IPA。サポートされるデバイス、シミュレーター、署名の要件は公開ワークフローによって異なります。
- **デスクトップアプリ:** macOS アプリケーションバンドル。
- **コマンドラインツール:** macOS または Linux の実行ファイル。単独、または依存関係とバンドルされた状態。

パッケージ化と互換性の要件については<.localized_link href="/guides/features/previews/types">サポートされるタイプ</.localized_link>をご覧ください。アーティファクトのタイプはプレビューの実行場所を決定しますが、どのビルドシステムがそれを生成するかを規定するものではありません。

## プレビューを公開する {#publish-a-preview}

セットアップおよび公開コマンド用にビルドシステムを選択してください:

<.home_cards>
  <.home_card
    title="Xcode"
    details="既存の Xcode プロジェクトまたは Tuist で生成されたプロジェクトからアプリケーションを共有します。"
    link="/guides/features/previews/xcode"
  />
  <.home_card
    title="Gradle"
    details="Gradle プロジェクトから Android アプリとネイティブのコマンドラインツールを共有します。"
    link="/guides/features/previews/gradle"
  />
  <.home_card
    title="Bazel"
    details="付随する Bazel ルールを使用して、Android アプリ、Apple アプリ、およびコマンドラインツールを共有します。"
    link="/guides/features/previews/bazel"
  />
  <.home_card
    title="Struo"
    details="Struo のネイティブアーティファクトプロバイダーを使用して、対象となる Android、Apple シミュレーター、および macOS アプリケーションを公開します。"
    link="/guides/features/previews/struo"
  />
</.home_cards>

すでにサポートされているビルドがある場合は、<.localized_link href="/cli/share">`tuist share`</.localized_link> を使用して、ビルドシステムの統合なしで公開できます。パッケージ化と署名の要件は引き続き適用されます。

## プレビューを実行する {#run-a-preview}

受信者は、プレビューを生成したビルドシステムを必要としません。互換性のあるビルドへのアクセス方法を選択してください:

<.home_cards>
  <.home_card
    title="CLI"
    details="tuist run を使用して、モバイルアプリ、macOS アプリ、およびコマンドラインのプレビューを実行します。"
    link="/guides/features/previews/run/cli"
  />
  <.home_card
    title="macOS アプリ"
    details="Tuist メニューバーアプリを通じて互換性のある Apple プレビューを実行します。"
    link="/guides/features/previews/run/macos"
  />
  <.home_card
    title="iPhone アプリ"
    details="iPhone で Apple プレビューを検索してアクセスします。"
    link="/guides/features/previews/run/ios"
  />
</.home_cards>

## 公開範囲 {#visibility}

プレビューはプロジェクトのデフォルトの公開範囲を使用します。非公開のプレビューには認証とプロジェクトへのアクセス権が必要です。ビルドを誰でも共有できる場合にのみ、プロジェクト設定でプレビューを公開にしてください。公開設定にしても、プラットフォームの署名やデバイスのインストール要件が回避されるわけではありません。

## トラック {#tracks}

トラックは、内部テスター向けの `beta` や自動ビルド向けの `nightly` など、名前付きグループにプレビューを整理します。ワークフローに合わせて公開コマンドでトラックを指定してください。トラックは初回使用時に遅延作成されます。これらを使用して、目的別にプレビューをグループ化し、Tuist ダッシュボードでプレビューをフィルタリングできます。

## README バッジ {#readme-badge}

リポジトリの `README` に、最新のプレビューを指すバッジを追加します:

[![Tuist Preview](https://tuist.dev/Dimillian/IcySky/previews/latest/badge.svg)](https://tuist.dev/Dimillian/IcySky/previews/latest)

アカウントとプロジェクトのハンドルを自分のものに置き換えてください:

```markdown
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest)
```

プロジェクトに異なるバンドル識別子を持つ複数のアプリが含まれている場合は、`bundle-id` クエリパラメータを追加してアプリを選択します:

```markdown
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest?bundle-id=com.example.app)
```
