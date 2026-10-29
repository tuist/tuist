---
{
  "title": "Xcode project",
  "titleTemplate": ":title · Get started · Guides · Tuist",
  "description": "Connect an existing Xcode project to Tuist for the Xcode compilation cache, build and test insights, bundle-size tracking, and preview links, without adopting project generation."
}
---
# Xcode プロジェクト {#existing-xcode-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/existing-xcode-project
```

:::

プロジェクト生成を採用せずに、`.xcodeproj` や `.xcworkspace` をそのまま維持したまま Tuist の機能を取り入れたい場合は、この手順に従ってください。以下の各セクションでは、現在不足しているものを最初に示し、そのギャップを埋める機能について順を追って説明します。

## 前提条件

- **Xcode 26以降**を搭載したmacOS（コンパイルキャッシュと最新のインサイト機能はこれに依存します）。
- <.localized_link href="/guides/install-tuist">Tuist コマンドラインインターフェース</.localized_link>。

## プロジェクトの接続

リポジトリのルートで `tuist init` を実行します。Tuist がワークスペースを検出したら **Integrate `<YourApp>`** を選択し、ブラウザで認証を行って、プロジェクトを所有すべきアカウントを選択します。Tuist はルートに `Tuist.swift` を書き込み、プロジェクトハンドルを固定することで、チームメンバーや CI が同じ接続を共有できるようにします。これをコミットしてください。

コーディングエージェントやスクリプトからこれを実行する場合は、まず `tuist auth login` を実行し（ブラウザフローでは Enter キーを押すまで待機します）、その後、非インタラクティブな形式を使用します。

```bash
tuist init --build-system xcode --name <project-handle> --account <account>
```

以下はすべて任意であり、独立しています。

## Xcode コンパイルキャッシュ

Xcode 26 にはファイルごとのコンパイルキャッシュが付属していますが、そのストアはマシンの `DerivedData` 内にあります。クリーンビルドを行うとローカルにキャッシュが作成されますが、チームメンバーや CI ランナーはそのストアを参照できないため、ゼロから再ビルドすることになります。

`tuist setup cache` は、Xcode のコンパイルキャッシュを共有された Tuist キャッシュネットワークに向けます。これにより、ある開発者マシンや CI 実行でキャッシュヒットが発生すると、同じリビジョンをビルドする他のすべてのマシンも恩恵を受けます。

```bash
tuist setup cache
```

Xcode でビルドを行います。Derived Data を消去し、別のマシンまたは CI ランナーで再度ビルドします。2 回目のビルドはほんのわずかな時間で完了し、Xcode のビルドレポートにはコンパイルキャッシュのヒットが表示されます。

## ビルドインサイト

Xcode はターゲットごとのビルド時間をログとビルドレポートに記録しますが、これらは実行間やマシン間で集計されません。ある PR で発生したビルド時間の回帰は、通常、CI 全体が遅くなるという形でしか表面化せず、どのターゲットが原因なのか、いつ発生したのかという明確な兆候はありません。

ビルドインサイトは、すべてのビルドの所要時間とフェーズのタイミングを記録するため、ダッシュボード上で傾向を確認できます。スキームに対するワンライナーのポストアクションとして設定します。

1. Xcode で：**Product → Scheme → Edit Scheme…**
2. **Build → Post-actions** を展開し、**+** をクリックして、**New Run Script Action** を選択します。
3. **Provide build settings from** の下で、アプリターゲットを選択します。
4. Tuist のインストール方法に合わせて、以下の行を貼り付けます。 ::: code-group
   ```bash [Mise]
   $HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect build
   ```
   ```bash [Homebrew]
   tuist inspect build
   ```
   <!-- -->
   :::

   Xcode のスキームスクリプトはシェルの `PATH` を継承しないため、mise の shim は自動的には見つかりません。上記の Mise の行では、mise を絶対パスで呼び出し、`$SRCROOT` から設定を読み込むように指示することで、プロジェクトでピン留めされたバージョンを選択します。
5. 一度ビルドを行います。ビルドは数秒以内にダッシュボードの **Builds** タブに表示されます。

## テストインサイト

Xcode のテストログには、テスト結果が実行ごとに一覧表示されます。しかし、実際に必要なクロスランの信号、つまりテストが失敗する頻度、先週からどれだけ遅くなったか、特定のシミュレーターでのみ失敗するかどうかといった情報は集計されません。10 回の CI 実行を通じて信頼性のあるテストが不安定になっていく様子も、単に運が悪かった 1 回の実行と同じように見えてしまいます。

テストインサイトは、すべてのテストの結果と所要時間を記録し、実行間の結果を相関させます。遅いテスト、失敗、および不安定なテストは、ダッシュボードの **Tests** タブに表示されます。

1. **Product → Scheme → Edit Scheme…**
2. **Test → Post-actions → +** → **New Run Script Action**。
3. アプリターゲットから **Provide build settings from** を設定します。
4. 貼り付け： ::: code-group
   ```bash [Mise]
   $HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect test
   ```
   ```bash [Homebrew]
   tuist inspect test
   ```
   <!-- -->
   :::
5. テストアクションを一度実行します。結果はダッシュボードの **Tests** タブに表示されます。

## バンドルインサイト

IPA のインストールサイズとダウンロードサイズは、追加されるアセットやリンクされるシンボルごとに変化します。Xcode は **Product → Show Archive** でオンデマンドにサイズを報告しますが、時系列としては報告しません。大きなアセットを追加した PR は、マージキュー内の他の PR と区別がつきません。

バンドルインサイトは、分析されたすべてのビルドのインストールサイズとダウンロードサイズを記録し、ブランチごとの閾値を超えた場合に PR チェックを失敗させることができます。ビルドステップの直後にこれを CI に追加します。

```bash
tuist inspect bundle App.ipa
```

ダッシュボードで **Bundle insights** を開き、傾向を確認して閾値を設定します。

## プレビュー

TestFlight では、共有するたびにビルドとレビューの往復が発生します。署名付きの `.ipa` を直接送信するには、プロビジョニングプロファイルに受信者の UDID が必要です。現在のブランチを試したいだけのデザイナーや QA にとっては、どちらも不便です。

プレビューは、ビルドをシミュレーターまたはデバイスでワンコマンドで実行できる共有可能なリンクに変換します。

```bash
tuist xcodebuild build -scheme App -workspace App.xcworkspace -configuration Debug -sdk iphonesimulator
tuist share App
```

リンクを送信します。受信者は `tuist run <url>` または Tuist macOS アプリを使用してそれを実行します。

## チームを巻き込む

キャッシュとインサイトの効果は、プロジェクトに接続している人数に応じて増幅されます。ダッシュボードのアカウント設定からチームメイトを組織に招待し、<.localized_link href="/guides/integrations/authentication/sso">シングルサインオン</.localized_link>（Google、Okta、Microsoft）を設定して、オンボーディングを一人ひとりの `tuist auth login` ではなくワンクリックで完了できるようにしましょう。

## 次のステップ

この方法では物足りなくなった場合、最も大きなステップは Tuist が生成するプロジェクトへの移行です。これは実際の変更です（ターゲットが `.xcodeproj` ではなく Swift マニフェストで記述されます）が、モジュールキャッシュと選択的テストを有効にするのはこれです。<.localized_link href="/guides/get-started/generated-xcode-project">Generated Xcode project</.localized_link> ガイドで端到端で説明されています。
