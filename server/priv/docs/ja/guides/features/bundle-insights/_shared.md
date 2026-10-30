## バンドルサイズの理解 {#understanding-sizes}

解析された各バンドルについて、Tuist は 2 つの値を報告します。

- **インストールサイズ**: デバイスにインストールされたアプリが占有する領域。
- **ダウンロードサイズ**: ユーザーがダウンロードする圧縮後のサイズ。Apple のバンドルでは `.ipa`（アーカイブのサイズ）に対してのみ報告され、`.xcarchive` または `.app` を入力とした場合は利用できません。

サイズはバイト単位で保存され、10 進法に従って表示されます。1 MB は 1,000,000 バイト、1 GB は 1,000,000,000 バイトです。これは Apple がストレージ容量やアプリサイズを報告する際に使用する規則と同じです（[Apple デバイスでのストレージ容量の測定方法](https://support.apple.com/en-us/102119) を参照）。インストールサイズが 733,446,863 バイトの場合、733.4 MB と表示されます。

## 継続的インテグレーション {#continuous-integration}

時間の経過に伴うバンドルサイズを追跡するには、CI でバンドルを解析してください。まず、CI が <.localized_link href="/guides/integrations/continuous-integration#authentication">認証済み</.localized_link> であることを確認してください。

Tuist は、どのプロジェクトにバンドルを報告するかを知る必要があります。プロジェクトをまだ接続していない場合は、`tuist init` を実行するか、ハンドルを自分で宣言してください。

::: code-group
```swift [Tuist.swift]
let tuist = Tuist(fullHandle: "my-account/my-project")
```
```toml [tuist.toml]
project = "my-account/my-project"
```
<!-- -->
:::

Gradle プロジェクトなど、Swift マニフェストがないプロジェクトには <.localized_link href="/references/tuist-toml">`tuist.toml`</.localized_link> を使用してください。両方のファイルが存在する場合、`Tuist.swift` が優先されます。

GitHub Actions ワークフローの例:

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

設定が完了すると、バンドルサイズが時間とともにどのように変化するかを確認できます。

![バンドルサイズグラフ](/images/guides/features/bundle-size/bundle-size-graph.png)

## プルリクエスト/マージリクエストのコメント {#pullmerge-request-comments}

> [!WARNING]
> **Git プラットフォームとの連携が必要です**
>
> プルリクエスト/マージリクエストに自動的にコメントを投稿するには、<.localized_link href="/guides/server/accounts-and-projects">Tuist プロジェクト</.localized_link> を <.localized_link href="/guides/server/authentication">Git プラットフォーム</.localized_link> と連携させてください。

Tuist プロジェクトが [GitHub](https://github.com) などの Git プラットフォームと接続されると、`tuist inspect bundle` を実行するたびに Tuist がプルリクエスト/マージリクエストに直接コメントを投稿します。

![検査済みバンドルを含む GitHub アプリのコメント](/images/guides/features/bundle-size/github-app-with-bundles.png)

## サイズしきい値 {#size-thresholds}

> [!WARNING]
> **Git フォージとの連携が必要です**
>
> サイズしきい値を使用するには、[Tuist GitHub App](https://github.com/apps/tuist) をプロジェクトに接続してください。これはプロジェクトの統合ページから行えます。

サイズしきい値を使用すると、ベースラインブランチと比較してバンドルサイズが設定された割合または絶対サイズを超えて増加した場合に、プルリクエストをブロックできます。しきい値に違反すると、Tuist は PR コミットに GitHub Check Run を作成し、サイズの増加が解決されるまでマージをブロックします。

![バンドルサイズしきい値超過を示す PR ステータスチェック](/images/guides/features/bundle-size/github-pr-check-status.png)

Check Run には、ベースラインサイズ、現在のサイズ、および設定された単位での増減が表示されます。増加が意図的なものであれば、GitHub UI から **Accept** ボタンをクリックして直接承認できます。

![しきい値違反を示す GitHub チェックラン](/images/guides/features/bundle-size/github-check-run-threshold.png)

### 設定 {#size-thresholds-configuration}

しきい値を設定するには、プロジェクトの **Settings > Bundles** タブに移動してください。

![バンドルサイズしきい値の設定](/images/guides/features/bundle-size/bundle-size-thresholds.png)

**Install size** または **Download size** を選択し、次に **Threshold type** を選択してください。

- **Percentage (%)**: ベースラインサイズに対する相対的な増加を制限します。`0.47` などの小数パーセントもサポートされています。既存のパーセントしきい値は、設定された値と動作を維持します。
- **Absolute size (MB)**: ベースラインサイズとは無関係に、固定量による増加を制限します。最大 1.5 MB の増加を許可するには `1.5` を入力してください。MB は 10 進単位を使用します: 1 MB = 1,000,000 バイト。値は正の整数バイトに解決される必要があります。

![絶対バンドルサイズ増加しきい値の設定](/images/guides/features/bundle-size/absolute-size-threshold.png)

どちらのタイプも、設定された **Baseline branch** 上の最新のバンドルと比較されます。比較対象は、同じ名前、同じバンドルタイプ（例: `.app` または `.ipa`）、および少なくとも 1 つの共通プラットフォームを持つものです。したがって、シミュレーターの `.app` はシミュレーターの `.app` アップロードとのみ比較されます。オプションの **Bundle name** はルールをそのバンドルに限定します。チェックは、増加が制限を **超える** 場合にのみ失敗します。増加量が等しい場合、サイズが変わらない場合、および減少した場合は合格します。一致するベースラインがないか、選択した指標の記録されたサイズがない場合、ルールはスキップされます。絶対制限ではゼロサイズのベースラインがサポートされていますが、パーセント制限ではパーセント増加が未定義であるためスキップされ続けます。

### 承認できるユーザーの制限 {#size-thresholds-approvals}

デフォルトでは、リポジトリへの書き込みアクセス権を持つ誰でもサイズ増加を承認できます。これは、GitHub がそのボタンを表示する対象だからです。範囲を狭めるには、**Settings > Bundles** の下にある **Who can accept** を設定してください。

- **Anyone**: デフォルト。リポジトリへの書き込みアクセス権を持つ全員。
- **Selected GitHub users**: 追加した GitHub ユーザー名のみ。

リストにいないユーザーがいる場合、説明付きでチェックは失敗したままとなり、ボタンは使用可能なユーザーのために残ります。
