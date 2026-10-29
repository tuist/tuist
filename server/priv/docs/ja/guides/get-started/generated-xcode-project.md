---
{
  "title": "Generated Xcode project",
  "titleTemplate": ":title · Get started · Guides · Tuist",
  "description": "Compress a modular Xcode project into declarative Swift and unlock module caching, selective testing, a package registry, and build and test insights on top of the graph."
}
---
# 生成されたXcodeプロジェクト {#generated-xcode-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/generated-xcode-project
```

:::

TuistにSwiftマニフェストからXcodeプロジェクトを記述・生成させたい場合は、この手順に従ってください。生成されたプロジェクトは、モジュラーなXcodeプロジェクトの複雑さを、グラフの簡潔で宣言的な記述に圧縮します。また、モジュールキャッシュと選択的テストには必須の要件です。

以下の各セクションでは、まず現在不足している点を示し、そのギャップを埋める機能について順を追って説明します。

## 前提条件

- XcodeがインストールされたmacOS。
- <.localized_link href="/guides/install-tuist">Tuistコマンドラインインターフェース</.localized_link>。

## プロジェクトの作成

動作を確認する最も早い方法は、新しいプロジェクトを作成することです。空のディレクトリで `tuist init` を実行し、**生成されたプロジェクトを作成** を選択してプラットフォームを選び、名前を確認した後、認証を行ってプロジェクトを所有するアカウントを選択してください。

```bash
mkdir MyApp && cd MyApp
tuist init
```

コーディングエージェントやスクリプトから実行する場合は、まず `tuist auth login` を実行してください（ブラウザフローではEnterキーを押すまで待機します）。その後、非インタラクティブな形式を使用します。

```bash
tuist init --build-system generated-xcode --name MyApp --platform ios --account <account>
```

initが完了したら、`tuist generate` を実行します。Tuistはマニフェストの隣に `.xcworkspace` を書き込み、Xcodeで開きます。ターゲットをビルドして実行してください。シミュレータでサンプルアプリが起動するはずです。

これが「接続＋生成」状態です。以下はすべて任意かつ独立しています。

既存のアプリを移行する場合は、まず [Xcodeプロジェクト移行ガイド](https://tuist.dev/en/docs/guides/features/projects/adoption/migrate/xcode-project) に従って接続し、その後戻ってきて、あなたの課題に適したセクションを続けてください。

## プロジェクト生成

`.xcodeproj` はアプリの構造をXMLにバンドルします。ファイル参照、ビルドフェーズ、ターゲット依存関係、スキーム、ビルド設定がすべて同じツリー内に存在し、グラフをグラフとして推論するためのプリミティブはありません。プロジェクトが大きくなるにつれて、その構造を頭の中で把握するのが難しくなり、Xcodeには変更がない場合にハッシュ化して作業をスキップするための安定したハンドルがありません。

生成されたプロジェクトは、グラフを宣言的なSwiftに圧縮します。`Project.swift` はターゲット、依存関係、リソースを直接記述し、Tuistはその背後でグラフの安定したモデルを維持します。このモデルこそが、以下のセクションを可能にします。モジュールキャッシングはそれをハッシュ化してバイナリを再利用し、選択的テストは入力に変更がないテストをスキップするためにハッシュ化します。

```swift
import ProjectDescription

let project = Project(
    name: "MyApp",
    targets: [
        .target(
            name: "MyApp",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.MyApp",
            sources: ["MyApp/Sources/**"],
            dependencies: []
        )
    ]
)
```

各 `tuist generate` はマニフェストから決定論的なワークスペースを生成します。`.xcodeproj` と `.xcworkspace` を `.gitignore` に追加してください。

## モジュールキャッシュ

モジュラーなXcodeプロジェクトをゼロからコンパイルすることは、マシンごとのコストがかかります。チームメンバー全員およびCIランナーそれぞれが、同じオブジェクトファイルのコピーを各自で作成します。Xcodeのコンパイルキャッシュは内側のループを短縮しますが、すべてのターゲットのマシンごとのビルドを排除することはできず、フレームワーク全体を事前構築済みバイナリで置き換えることもできません。

モジュールキャッシュはそれを行います。グラフ内のキャッシュ可能なすべての依存関係（フレームワーク、ライブラリ、バンドル）を一度ビルドし、結果のバイナリをターゲットの入力のハッシュ値に関連付けて保存し、後続の生成ではターゲットをそのバイナリに置き換えます。変更されていないモジュールはコンパイルされなくなります。

```bash
tuist cache
```

初回実行ではすべてをコンパイルし、バイナリをあなたのアカウントにアップロードします。次の `tuist generate` では、変更されていない依存関係はキャッシュされたバイナリに置き換えられ、Xcodeはソースからコンパイルする代わりに `.xcframework` に対してリンクします。

## 選択的テスト

`xcodebuild test` は変更がどのテストに影響するかを認識しないため、CIはプッシュごとにスイート全体を実行します。スイートが大きくなるにつれて、実際に実行が必要なものと実行されるものの間のギャップは、数分から数十分に広がります。

選択的テストは、プロジェクトグラフとモジュールキャッシュが依存する同じハッシュアルゴリズムを使用して、最後の成功したテスト実行以降に変更があった影響を受けるテストのみを実行します。

```bash
tuist test
```

最初の `tuist test` はすべてを実行し、ターゲットごとのハッシュを永続化します。後続の実行では、入力に変更がないターゲットをスキップします。`tuist test` をCIで `xcodebuild test` の代わりに使用するように変更すれば、フィードバックが数分ではなく数秒で得られます。

## パッケージレジストリ

Swift Package Managerは、パッケージがレジストリではなくURLで指定されるため、各パッケージのgit履歴を深くクローンすることで依存関係を解決します。推移的なパッケージが数十あるプロジェクトでは、クリーンチェックアウト時の解決に数分かかり、それがすべてのCIジョブで繰り返されます。

Tuist Package Registryは、Swift Package Indexが追跡している同じパッケージを提供しますが、実際のレジストリとして機能するため、SwiftPMは実際に必要なコミットのみを取得します。`Tuist.swift` で `registryEnabled: true` を設定することで一度有効にしてください。

```swift
let tuist = Tuist(
    project: .tuist(
        generationOptions: .options(
            registryEnabled: true
        )
    )
)
```

再生成してください。パッケージ解決時間が数分から数秒に短縮されます。

## ビルドインサイト

Xcodeはターゲットごとのビルド時間をログとビルドレポートに記録します。いずれも実行間やマシン間で集計されないため、ビルド時間の回帰は通常、CI全体の低速化としてのみ表面化します。

ビルドインサイトは、生成されたスキームのビルド時間とフェーズタイミングを自動的に記録します。追加の設定は不要です。次の `tuist generate` ＋ビルドサイクル後に、ダッシュボードの **ビルド** タブを開いてください。

## テストインサイト

Xcodeはテストごとの結果を1回の実行ごとに報告します。実際には必要なクロスランのシグナル、つまり不安定率、週ごとの持続時間、どのシミュレータバリアントが失敗するかを集計しません。

テストインサイトは、生成されたスキームのテスト結果と持続時間を自動的に記録し、実行間で結果を相関付けます。不安定なテスト、遅いテスト、失敗はダッシュボードの **テスト** タブに表示されます。不安定さが蓄積された場合は、ダッシュボードから隔離してマージをブロックしないようにしてください。

## チームを巻き込む

モジュールキャッシュと選択的テストは、全員が同じ共有 surface にアクセスしているときに最大の効果を発揮します。ダッシュボードのアカウント設定からチームメイトを組織に招待し、<.localized_link href="/guides/integrations/authentication/sso">シングルサインオン</.localized_link>（Google、Okta、Microsoft）を設定して、オンボーディングを個人ごとの `tuist auth login` ではなくクリックだけで完了できるようにしてください。
