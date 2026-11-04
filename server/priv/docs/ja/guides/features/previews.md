---
{
  "title": "Previews",
  "titleTemplate": ":title · 機能 · ガイド · Tuist",
  "description": "Tuist Previews を使ってモバイルアプリ、デスクトップアプリ、コマンドラインツールを共有し、チームメンバーがローカルで再ビルドせずにビルドを試せるようにします。"
}
---
# プレビュー {#previews}

Tuist Previews を使えば、チームメンバーはモバイルアプリ、デスクトップアプリ、コマンドラインツールをローカルで再ビルドせずに試せます。ビルドを Tuist プロジェクトに公開し、そのプレビューリンクを共有してください。

## プレビュー可能なもの {#what-you-can-preview}

- **モバイルアプリ:** Android APK および Apple アプリケーションバンドルまたは IPA。サポートされるデバイス、シミュレータ、署名要件は公開ワークフローによって異なります。
- **デスクトップアプリ:** macOS アプリケーションバンドル。
- **コマンドラインツール:** macOS または Linux の実行ファイル。単独、または依存関係とバンドルされた状態。

パッケージングと互換性の要件については <.localized_link href="/guides/features/previews/types">サポートされるタイプ</.localized_link> を参照してください。アーティファクトのタイプはプレビューの実行先を決定しますが、どのビルドシステムが生成するかを規定するものではありません。

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
    details="Gradle プロジェクトから Android アプリおよびネイティブのコマンドラインツールを共有します。"
    link="/guides/features/previews/gradle"
  />
  <.home_card
    title="Bazel"
    details="付随する Bazel ルールを使用して、Android アプリ、Apple アプリ、およびコマンドラインツールを共有します。"
    link="/guides/features/previews/bazel"
  />
</.home_cards>

すでにサポートされているビルドがある場合は、<.localized_link href="/cli/share">`tuist share`</.localized_link> を使用して、ビルドシステムの統合なしで公開できます。パッケージングと署名の要件は引き続き適用されます。

## プレビューを実行する {#run-a-preview}

受信側はプレビューを生成したビルドシステムを必要としません。互換性のあるビルドへのアクセス方法を選択してください:

<.home_cards>
  <.home_card
    title="CLI"
    details="tuist run でモバイルアプリ、macOS アプリ、およびコマンドラインのプレビューを実行します。"
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

## 可視性 {#visibility}

プレビューはプロジェクトのデフォルトの可視性を使用します。非公開のプレビューには認証とプロジェクトへのアクセス権が必要です。ビルドを誰でも共有できる場合のみ、プロジェクト設定でプレビューを公開にしてください。公開可視性はプラットフォームの署名やデバイスインストールの要件を bypass しません。

## トラック {#tracks}

トラックはプレビューを名前付きグループに整理します。例えば、内部テスター向けに `beta`、自動ビルド向けに `nightly` などです。ワークフローに合わせて公開コマンドでトラックを指定してください。トラックは初回使用時に遅延作成されます。目的別にプレビューをグループ化し、Tuist ダッシュボードでプレビューをフィルタリングするために使用します。

## README バッジ {#readme-badge}

リポジトリの `README` に、最新のプレビューを指すバッジを追加します:

[![Tuist Preview](https://tuist.dev/Dimillian/IcySky/previews/latest/badge.svg)](https://tuist.dev/Dimillian/IcySky/previews/latest)

アカウントとプロジェクトのハンドルを自分のものに置き換えてください:

```markdown
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest)
```

プロジェクトに異なるバンドル識別子を持つ複数のアプリが含まれている場合は、アプリを選択するために `bundle-id` クエリパラメータを追加します:

```markdown
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest?bundle-id=com.example.app)
```
