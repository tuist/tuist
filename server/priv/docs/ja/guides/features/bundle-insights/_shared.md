## バンドルサイズの理解 {#understanding-sizes}

Tuistは、分析対象の各バンドルについて以下の2つの値を報告します。

- **インストールサイズ**: デバイスにインストールされたアプリが占める領域。
- **ダウンロードサイズ**: ユーザーがダウンロードする圧縮後のサイズ。Apple バンドルの場合、これは `.ipa`（アーカイブのサイズ）に対してのみ報告されます。`.xcarchive` または `.app` を入力とした場合は利用できません。

サイズはバイト単位で保存され、10進法の規則に従って表示されます。この規則では 1 MB は 1,000,000 バイト、1 GB は 1,000,000,000 バイトです。これは Apple がストレージ容量やアプリサイズを報告する際に使用する規則と同じです（[Apple デバイスでのストレージ容量の測定方法](https://support.apple.com/en-us/102119)を参照）。インストールサイズが 733,446,863 バイトの場合、733.4 MB と表示されます。

## 継続的インテグレーション {#continuous-integration}

時間経過に伴うバンドルサイズを追跡するには、CI でバンドルを分析してください。まず、CI が <.localized_link href="/guides/integrations/continuous-integration#authentication">認証済み</.localized_link>であることを確認してください。

また、Tuist はどのプロジェクトにバンドルを報告するかを知る必要があります。プロジェクトをまだ接続していない場合は、`tuist init`を実行するか、ハンドルを自分で宣言してください。

::: code-group
```swift [Tuist.swift]
let tuist = Tuist(fullHandle: "my-account/my-project")
```
```toml [tuist.toml]
project = "my-account/my-project"
```
<!-- -->
:::

Swift マニフェストのないプロジェクト（Gradle プロジェクトなど）には、<.localized_link href="/references/tuist-toml">`tuist.toml`</.localized_link>を使用してください。両方のファイルが存在する場合、`Tuist.swift`が優先されます。

GitHub Actions ワークフローの例：

::: code-group
```yaml [Apple]
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
```yaml [Android]
name: Build

jobs:
  build:
    steps:
      - # Build your app
      - name: Analyze bundle
        # .aab is recommended over .apk for more accurate size analysis
        run: tuist inspect bundle App.aab
        env:
          TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}
```
<!-- -->
:::

設定が完了すると、時間経過に伴うバンドルサイズの変化を確認できます。

![バンドルサイズグラフ](/images/guides/features/bundle-size/bundle-size-graph.png)

## プルリクエスト／マージリクエストのコメント {#pullmerge-request-comments}

> [!WARNING]
> **Git プラットフォームとの連携が必要**
>
> プルリクエスト／マージリクエストへの自動コメントを取得するには、<.localized_link href="/guides/server/accounts-and-projects">Tuist プロジェクト</.localized_link>を <.localized_link href="/guides/server/authentication">Git プラットフォーム</.localized_link>と連携させてください。

Tuist プロジェクトが [GitHub](https://github.com) などの Git プラットフォームと接続されると、`tuist inspect bundle`を実行するたびに Tuist がプルリクエスト／マージリクエストに直接コメントを投稿します。

![検査済みバンドルを含む GitHub アプリのコメント](/images/guides/features/bundle-size/github-app-with-bundles.png)

## サイズしきい値 {#size-thresholds}

> [!WARNING]
> **Git フォージとの連携が必要**
>
> サイズしきい値を使用するには、[Tuist GitHub App](https://github.com/apps/tuist)をプロジェクトに接続してください。これはプロジェクトの統合ページから実行できます。

サイズしきい値を使用すると、ベースラインブランチと比較してバンドルサイズが設定されたパーセンテージまたは絶対サイズを超えて増加した場合に、プルリクエストをブロックできます。しきい値が違反されると、Tuist は PR コミットに GitHub チェックランを作成し、サイズの増加が解決されるまでマージをブロックします。

![バンドルサイズのしきい値超過を示す PR ステータスチェック](/images/guides/features/bundle-size/github-pr-check-status.png)

チェックランには、ベースラインサイズ、現在のサイズ、および設定された単位での増減が表示されます。増加が意図的なものである場合は、GitHub UI から **承認** ボタンをクリックして直接承認できます。

![しきい値違反を示す GitHub チェックラン](/images/guides/features/bundle-size/github-check-run-threshold.png)

### 設定 {#size-thresholds-configuration}

しきい値を設定するには、プロジェクトの **設定 > バンドル** タブに移動してください。

![バンドルサイズのしきい値設定](/images/guides/features/bundle-size/bundle-size-thresholds.png)

**インストールサイズ** または **ダウンロードサイズ** を選択し、次に **しきい値のタイプ** を選択してください。

- **パーセンテージ (%)**: ベースラインサイズに対する相対的な増加を制限します。`0.47` のような小数点以下のパーセンテージもサポートされています。既存のパーセンテージしきい値は、設定された値と動作を維持します。
- **絶対サイズ (MB)**: ベースラインサイズとは無関係に、固定量で増加を制限します。最大 1.5 MB の増加を許可するには `1.5` と入力してください。MB は10進単位を使用します。1 MB = 1,000,000 バイトです。値は正の整数バイトに解決される必要があります。

![絶対バンドルサイズ増加しきい値の設定](/images/guides/features/bundle-size/absolute-size-threshold.png)

どちらのタイプも、設定された **ベースラインブランチ** 上の最新のバンドルと比較されます。比較対象は、同じ名前、同じバンドルタイプ（例：`.app` または `.ipa`）、そして少なくとも1つの共通プラットフォームを持つものです。したがって、シミュレータ用 `.app` はシミュレータ用 `.app` のアップロードとのみ比較されます。オプションの **バンドル名** を指定すると、ルールはそのバンドルに限定されます。チェックが失敗するのは、増加が制限を **超える** 場合のみです。増加量が制限と等しい場合、サイズが変わらない場合、および減少した場合は通過します。一致するベースラインがない場合、または選択した指標の記録されたサイズがない場合、ルールはスキップされます。絶対制限の場合はゼロサイズのベースラインがサポートされますが、パーセンテージ増加は未定義であるため、パーセンテージ制限では引き続きスキップされます。

### 承認可能なユーザーの制限 {#size-thresholds-approvals}

デフォルトでは、リポジトリへの書き込みアクセス権を持つ誰でもサイズの増加を承認できます。これは、GitHub がそのボタンを表示する対象だからです。範囲を狭めるには、**設定 > バンドル** の下にある **承認可能なユーザー** を設定してください。

- **全員**: デフォルト。リポジトリへの書き込みアクセス権を持つすべてのユーザー。
- **選択した GitHub ユーザー**: 追加した GitHub ユーザー名のみ。

リストにいないユーザーは、説明付きでチェックを失敗させたままにし、ボタンは使用可能なユーザーのために残ります。
