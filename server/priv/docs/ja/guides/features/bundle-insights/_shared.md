## タグ {#tags}

バンドルをアップロードする際にタグを付与して、ビルドのフレーバー、環境、リリースチャネルを区別します。バンドルタグは Build Insights タグと同じ規則に従います。

```bash
tuist inspect bundle App.ipa --tags paid production
```

CI では、`TUIST_BUNDLE_TAGS` を使用してカンマ区切りのタグを設定することもできます。

```bash
TUIST_BUNDLE_TAGS="paid,production" tuist inspect bundle App.ipa
```

明示的な `--tags` は環境変数のタグを上書きします。タグには英字、数字、ハイフン、アンダースコアを使用でき、バンドルごとに最大 10 個、タグごとに最大 50 文字まで指定できます。同じオプションは Android バンドルでも利用可能です。`--json` はローカルのみで動作し、タグやバンドルのアップロードは行いません。

タグはバンドル名の横およびバンドルの詳細に表示されます。ダッシュボードの **タグ** フィルターを使用して、タグを入力することでバンドルリストに含めるか除外するかを選択できます。フィルター演算子のラベルが **含む** および **含まない** であっても、マッチングは完全一致で大文字小文字を区別します。`paid` は `paid-extra` に一致しません。CLI からフィルターするには:

```bash
tuist bundle list --tags paid production
```

CLI、API (`?tags=paid,production`)、および MCP `list_bundles` ツール (`tags: ["paid", "production"]`) は、指定されたタグを **すべて** 含むバンドルを返します。API アップロードは `bundle.custom_metadata.tags` を受け付け、リストおよび詳細レスポンスは `custom_metadata.tags` を返します。タグのない既存のバンドルはこれまで通り利用可能です。タグはバンドルリストをフィルターしますが、サイズチャートや自動比較および閾値のベースラインには影響しません。

既存のクライアントは、タグなしでバンドルのアップロードと読み取りを継続できます。更新されたクライアントは、`custom_metadata` を省略する古いサーバーからのレスポンスも読み取れます。タグの保存とフィルターには、バンドルタグをサポートするサーバーバージョンが必要です。古いサーバーはアップロードメタデータを無視し、タグフィルターを拒否します。タグが指定されていない場合、更新されたクライアントはアップロードメタデータとタグクエリパラメータの両方を省略します。

## バンドルサイズの理解 {#understanding-sizes}

Tuist は、分析されたすべてのバンドルについて 2 つの値を報告します。

- **インストールサイズ**: デバイスにインストールされたアプリが占有する領域。
- **ダウンロードサイズ**: ユーザーがダウンロードする圧縮後のサイズ。Apple バンドルの場合、これは `.ipa` (アーカイブのサイズ) のみ報告され、`.xcarchive` または `.app` の入力では利用できません。

サイズはバイト単位で保存され、1 MB を 1,000,000 バイト、1 GB を 1,000,000,000 バイトとする十進法規則を使用して表示されます。これは Apple がストレージ容量とアプリサイズを報告するために使用する規則と同じです ([Apple デバイスでのストレージ容量の測定方法](https://support.apple.com/en-us/102119) を参照)。733,446,863 バイトのインストールサイズは 733.4 MB と表示されます。

## 継続的インテグレーション {#continuous-integration}

時間の経過に伴うバンドルサイズを追跡するには、CI でバンドルを分析します。まず、CI が <.localized_link href="/guides/server/authentication#continuous-integration">認証済み</.localized_link> であることを確認してください。

Tuist は、バンドルをどのプロジェクトに報告するかを知る必要があります。プロジェクトをまだ接続していない場合は、`tuist init` を実行するか、ハンドルを自分で宣言してください。

::: code-group
```swift [Tuist.swift]
let tuist = Tuist(fullHandle: "my-account/my-project")
```
```toml [tuist.toml]
project = "my-account/my-project"
```
<!-- -->
:::

Swift マニフェストのないプロジェクト (Gradle プロジェクトなど) には <.localized_link href="/references/tuist-toml">`tuist.toml`</.localized_link> を使用してください。両方のファイルが存在する場合、`Tuist.swift` が優先されます。

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
> **Git フォージの統合が必要**
>
> プルリクエスト/マージリクエストに自動的にコメントを投稿するには、<.localized_link href="/guides/server/accounts-and-projects">Tuist プロジェクト</.localized_link> を Git フォージ (<.localized_link href="/guides/integrations/gitforge/github">GitHub</.localized_link>、<.localized_link href="/guides/integrations/gitforge/origin">Cursor Origin</.localized_link>、または <.localized_link href="/guides/integrations/gitforge/entire">Entire</.localized_link>) と統合してください。

Tuist プロジェクトが [GitHub](https://github.com) などの Git プラットフォームと接続されると、`tuist inspect bundle` を実行するたびに Tuist がプルリクエスト/マージリクエストに直接コメントを投稿します。

![検査済みバンドルを含む GitHub アプリのコメント](/images/guides/features/bundle-size/github-app-with-bundles.png)

## サイズ閾値 {#size-thresholds}

> [!WARNING]
> **Git フォージの統合が必要**
>
> サイズ閾値を使用するには、[Tuist GitHub App](https://github.com/apps/tuist) をプロジェクトに接続してください。これはプロジェクトの統合ページから実行できます。

サイズ閾値を使用すると、バンドルサイズがベースラインブランチと比較して設定されたパーセンテージまたは絶対サイズを超えて増加した場合に、プルリクエストをブロックできます。閾値に違反すると、Tuist は PR コミットに GitHub Check Run を作成し、サイズの増加が解決されるまでマージをブロックします。

![バンドルサイズ閾値超過を示す PR ステータスチェック](/images/guides/features/bundle-size/github-pr-check-status.png)

チェックランは、ベースラインサイズ、現在のサイズ、および設定された単位での増減を表示します。増加が意図的なものである場合、GitHub UI の **承認** ボタンをクリックして直接承認できます。

![閾値違反を示す GitHub チェックラン](/images/guides/features/bundle-size/github-check-run-threshold.png)

### 設定 {#size-thresholds-configuration}

閾値を設定するには、プロジェクトの **設定 > バンドル** タブに移動してください。

![バンドルサイズ閾値の設定](/images/guides/features/bundle-size/bundle-size-thresholds.png)

**インストールサイズ** または **ダウンロードサイズ** を選択し、次に **閾値タイプ** を選択します。

- **パーセンテージ (%)**: ベースラインサイズに対する相対的な増加を制限します。`0.47` などの小数点付きのパーセンテージもサポートされています。既存のパーセンテージ閾値は、設定された値と動作を維持します。
- **絶対サイズ (MB)**: ベースラインサイズとは無関係に、固定量による増加を制限します。`1.5` を入力すると、最大 1.5 MB の増加を許可します。MB は十進単位を使用します: 1 MB = 1,000,000 バイト。値は正の整数バイトに解決される必要があります。

![絶対バンドルサイズ増加閾値の設定](/images/guides/features/bundle-size/absolute-size-threshold.png)

どちらのタイプも、設定された **ベースラインブランチ** 上の最新のバンドルと比較されます。比較対象は、同じ名前、同じバンドルタイプ（例: `.app` または `.ipa`）、および少なくとも 1 つの共通プラットフォームを持つものに限られるため、シミュレータ用 `.app` はシミュレータ用 `.app` のアップロードとのみ比較されます。オプションの **バンドル名** を指定すると、ルールがそのバンドルに限定されます。チェックが失敗するのは、増加量が制限を **超えた** 場合のみです。増加量が制限と同等の場合、サイズが変わらない場合、または減少した場合はパスします。一致するベースラインがない場合、または選択したメトリックの記録されたサイズがない場合は、ルールがスキップされます。絶対制限ではサイズゼロのベースラインがサポートされていますが、パーセンテージ増加が未定義であるため、パーセンテージ制限では引き続きスキップされます。

### 承認できるユーザーの制限 {#size-thresholds-approvals}

デフォルトでは、リポジトリへの書き込みアクセス権を持つすべてのユーザーがサイズの増加を承認できます。これは、GitHub がそのボタンを表示する対象だからです。範囲を狭めるには、**設定 > バンドル** の下にある **承認可能なユーザー** を設定してください。

- **全員**: デフォルト。リポジトリへの書き込みアクセス権を持つすべてのユーザー。
- **選択した GitHub ユーザー**: 追加した GitHub ユーザー名のみ。

リストにないユーザーは、説明付きでチェックを失敗させたままにし、ボタンは使用可能なユーザーのために残ります。
