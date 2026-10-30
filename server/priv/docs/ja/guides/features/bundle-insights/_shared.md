## タグ {#tags}

バンドルをアップロードする際にタグを付与することで、ビルドのフレーバー、環境、またはリリースチャネルを区別できます。バンドルタグは Build Insights タグと同じ規則に従います：

```bash
tuist inspect bundle App.ipa --tags paid production
```

CI では、`TUIST_BUNDLE_TAGS` を使用してカンマ区切りのタグを設定することもできます：

```bash
TUIST_BUNDLE_TAGS="paid,production" tuist inspect bundle App.ipa
```

明示的な `--tags` は環境変数のタグを上書きします。タグには文字、数字、ハイフン、アンダースコアを使用でき、1つのバンドルにつき最大10個、1つのタグあたり最大50文字まで指定可能です。同じオプションは Android バンドルでも機能します。`--json` はローカルのみで実行され、タグやバンドルはアップロードされません。

タグはバンドル名の横およびバンドルの詳細に表示されます。ダッシュボードの **タグ** フィルターを使用して、タグを入力し、バンドルリストに含めるか除外するかを指定します。フィルター演算子のラベルが **含む** および **含まない** であっても、マッチングは完全一致で大文字小文字を区別します：`paid` は `paid-extra` に一致しません。CLI からフィルターするには：

```bash
tuist bundle list --tags paid production
```

CLI、API（`?tags=paid,production`）、および MCP `list_bundles` ツール（`tags: ["paid", "production"]`）は、指定されたタグを **すべて** 含むバンドルを返します。API アップロードは `bundle.custom_metadata.tags` を受け付け、リストおよび詳細レスポンスは `custom_metadata.tags` を返します。タグのない既存のバンドルは以前と同様に利用可能です。タグはバンドルリストをフィルターしますが、サイズチャートや自動比較および閾値のベースラインには影響しません。

既存のクライアントは、タグなしでバンドルのアップロードと読み取りを継続できます。更新されたクライアントは、`custom_metadata` を省略する古いサーバーからのレスポンスも読み取ることができます。タグの保存とフィルタリングには、バンドルタグをサポートするサーバーバージョンが必要です：古いサーバーはアップロードメタデータを無視し、タグフィルターを拒否します。タグが指定されていない場合、更新されたクライアントはアップロードメタデータとタグクエリパラメータの両方を省略します。

## バンドルサイズの理解 {#understanding-sizes}

Tuist は、分析されたすべてのバンドルについて2つの値を報告します：

- **インストールサイズ**：デバイスにインストールされたアプリが占有する領域。
- **ダウンロードサイズ**：ユーザーがダウンロードする圧縮後のサイズ。Apple バンドルの場合、これは `.ipa`（アーカイブのサイズ）に対してのみ報告され、`.xcarchive` または `.app` の入力では利用できません。

サイズはバイト単位で保存され、1 MB が 1,000,000 バイト、1 GB が 1,000,000,000 バイトとなる十進法規約で表示されます。これは Apple がストレージ容量とアプリサイズを報告するために使用するのと同じ規約です（[Apple デバイスでのストレージ容量の測定方法](https://support.apple.com/en-us/102119) を参照）。733,446,863 バイトのインストールサイズは 733.4 MB と表示されます。

## 継続的インテグレーション {#continuous-integration}

時間の経過に伴うバンドルサイズを追跡するには、CI でバンドルを分析します。まず、CI が <.localized_link href="/guides/integrations/continuous-integration#authentication">認証済み</.localized_link> であることを確認してください。

Tuist は、どのプロジェクトにバンドルを報告するかを知る必要があります。プロジェクトをまだ接続していない場合は、`tuist init` を実行するか、ハンドルを自分で宣言してください：

::: code-group
```swift [Tuist.swift]
let tuist = Tuist(fullHandle: "my-account/my-project")
```
```toml [tuist.toml]
project = "my-account/my-project"
```
<!-- -->
:::

Swift マニフェストのないプロジェクト（Gradle プロジェクトなど）には、<.localized_link href="/references/tuist-toml">`tuist.toml`</.localized_link> を使用します。両方のファイルが存在する場合、`Tuist.swift` が優先されます。

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

設定が完了すると、バンドルサイズが時間とともにどのように変化するかを確認できます：

![バンドルサイズグラフ](/images/guides/features/bundle-size/bundle-size-graph.png)

## プル/マージリクエストのコメント {#pullmerge-request-comments}

> [!WARNING]
> **Git プラットフォームとの統合が必要**
>
> プル/マージリクエストのコメントを自動的に取得するには、<.localized_link href="/guides/server/accounts-and-projects">Tuist プロジェクト</.localized_link> を <.localized_link href="/guides/server/authentication">Git プラットフォーム</.localized_link> と統合してください。

Tuist プロジェクトが [GitHub](https://github.com) などの Git プラットフォームと接続されると、`tuist inspect bundle` を実行するたびに、Tuist はプル/マージリクエストに直接コメントを投稿します：

![検査済みバンドルを含む GitHub アプリのコメント](/images/guides/features/bundle-size/github-app-with-bundles.png)

## サイズ閾値 {#size-thresholds}

> [!WARNING]
> **Git フォージとの統合が必要**
>
> サイズ閾値を使用するには、[Tuist GitHub App](https://github.com/apps/tuist) をプロジェクトに接続してください。これはプロジェクトの統合ページから行うことができます。

サイズ閾値を使用すると、ベースラインブランチと比較してバンドルサイズが設定されたパーセンテージまたは絶対サイズを超えて増加した場合に、プルリクエストをブロックできます。閾値が違反されると、Tuist は PR コミットに GitHub Check Run を作成し、サイズの増加が解決されるまでマージをブロックします：

![バンドルサイズ閾値超過を示す PR ステータスチェック](/images/guides/features/bundle-size/github-pr-check-status.png)

チェックランは、ベースラインサイズ、現在のサイズ、および設定された単位での増減を表示します。増加が意図的なものである場合、**承認** ボタンをクリックして GitHub UI から直接承認できます：

![閾値違反を示す GitHub チェックラン](/images/guides/features/bundle-size/github-check-run-threshold.png)

### 設定 {#size-thresholds-configuration}

閾値を設定するには、プロジェクトの **設定 > バンドル** タブに移動します：

![バンドルサイズ閾値の設定](/images/guides/features/bundle-size/bundle-size-thresholds.png)

**インストールサイズ** または **ダウンロードサイズ** を選択し、次に **閾値タイプ** を選択します：

- **パーセンテージ (%)**：ベースラインサイズに対する相対的な増加を制限します。`0.47` などの小数点付きパーセンテージもサポートされています。既存のパーセンテージ閾値は、設定された値と動作を維持します。
- **絶対サイズ (MB)**：ベースラインサイズとは無関係に、固定量で増加を制限します。`1.5` と入力すると、最大 1.5 MB の増加を許可します。MB は十進単位を使用します：1 MB = 1,000,000 バイト。値は正の整数バイトに解決される必要があります。

![絶対バンドルサイズ増加閾値の設定](/images/guides/features/bundle-size/absolute-size-threshold.png)

どちらのタイプも、設定された**ベースラインブランチ**上の最新バンドルと比較されます。比較対象は同じ名前、同じバンドルタイプ（例：`.app`または`.ipa`）、そして少なくとも1つの共通プラットフォームを持つものであり、シミュレータ用`.app`はシミュレータ用`.app`アップロードとのみ比較されます。オプションの**バンドル名**を指定すると、ルールはそのバンドルに限定されます。増加が制限を**超える**場合にのみチェックは失敗します。増加量が等しい場合、サイズが変わらない場合、および減少した場合は通過します。一致するベースラインがない場合、または選択した指標の記録されたサイズがない場合、ルールはスキップされます。絶対制限ではゼロサイズのベースラインがサポートされていますが、パーセンテージ増加が未定義であるため、パーセンテージ制限では引き続きスキップされます。

### 承認できるユーザーの制限 {#size-thresholds-approvals}

デフォルトでは、リポジトリへの書き込みアクセス権を持つ誰でもサイズの増加を承認できます。これは、GitHub がそのボタンを表示する対象だからです。範囲を狭めるには、**設定 > バンドル** の下にある **承認できるユーザー** を設定します：

- **全員**：デフォルト。リポジトリへの書き込みアクセス権を持つ全員。
- **選択した GitHub ユーザー**：追加した GitHub ユーザー名のみ。

リストにいない人が承認しようとすると、説明付きでチェックは失敗したままとなり、ボタンは使用権限を持つ人のために表示され続けます。
