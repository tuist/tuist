---
{
  "title": "Xcode プロジェクト",
  "titleTemplate": ":title · はじめに · ガイド · Tuist",
  "description": "プロジェクト生成を採用することなく、既存の Xcode プロジェクトを Tuist に接続し、Xcode コンパイルキャッシュ、ビルドおよびテストのインサイト、バンドルサイズ追跡、プレビューリンクを利用できます。"
}
---
# Xcodeプロジェクト {#existing-xcode-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/existing-xcode-project
```

:::

`.xcodeproj`や`.xcworkspace`をそのまま維持しつつ、プロジェクト生成を導入せずにTuistの機能を取り入れたい場合は、この手順に従ってください。以下の各セクションでは、まず現状で不足している点を示し、そのギャップを埋める機能を順に説明します。

## 前提条件

- **Xcode 26以降**を搭載したmacOS（コンパイルキャッシュと最新のインサイト機能はこれに依存します）。
- <.localized_link href="/guides/install-tuist">Tuistコマンドラインインターフェース</.localized_link>。

## プロジェクトを接続する

リポジトリのルートで`tuist init`を実行してください。Tuistがワークスペースを検出したら **`<YourApp>`を統合**を選択し、ブラウザで認証して、プロジェクトを所有すべきアカウントを選びます。Tuistはルートに`Tuist.swift`を作成し、プロジェクトハンドルを固定することで、チームメンバーやCIが同じ接続を共有できるようにします。これをコミットしてください。

コーディングエージェントやスクリプトから実行する場合は、まず`tuist auth login`を実行し（ブラウザフローではEnterキーを押すまで待機します）、その後、非インタラクティブな形式を使用してください：

```bash
tuist init --build-system xcode --name <project-handle> --account <account>
```

以下はすべて任意であり、独立しています。

## Xcodeコンパイルキャッシュ

Xcode 26にはファイルごとのコンパイルキャッシュが付属していますが、そのストアはマシンの`DerivedData`内にあります。クリーンビルドするとローカルにキャッシュが蓄積されますが、チームメンバーやCIランナーはそのストアを参照できないため、ゼロから再ビルドすることになります。

`tuist setup cache`は、Xcodeのコンパイルキャッシュを共有されたTuistキャッシュネットワークに向けます。これにより、ある開発者マシンやCI実行でキャッシュヒットが発生すると、同じリビジョンをビルドする他のすべてのマシンも恩恵を受けられます。

```bash
tuist setup cache
```

このコマンドは、共有キャッシュを使用するためにXcodeが必要とするビルド設定を表示します。プロジェクト自体は編集しないため、これらの設定をプロジェクトのビルド設定または`.xcconfig`ファイルに追加してください。詳細は<.localized_link href="/guides/features/cache/xcode-cache#configure-xcode-build-settings">Xcodeビルド設定の構成</.localized_link>をご覧ください。

Xcodeでビルドした後、同じリビジョンを別のマシンまたはCIランナーでビルドしてください。2回目のビルドはごく短時間で完了し、Xcodeのビルドレポートにはコンパイルキャッシュのヒットが表示されます。

## ビルドインサイト

Xcodeはターゲットごとのビルド時間をログとビルドレポートに記録しますが、実行間やマシン間で集計されることはありません。1つのPRで発生したビルド時間の悪化は、通常、CI全体の遅延としてのみ現れ、どのターゲットが原因なのか、いつ発生したのかという明確な兆候は残りません。

ビルドインサイトは、すべてのビルドの所要時間とフェーズごとのタイミングを記録するため、ダッシュボードで傾向を確認できます。スキームに1行のポストアクションを追加するだけです：

1. Xcodeで：**Product → Scheme → Edit Scheme…**
2. **Build → Post-actions**を展開し、**+** をクリックして、**New Run Script Action**を選択します。
3. **Provide build settings from**の下で、アプリターゲットを選択します。
4. Tuistのインストール方法に合わせて、以下の行を貼り付けてください： ::: code-group
   ```bash [Mise]
   $HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect build
   ```
   ```bash [Homebrew]
   tuist inspect build
   ```
   <!-- -->
   :::

   Xcodeのスキームスクリプトはシェルの`PATH`を継承しないため、miseのshimは自動的には見つかりません。上記のMise用の行では、miseを絶対パスで呼び出し、`$SRCROOT`から設定を読み込むよう指示することで、プロジェクトでピン留めされたバージョンを選択させます。
5. 一度ビルドしてください。ビルド結果は数秒以内にダッシュボードの**Builds**タブに表示されます。

## テストインサイト

Xcodeのテストログには、テスト結果が実行ごとに一覧表示されます。しかし、実際に必要なクロス実行のシグナル、つまりテストの失敗頻度、先週と比べてどれだけ遅くなったか、特定のシミュレーターでのみ失敗するかどうかなどは集計されません。10回のCI実行を経て信頼性のある状態からflakyな状態へと drifted したテストも、単に運が悪かった1回の実行と同じように見えてしまいます。

テストインサイトは、すべてのテストの結果と所要時間を記録し、実行間の結果を相関付けます。低速なテスト、失敗、flakyなテストは、ダッシュボードの**Tests**タブに表示されます。

1. **Product → Scheme → Edit Scheme…**
2. **Test → Post-actions → +** → **New Run Script Action**。
3. アプリターゲットから**Provide build settings from**を選択します。
4. 貼り付け： ::: code-group
   ```bash [Mise]
   $HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect test
   ```
   ```bash [Homebrew]
   tuist inspect test
   ```
   <!-- -->
   :::
5. テストアクションを一度実行してください。結果はダッシュボードの**Tests**タブに表示されます。

## バンドルインサイト

IPAのインストールサイズとダウンロードサイズは、追加されるアセットやリンクされるシンボルごとに変わります。Xcodeは**Product → Show Archive**でオンデマンドにサイズを報告しますが、時系列としては提供しません。大きなアセットを追加したPRも、マージキュー内の他のPRと区別がつきません。

バンドルインサイトは、分析対象のすべてのビルドについてインストールサイズとダウンロードサイズを記録し、ブランチごとの閾値を超えた場合にPRチェックを失敗させることができます。ビルドステップの直後にこれをCIに追加してください：

```bash
tuist inspect bundle App.ipa
```

ダッシュボードで**Bundle insights**を開き、傾向を確認して閾値を設定します。

## プレビュー

TestFlightでは、共有ごとにビルドとレビューの往復が発生します。署名付き`.ipa`を直接送信するには、プロビジョニングプロファイルに受信者のUDIDが必要です。どちらも、現在のブランチを試したいだけのデザイナーやQAにとっては不便です。

プレビューは、ビルドを共有可能なリンクに変換し、1つのコマンドでシミュレーターまたはデバイス上で実行できるようにします：

```bash
tuist xcodebuild build -scheme App -workspace App.xcworkspace -configuration Debug -sdk iphonesimulator
tuist share App
```

リンクを送信します。受信者は`tuist run <url>`またはTuist macOSアプリを使用して実行します。

## チームを巻き込む

キャッシュとインサイトの効果は、プロジェクトに接続する人数が増えるほど高まります。ダッシュボードのアカウント設定からチームメンバーを組織に招待し、<.localized_link href="/guides/integrations/authentication/sso">Single Sign-On</.localized_link>（Google、Okta、Microsoft）を設定して、オンボーディングを一人ひとりの`tuist auth login`ではなくワンクリックで済むようにしましょう。

## 次のステップ

このアプローチでは物足りなくなったら、次はTuistが生成するプロジェクトへの移行が大きな一歩です。これは実際の変更です（ターゲットを`.xcodeproj`ではなくSwiftマニフェストで記述します）が、モジュールキャッシュと選択的テストを利用可能にするのはこれです。<.localized_link href="/guides/get-started/generated-xcode-project">Generated Xcode project</.localized_link>ガイドで端到端の手順を解説しています。
