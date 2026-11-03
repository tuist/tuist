---
{
  "title": "Xcode ビルドインサイト",
  "titleTemplate": ":title · ビルドインサイト · 機能 · ガイド · Tuist",
  "description": "Tuist ダッシュボードで Xcode のビルド分析を追跡し、ローカルおよび CI ビルドのパフォーマンスを監視します。"
}
---
# Xcode ビルドインサイト {#xcode-build-insights}

大規模プロジェクトでの作業において、同じコードを何度も再ビルドする必要はありません。Tuist Build Insights を使えば、ローカルや CI のビルド時間がボトルネックになる前に傾向を把握できるよう、ビルド分析を追跡できます。

ビルドインサイトは `tuist inspect build` コマンドによって提供され、通常はスキームのポストアクションに追加します。

ローカルのビルド時間の追跡を開始するには、スキームのポストアクションに `tuist inspect build` コマンドを追加して活用します。

![ビルドを検査するためのポストアクション](/images/guides/features/build-insights/inspect-build-scheme-post-action.png)

> [!NOTE]
> ビルド設定を取得するため、「Provide build settings from」フィールドを実行可能ファイルまたはメインのビルドターゲットに設定してください。


> [!NOTE]
> ビルドが失敗した場合、ポストスキームアクションは実行されません。

>
> その場合は、関連する `project.pbxproj` の `BuildAction` で `runPostActionsOnFailure` を `YES` に設定することで実行できます。
>
> ```diff
> <BuildAction
>    buildImplicitDependencies="YES"
>    parallelizeBuildables="YES"
> +  runPostActionsOnFailure="YES">
> ```

[Mise](https://mise.jdx.dev/) の場合、ポストアクション環境で `tuist` を有効化します。

```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect build
```

> [!TIP]
> **Mise のパス解決**
>
> 環境の `PATH` はスキームのポストアクションには継承されないため、Mise の絶対パスを使用してください。これは Mise のインストール方法によって異なります。ビルド設定はターゲットから継承されるべきであり、`mise` が `$SRCROOT` から実行できるようにします。

[Homebrew](https://brew.sh/) の場合、ポストアクション環境に Homebrew のパスを追加します。

```sh
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
tuist inspect build
```

アクタークレームはデフォルトで無効です。スキームのポストアクション用に設定するには、シェルのエクスポートに頼らず、そのスクリプト内で `TUIST_ACTOR_ID` を設定してください。Dock から起動した Xcode は `~/.zshrc` からの変数を継承しません。Homebrew で設定済みのクレームを明示的に抑制するには、次を使用します。

```sh
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
export TUIST_ACTOR_ID=""
tuist inspect build
```

Mise では、Mise が環境を読み込んだ後に値を上書きします。

```sh
$HOME/.local/bin/mise x -C "$SRCROOT" -- env TUIST_ACTOR_ID="" tuist inspect build
```

オプトインするには、空の値ではなく明示的なラベルを使用してください。

ログインすると、ローカルビルドが追跡され、Tuist ダッシュボードから利用可能になります。

> [!TIP]
> ダッシュボードにすばやくアクセスするには、CLI から `tuist project show --web` を実行します。


![ビルドインサイト付きダッシュボード](/images/guides/features/build-insights/builds-dashboard.png)

## CI におけるビルドインサイト {#continuous-integration}

CI でビルドインサイトを追跡するには、CI が <.localized_link href="/guides/integrations/continuous-integration#authentication">認証済み</.localized_link>であることを確認してください。

Xcodebuild 主導の CI の場合、次のことが必要です。
- `xcodebuild` アクションを呼び出す際は、<.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</.localized_link> を使用します。
- `xcodebuild` コマンドに `-resultBundlePath` を追加します。

`-resultBundlePath` がないと、必要なアクティビティログと結果バンドルが生成されず、`tuist inspect build` でビルドを分析できません。

## プライベートネットワークでの認証不要なレポート公開 {#network-trusted-publishing}

セルフホストされたデプロイメントでは、開発者がサインインせずに完了したレポートを公開できるようにすることができます。オペレーターはインスタンスで `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS=true` を構成し、<.localized_link href="/guides/server/self-host/server#network-trusted-access">セルフホスティングガイド</.localized_link>に記載されている通りに再起動する必要があります。これはサポートされているすべてのプロジェクトに適用され、ダッシュボードの設定はありません。スキームのポストアクションまたはターミナルで使用される環境で、セルフホストされた URL とプロジェクトを設定してください。認証情報がない場合、CLI は自動的にインスタンスのポリシーを検出します。

```sh
export TUIST_URL="https://tuist.internal.example"
tuist inspect build
# To publish local test results:
tuist inspect test
```

認証情報が genuinely absent（真に存在しない）場合、アクティビティログと XCResult バンドルはローカルで解析され、構造化されたレポートとして送信されます。生のアーカイブ、添付ファイル、カバレッジ/履歴のアップロード、リモートプロセッサ、シャード参照、または選択的実行の証拠は送信されません。レポートは表示されたままですが、認証されたテストケースの状態を更新したり、検疫/失敗の自動化を駆動したりすることはできません。ダッシュボードやその他の特権コマンドには引き続きサインインが必要です。インスタンスが別途ネットワーク信頼キャッシュアクセスを有効にしていない限り、または認証情報がプロビジョニングされていない限り、キャッシュ統合は無効のままにしてください。

既存の認証情報は認証されたままです。無効、破損、空白、またはリフレッシュ拒否された認証情報はフェイルクローズされ、ディスク上に残るため、後続のコマンドがサイレントに未署名状態になることはありません。意図的な復旧措置として、再度サインインするか、明示的にサインアウトしてください。認証不要クライアントをアップグレードする前に、すべてのサーバーレプリカをディスカバリー対応バージョンにアップグレードし、リダイレクトなしで最終的なサーバー URL を構成してください。ディスカバリー機能のない古いサーバー、無効化されたインスタンス、およびディスカバリー失敗時は依然として認証が必要です。クライアント側のオプトインは不要です。設定されたアクタークレームを省略するには `TUIST_ACTOR_ID=""` を独立して設定してください。検証済みの認証情報 ID は影響を受けません。

## マシンメトリクス {#machine-metrics}

ビルドインサイトには、ビルド中にキャプチャされたマシンレベルのパフォーマンスメトリクス（CPU、メモリ、ネットワーク、およびディスク使用量）を含めることができます。これを有効にするには、システムメトリクスを継続的にサンプリングする軽量なバックグラウンドデーモンを設定します。

```bash
tuist setup insights
```

これにより、バックグラウンドでメトリクスをサンプリングするローカルデーモンが実行されます。データは `tuist inspect build` によって自動的に取得され、ビルドレポートと一緒にアップロードされます。

> [!TIP]
> **Ci**
>
> CI マシンでもマシンメトリクスをキャプチャするため、ビルド前に `tuist setup insights` を実行します。

マシンメトリクスの収集を停止するには、次を実行します。

```bash
tuist teardown insights
```

これにより、デーモンの LaunchAgent がアンロードされ、plist が削除され、`~/.local/state` からサンプリングされたメトリクスとデーモンログが削除されるため、バックグラウンドで実行されているものは何も残りません。


## レポートアクタークレーム {#report-actor-claim}

レポート作成リクエストには、`TUIST_ACTOR_ID` を組織スコープのラベルに明示的に設定した場合のみ、オプションの `x-tuist-actor-id` ヘッダーが含まれます（例：`TUIST_ACTOR_ID=employee-123 tuist inspect build`）。デフォルトではラベルは送信されず、Tuist はオペレーティングシステムのユーザー名を検出しません。空の `TUIST_ACTOR_ID` は報告された識別子を省略しますが、認証情報ベースの検証済み ID は削除されません。識別子はスペース以外の印刷可能 ASCII で 1〜128 バイトである必要があります。無効なオーバーライドはフォールバックせずに省略されます。カスタムプロキシが見慣れないヘッダーを拒否する場合は、空の環境オーバーライドでオプトアウトしてください。

検証済みの個別認証情報が優先されます。それ以外の場合、クライアント報告の識別子は **未検証** として表示され、権限を付与したりユーザーに自動リンクしたりすることはありません。識別子はプロジェクトのレポートを表示できる anyone に表示され、プロジェクトが公開されている場合は公開ビューアにも表示され、データエクスポートにも含まれるため、機密情報を含めないでください。これはビルド、テスト、およびコマンドイベントレポートに適用されます。古いサーバーはオプションのヘッダーを無視し、新しいサーバーはそれなしの古いクライアントを受け入れます。識別子のない新しい共有トークンレポートは、公開組織ではなく **不明** と表示されます。過去のレポートは以前の帰属を保持します。ビルドおよびテスト一覧は、検証済みユーザーと未検証の報告された識別子を区別します。セルフホストされたインスタンスが認証不要なレポート公開を明示的に有効にし、クライアントがそのポリシーを検出しない限り、認証は引き続き必要です。

## カスタムメタデータ {#custom-metadata}

環境変数を使用してビルドにメタデータを添付し、フィルタリングを改善できます。

### 環境変数

| 変数 | 形式 | 説明 |
|----------|--------|-------------|
| `TUIST_BUILD_TAGS` | カンマ区切り | 1つの変数に複数のタグ。 |
| `TUIST_BUILD_VALUE_*` | 単一値 | サフィックスがキーとなるキーと値のペア。 |

### 例

ビルドを実行する前に、CIまたはシェルでこれらの値を設定してください：

```sh
export TUIST_BUILD_TAGS="nightly,ios-team,release-candidate"
```

```sh
export TUIST_BUILD_VALUE_TICKET="PROJ-1234"
export TUIST_BUILD_VALUE_PR_URL="https://github.com/myorg/myrepo/pull/123"
```
