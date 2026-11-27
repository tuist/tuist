---
{
  "title": "Xcode プロジェクト",
  "titleTemplate": ":title · はじめに · ガイド · Tuist",
  "description": "プロジェクト生成を導入することなく、既存の Xcode プロジェクトを Tuist に接続し、Xcode コンパイルキャッシュ、ビルドとテストのインサイト、バンドルサイズ追跡、プレビューリンクを利用できます。"
}
---
# Xcode プロジェクト {#existing-xcode-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/existing-xcode-project
```

:::

プロジェクト生成を導入せずに、`.xcodeproj` や `.xcworkspace` をそのまま維持したまま Tuist の機能を取り入れたい場合は、この手順に従ってください。以下の各セクションでは、まず現在不足している点を示し、そのギャップを埋める機能について説明します。

## 前提条件

- **Xcode 26 以降** がインストールされた macOS（コンパイルキャッシュと最新のインサイト機能はこれに依存します）。
- <.localized_link href="/guides/install-tuist">Tuist コマンドラインインターフェース</.localized_link>。

## プロジェクトを接続する

リポジトリのルートで `tuist init` を実行してください。Tuist がワークスペースを検出したら **`<YourApp>` を統合** を選択し、ブラウザで認証を行って、プロジェクトを所有すべきアカウントを選択します。Tuist はルートに `Tuist.swift` を作成し、プロジェクトハンドルを固定することで、チームメンバーや CI が同じ接続を共有できるようにします。これをコミットしてください。

コーディングエージェントやスクリプトから実行する場合は、まず `tuist auth login` を実行し（ブラウザフローでは Enter キーを押すまで待機します）、その後、非対話形式のコマンドを使用してください。

```bash
tuist init --build-system xcode --name <project-handle> --account <account>
```

以下の内容はすべて任意であり、独立しています。

## Xcode コンパイルキャッシュ

Xcode 26 にはファイル単位のコンパイルキャッシュが付属していますが、そのストアはマシンの `DerivedData` 内に存在します。クリーンビルドを行うとローカルにキャッシュが生成されますが、チームメンバーや CI ランナーはそのストアを参照できないため、ゼロから再ビルドすることになります。

`tuist setup cache` は、Xcode のコンパイルキャッシュを共有 Tuist キャッシュネットワークに向けるように設定します。これにより、ある開発者マシンや CI 実行でキャッシュヒットが発生すると、同じリビジョンをビルドする他のすべてのマシンもその恩恵を受けられます。

```bash
tuist setup cache
```

このコマンドは、共有キャッシュを使用するために Xcode が必要なビルド設定を表示します。プロジェクト自体は編集されないため、表示された設定をプロジェクトのビルド設定または `.xcconfig` ファイルに追加してください。詳細は <.localized_link href="/guides/features/cache/xcode-cache#configure-xcode-build-settings">Xcode ビルド設定の構成</.localized_link> を参照してください。

Xcode でビルドを行い、その後、別のマシンまたは CI ランナーで同じリビジョンをビルドしてください。2 回目のビルドは大幅に短時間で完了し、Xcode のビルドレポートにコンパイルキャッシュのヒットが表示されます。

## ビルドインサイト

Xcode はターゲットごとのビルド所要時間をログとビルドレポートに記録しますが、これらのデータは実行間やマシン間で集計されません。ある PR でビルド時間の回帰が発生しても、CI 全体が遅くなるという現象として現れるだけで、どのターゲットが原因なのか、いつ発生したのかという明確な兆候は得られません。

ビルドインサイトは、すべてのビルドの所要時間とフェーズごとのタイミングを記録するため、ダッシュボード上で傾向を確認できます。スキームに 1 行のポストアクションを追加するだけです。

1. Xcode で：**Product → Scheme → Edit Scheme…**
2. **Build → Post-actions** を展開し、**+** をクリックして、**New Run Script Action** を選択します。
3. **Provide build settings from** の下で、アプリターゲットを選択します。
4. Tuist のインストール方法に合わせて、以下のいずれかの行を貼り付けてください。 ::: code-group
   ```bash [Mise]
   $HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect build
   ```
   ```bash [Homebrew]
   tuist inspect build
   ```
   <!-- -->
   :::

   Xcode のスキームスクリプトはシェルの `PATH` を継承しないため、mise の shim が自動的には見つかりません。上記の Mise の行では、mise を絶対パスで呼び出し、`$SRCROOT` から設定を読み込むよう指示することで、プロジェクトでピン留めされたバージョンを使用します。
5. 一度ビルドを実行してください。ビルド結果は数秒以内にダッシュボードの **Builds** タブに表示されます。

## テストインサイト

Xcode のテストログには、テスト結果が実行ごとに一覧表示されます。しかし、実際に必要なクロス実行のシグナル、例えばテストの失敗頻度、先週と比較した速度低下、特定のシミュレータでのみ失敗するかどうかといった情報は集計されません。10 回の CI 実行を通じて安定していたテストが不安定になっていく過程も、単に運が悪かった 1 回の実行と同じように見えてしまいます。

テストインサイトは、すべてのテストの結果と所要時間を記録し、実行間の結果を相関付けます。遅いテスト、失敗、および不安定なテスト（flakes）は、ダッシュボードの **Tests** タブに表示されます。

1. **Product → Scheme → Edit Scheme…**
2. **Test → Post-actions → +** → **New Run Script Action**。
3. アプリターゲットから **Provide build settings from** を選択します。
4. 以下を貼り付けてください。 ::: code-group
   ```bash [Mise]
   $HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect test
   ```
   ```bash [Homebrew]
   tuist inspect test
   ```
   <!-- -->
   :::
5. テストアクションを一度実行してください。結果はダッシュボードの **Tests** タブに表示されます。

## バンドルインサイト

IPA のインストールサイズとダウンロードサイズは、アセットが追加されるたび、シンボルがリンクされるたびに変動します。Xcode は **Product → Show Archive** でオンデマンドにサイズを報告しますが、時系列データとしては提供しません。大きなアセットを追加した PR も、マージキュー内の他の PR と区別がつきません。

バンドルインサイトは、分析されたすべてのビルドのインストールサイズとダウンロードサイズを記録し、ブランチごとの閾値を超えた場合に PR チェックを失敗させることができます。ビルドステップの直後に、CI に以下を追加してください。

```bash
tuist inspect bundle App.ipa
```

ダッシュボードで **Bundle insights** を開き、傾向を確認して閾値を設定してください。

## プレビュー

TestFlight では、共有するたびにビルドとレビューの往復が発生します。署名付きの `.ipa` を直接送信するには、プロビジョニングプロファイルに受信者の UDID を含める必要があります。現在のブランチを試したいだけのデザイナーや QA 担当者にとって、どちらも不便です。

プレビュー機能は、ビルドを共有可能なリンクに変換し、1 つのコマンドでシミュレータまたはデバイス上で実行できるようにします。

```bash
tuist xcodebuild build -scheme App -workspace App.xcworkspace -configuration Debug -sdk iphonesimulator
tuist share App
```

リンクを送信してください。受信者は `tuist run <url>` または Tuist macOS アプリを使用してそれを実行します。

## チームを巻き込む

キャッシュとインサイトの効果は、プロジェクトに接続する人数が増えるほど大きくなります。ダッシュボードのアカウント設定からチームメイトを組織に招待し、<.localized_link href="/guides/integrations/authentication/sso">Single Sign-On</.localized_link>（Google、Okta、Microsoft）を設定して、オンボーディングを一人ひとりの `tuist auth login` ではなくクリック操作で完了できるようにしましょう。

## 次のステップ

この手法では物足りなくなった場合、最大の前進は Tuist が生成するプロジェクトへの移行です。これは実質的な変更です（ターゲットを `.xcodeproj` ではなく Swift マニフェストで定義します）が、モジュールキャッシュと選択的テストを利用可能にするのはこのアプローチです。<.localized_link href="/guides/get-started/generated-xcode-project">Generated Xcode project</.localized_link> ガイドで端から端まで解説しています。
