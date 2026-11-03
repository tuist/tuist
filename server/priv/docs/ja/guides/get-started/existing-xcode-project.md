---
{
  "title": "Xcode プロジェクト",
  "titleTemplate": ":title · はじめに · ガイド · Tuist",
  "description": "既存の Xcode プロジェクトを Tuist に接続して、Xcode コンパイルキャッシュ、ビルドおよびテストの分析、バンドルサイズ追跡、プレビューリンクを利用できます。プロジェクト生成を導入する必要はありません。"
}
---
# Xcode プロジェクト {#existing-xcode-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/existing-xcode-project
```

:::

プロジェクト生成を採用せずに、`.xcodeproj` や `.xcworkspace` をそのまま維持したまま Tuist の機能を取り入れたい場合は、この手順に従ってください。以下の各セクションでは、まず現状で不足している点を示し、そのギャップを埋める機能を順に説明します。

## 前提条件

- **Xcode 26以降**がインストールされたmacOS（コンパイルキャッシュと最新のインサイト機能はこれに依存します）。
- <.localized_link href="/guides/install-tuist">Tuist コマンドラインインターフェース</.localized_link>。

## プロジェクトの接続

リポジトリのルートで `tuist init` を実行します。Tuist がワークスペースを検出したら **Integrate `<YourApp>`** を選択し、ブラウザで認証を行って、プロジェクトを所有するアカウントを選択します。Tuist はルートに `Tuist.swift` を書き込み、プロジェクトハンドルを固定することで、チームメンバーや CI が同じ接続を共有できるようにします。これをコミットしてください。

コーディングエージェントやスクリプトから実行する場合は、まず `tuist auth login` を実行します（ブラウザフローでは Enter キーを押すまで待機します）。その後、非インタラクティブな形式を使用します。

```bash
tuist init --build-system xcode --name <project-handle> --account <account>
```

以下はすべて任意であり、独立しています。

## Xcode コンパイルキャッシュ

Xcode 26 にはファイルごとのコンパイルキャッシュが付属していますが、そのストアはマシンの `DerivedData` 内にあります。クリーンビルドを行うとローカルにキャッシュが作成されますが、チームメンバーや CI ランナーはそのストアを参照できないため、ゼロから再ビルドすることになります。

`tuist setup cache` は、Xcode のコンパイルキャッシュを共有された Tuist キャッシュネットワークに向けます。これにより、ある開発者マシンや CI 実行でのキャッシュヒットが、同じリビジョンをビルドする他のすべてのマシンにも恩恵をもたらします。

```bash
tuist setup cache
```

Xcode でビルドを行います。Derived Data を削除し、別のマシンまたは CI ランナーで再度ビルドします。2 回目のビルドはほんのわずかな時間で完了し、Xcode のビルドレポートにコンパイルキャッシュのヒットが表示されます。

## ビルドインサイト

Xcode はターゲットごとのビルド時間をログとビルドレポートに記録しますが、実行間やマシン間で集計されることはありません。ある PR で発生したビルド時間の回帰は、通常、CI 全体が遅くなるという形でしか表面化せず、どのターゲットが原因なのか、いつ発生したのかという明確なシグナルは得られません。

ビルドインサイトは、すべてのビルドの所要時間とフェーズのタイミングを記録するため、ダッシュボード上で傾向を確認できます。スキームに追加するポストアクションは 1 行だけです。

1. Xcode で：**Product → Scheme → Edit Scheme…**
2. **Build → Post-actions** を展開し、**+** をクリックして、**New Run Script Action** を選択します。
3. **Provide build settings from** の下で、アプリターゲットを選択します。
4. Tuist のインストール方法に合わせて、以下のいずれかの行を貼り付けます。 ::: code-group
   ```bash [Mise]
   $HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect build
   ```
   ```bash [Homebrew]
   tuist inspect build
   ```
   <!-- -->
   :::

   Xcode のスキームスクリプトはシェルの `PATH` を継承しないため、mise の shim は自動的には見つかりません。上記の Mise の行では、mise を絶対パスで呼び出し、`$SRCROOT` から設定を読み込むよう指示することで、プロジェクトでピン留めされたバージョンを選択します。
5. 一度ビルドを実行します。ビルドは数秒以内にダッシュボードの **Builds** タブに表示されます。

## テストインサイト

Xcode のテストログには、テスト結果が実行ごとに一覧表示されます。しかし、実際に必要なクロス実行のシグナル、つまりテストの失敗頻度、先週からどれだけ遅くなったか、特定のシミュレーターでのみ失敗するかどうかといった情報は集計されません。10 回の CI 実行を通じて信頼性のあるテストが不安定になっていく様子も、単に運が悪かった 1 回の実行と同じように見えてしまいます。

テストインサイトは、すべてのテストの結果と所要時間を記録し、実行間の結果を相関させます。遅いテスト、失敗、不安定なテストは、ダッシュボードの **Tests** タブに表示されます。

1. **Product → Scheme → Edit Scheme…**
2. **Test → Post-actions → +** → **New Run Script Action**。
3. アプリターゲットから **Provide build settings from**。
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

IPA のインストールサイズとダウンロードサイズは、アセットが追加されたりシンボルがリンクされたりするたびに変動します。Xcode は **Product → Show Archive** でオンデマンドにサイズを報告しますが、時系列としては提供しません。大きなアセットを追加した PR も、マージキュー内の他の PR と見分けがつきません。

バンドルインサイトは、分析されたすべてのビルドのインストールサイズとダウンロードサイズを記録し、ブランチごとの閾値を超えた場合に PR チェックを失敗させることができます。ビルドステップの直後にこれを CI に追加します。

```bash
tuist inspect bundle App.ipa
```

ダッシュボードで **Bundle insights** を開き、傾向を確認して閾値を設定します。

## プレビュー

TestFlight では、共有するたびにビルドとレビューの往復が発生します。署名付きの `.ipa` を直接送信するには、プロビジョニングプロファイルに受信者の UDID が必要です。現在のブランチを試したいだけのデザイナーや QA にとっては、どちらも不便です。

プレビューは、ビルドを共有可能なリンクに変換し、1 つのコマンドでシミュレーターまたはデバイス上で実行できるようにします。

```bash
tuist xcodebuild build -scheme App -workspace App.xcworkspace -configuration Debug -sdk iphonesimulator
tuist share App
```

リンクを送信します。受信者は `tuist run <url>` または Tuist macOS アプリを使用して実行します。

## チームを巻き込む

キャッシュとインサイトは、プロジェクトに接続する人数が増えるほど効果を発揮します。ダッシュボードのアカウント設定からチームメイトを組織に招待し、<.localized_link href="/guides/integrations/authentication/sso">Single Sign-On</.localized_link>（Google、Okta、Microsoft）を設定して、オンボーディングを一人ひとりの `tuist auth login` ではなくクリックだけで完了できるようにしましょう。

## 次のステップ

この方法では物足りなくなった場合、次の大きな一歩は Tuist が生成するプロジェクトへの移行です。これは実際の変更であり（ターゲットが `.xcodeproj` ではなく Swift マニフェストで記述されます）、モジュールキャッシュと選択的テストを利用可能にする鍵となります。<.localized_link href="/guides/get-started/generated-xcode-project">Generated Xcode project</.localized_link> ガイドで端から端まで解説しています。
