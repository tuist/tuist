---
{
  "title": "リリース",
  "titleTemplate": ":title | コントリビューター | Tuist",
  "description": "Tuist の継続的リリースプロセスの仕組みを学ぶ"
}
---
# リリース

Tuist は、変更が main ブランチにマージされると自動的に新しいバージョンを公開します。CLI、サーバー、Kura キャッシュサーバーはすべてリリースチャネル（canary、release candidate、stable）を通じて配布されるため、推奨されるインストールは安定しており、更新頻度は抑えられています。リリース候補版の作成と stable への昇格は、毎週 deliberate に実行されるステップです。アプリは継続的にリリースされます（iOS アプリは TestFlight への継続的なデプロイのみを行います。詳細は[こちら](#app-store-release)をご覧ください）。

## 概要

以下の主要コンポーネントをリリースしています：
- **Tuist CLI** - コマンドラインツール。canary、release candidate、stable の[チャネル](#release-channels)を通じて配布
- **Tuist Server** - バックエンドサービス。CLI と同じチャネルモデルで配布
- **Kura** - キャッシュサーバー。CLI と同じチャネルモデルで配布
- **Tuist App** - macOS および iOS アプリ。継続的にリリース（iOS アプリは TestFlight への継続的なデプロイのみ。詳細は[こちら](#app-store-release)）

`main` へのすべてのプッシュにより、CLI、サーバー、Kura の canary プレリリースが公開されます。これらの各コンポーネントの stable リリースは、メンテナーが十分な検証を経たリリース候補版を昇格させたときにのみ作成され、毎週のスケジュールで 3 つのリリーストレインが連動して実行されます（[リリースチャネル](#release-channels)を参照）。アプリは `main` へのすべてのプッシュで stable を公開します。

## 仕組み

### 1. コミット規約

コミットメッセージの構造化には [Conventional Commits](https://www.conventionalcommits.org/) を使用しています。これにより、ツールが変更の内容を理解し、バージョンの上げ方を決定し、適切な changelog を生成できます。

形式: `type(scope): description`

#### コミットタイプとその影響

| タイプ | 説明 | バージョンへの影響 | 例 |
|------|-------------|----------------|---------|
| `feat` | 新機能または新機能の追加 | マイナーバージョンアップ（x.Y.z） | `feat(cli): add support for Swift 6` |
| `fix` | バグ修正 | パッチバージョンアップ（x.y.Z） | `fix(app): resolve crash when opening projects` |
| `docs` | ドキュメントの変更 | リリースなし | `docs: update installation guide` |
| `style` | コードスタイルの変更 | リリースなし | `style: format code with swiftformat` |
| `refactor` | コードのリファクタリング | リリースなし | `refactor(server): simplify auth logic` |
| `perf` | パフォーマンスの改善 | パッチバージョンアップ | `perf(cli): optimize dependency resolution` |
| `test` | テストの追加・変更 | リリースなし | `test: add unit tests for cache` |
| `chore` | メンテナンスタスク | リリースなし | `chore: update dependencies` |
| `ci` | CI/CD の変更 | リリースなし | `ci: add workflow for releases` |

CLI では、これらのバージョンアップにより canary のバージョンと changelog のグループ化が決まります。stable な CLI バージョンのマイナーライン（`X.Y.0`）は手動で作成され、stable パッチ（`X.Y.Z`）はバックポートからのみ提供されるため、`feat` または `fix` は即座に stable リリースとしてではなく、以下のチャネルフローを通じて CLI ユーザーに届きます。

#### 破壊的変更

破壊的変更はメジャーバージョンアップ（X.0.0）を引き起こし、コミット本文に記載する必要があります：

```
feat(cli): change default cache location

BREAKING CHANGE: The cache is now stored in ~/.tuist/cache instead of .tuist-cache.
Users will need to clear their old cache directory.
```

### 2. 変更検出

各コンポーネントは [git cliff](https://git-cliff.org/) を使用して以下のことを行います：
- 最後のリリース以降のコミットを分析する
- スコープ（cli、app、server）でコミットをフィルタリングする
- リリース可能な変更があるかどうかを判断する
- changelog を自動生成する

### 3. リリースパイプライン

リリース可能な変更が検出された場合：

1. **バージョン計算**：パイプラインが次のバージョン番号を決定します
2. **Changelog 生成**：git cliff がコミットメッセージから changelog を作成します
3. **ビルドプロセス**：コンポーネントがビルドおよびテストされます
4. **アーティファクト生成**：CLI バンドル、チェックサム、`tuist --experimental-dump-help` から生成された `tuist.spec.json` CLI 仕様など、リリース固有のアセットが作成されます
5. **リリース作成**：アーティファクト付きの GitHub リリースが作成されます
6. **配布**：更新がパッケージマネージャーにプッシュされます（例：CLI の Homebrew）

アプリの場合、これはマージごとに stable リリースを生成します。CLI、サーバー、Kura の場合、この同じ自動パイプラインは **canary** プレリリースのみを生成します。リリース候補版と stable リリースは毎週のリリーストレインで作成されます（[リリースチャネル](#release-channels)を参照）。

### 4. スコープフィルタリング

各コンポーネントは、関連する変更がある場合にのみリリースされます：

- **CLI**：`(cli)` スコープを持つコミット、またはスコープなしのコミット
- **App**：`(app)` スコープを持つコミット
- **Server**：`(server)` スコープを持つコミット

## リリースチャネル

CLI、サーバー、Kura は `main` へのすべてのプッシュで stable リリースに昇格されるわけではありません。推奨されるインストール先が安定しており変化が少ない状態を保ちながら、早期採用者がコミットごとのビルドを利用できるよう、それぞれ 3 つのチャネルを通じて提供されます。ユーザー向けのドキュメントは <.localized_link href="/cli/release-channels">CLI リリースチャネル</.localized_link> および <.localized_link href="/guides/server/self-host/release-channels">Server リリースチャネル</.localized_link> にあります。このセクションはメンテナー向けの運用ガイドです。

すべてのコンポーネントが同じ 3 つのチャネルを使用します：

| チャネル | バージョン | 作成者 |
|---------|---------|--------|
| Canary | `X.Y.0-canary.N` | 自動。`main` への変更を含むすべてのプッシュ時（`<component>-release.yml`。Kura の場合は `kura/` が変更された際に `server-production-deployment.yml` によって呼び出されます） |
| Release candidate | `X.Y.0-rc.N` | 毎週月曜日、または手動。`releases/<component>-<major>.<minor>.x` ブランチ上（`<component>-rc.yml`） |
| Stable | `X.Y.Z` | 毎週月曜日、または手動。十分な検証を経た RC を昇格させることで（`<component>-promote.yml`）。パッチは `<component>-backport.yml` を介して適用されます |

Canary と RC ビルドは GitHub プレリリースとして公開されます（「Latest」とマークされることはなく、GHCR 上の `:latest` も移動せず、CLI の Homebrew にもプッシュされません）。そのため、パッケージマネージャーやイメージリゾルバーは明示的なオプトインがあった場合にのみこれらを取得します。Canary は常に次の未リリースのマイナーバージョンを対象とします。RC ラインが作成されると、`main` の canary は次のマイナーバージョンに進みます。

ホスト型 Tuist は stable トレインを待ちません。サーバーはコミットごとにデプロイされ、ホスト型 canary と本番環境は最新の Kura canary を実行します。デプロイのカスケード処理により、その canary 自体がデプロイ前に公開されるため、`kura-release.yml` には独自のトリガーがありません。Kura のリリースツール自体の変更（`mise/tasks/kura/**`、`kura-*.yml` ワークフロー）だけでは canary は作成されません。

バージョン番号を手動で選択することはありません。各チャネルの次のバージョンは、以下のワークフローによって呼び出される `mise/tasks/<component>/release/channel-version.sh` により、既存の git タグから導出されます。

リリースブランチはコンポーネントごとに名前空間化されています（`releases/server-X.Y.x`、`releases/kura-X.Y.x`、CLI の場合は `releases/X.Y.x`）。これにより、3 つのコンポーネントのラインが同じマイナーバージョンで競合することはありません。

### 毎週のスケジュール

毎週月曜日の 06:00 UTC に、3 つのコンポーネントの昇格ジョブが連動して実行されます：**CLI Promote to Stable**、**Server Promote to Stable**、**Kura Promote to Stable**。それぞれがまだ stable になっていない最新の RC ラインを昇格させます。通常、これは前週の月曜日に作成されたラインです。そのようなラインがない場合、そのジョブは何も公開しません。

昇格が完了すると、結果に関係なく、対応する **Release Candidate** ワークフロー（`cli-rc.yml`、`server-rc.yml`、`kura-rc.yml`）が `workflow_run` を介して発火し、`main` から次のラインを作成します。

スケジュールされた実行のいずれかが失敗するかキャンセルされると、Slack にメッセージが投稿されます。リリースブランチに最新の RC 以降のコミットがある場合、昇格は失敗します。そのラインを出荷するには、そこに新しい RC を作成し、手動で昇格させてください。それ以外の場合、次の月曜日に新しいラインが代わりに昇格されます。

### リリース候補版の作成

毎週のスケジュール外で新しいラインを作成するには（以下のコンポーネントのワークフロー名に置き換えてください）：

1. `branch` 入力を空にして、**\<Component\> Release Candidate** ワークフロー（例：`server-rc.yml`）を実行します。
2. これにより `X.Y.0-rc.1` が公開され、成功するとビルドされたコミットで保護された `releases/<component>-X.Y.x` ブランチが作成されます。

重要な修正や回帰を soaking ラインに取り込むには、PR を介してリリースブランチに cherry-pick し（バックポートと同じフローです。CI は決して cherry-pick しません）、その後 RC を反復処理します：

1. `releases/<component>-X.Y.x` からブランチを切り、修正を cherry-pick し、リリースブランチへ戻る PR を開き、競合を解決してマージします。
2. `branch=releases/<component>-X.Y.x` を指定して **Release Candidate** ワークフローを再度実行します。これにより、ブランチの HEAD から `X.Y.0-rc.(N+1)` が公開されます。

soaking ラインは機能フリーズされています。重要な修正と回帰のみが適用されます。

### stable への昇格

毎週のスケジュール外でラインを昇格させるには、その RC が正常に soaking された後に行います：

1. `branch=releases/<component>-X.Y.x` を指定して **\<Component\> Promote to Stable** ワークフロー（例：`server-promote.yml`）を実行します。
2. これにより `make_latest=true` を使用して semver タグ付きイメージが公開され、GHCR の `:latest` タグと GitHub の「Latest」ポインタが移動します。CLI はさらに Homebrew formula を更新します。

ブランチの HEAD が最新の RC が指すコミットと正確に一致しない限り、昇格は実行されません。したがって、最後の RC 以降にラインに修正がマージされた場合は、新しい RC を作成し、stable として出荷される前にそれを soaking させる必要があります。

### stable ラインへの修正のバックポート

ラインが stable になったら、CLI 専用の **Backport Release** ワークフロー（`cli-backport.yml`）を使用してパッチを出荷します。PR を介して `releases/X.Y.x` に修正を cherry-pick し、そのブランチでワークフローを実行して `X.Y.(Z+1)` を作成します。バックポートは「Latest」ポインタや Homebrew formula を移動させません。同時に 2 つのラインが維持されます。現在のラインは回帰とセキュリティ修正を受け入れ、前のラインは重要な修正とセキュリティ修正のみを受け入れます。その他のバグ修正はバックポートされず、次のマイナーバージョンで出荷されます。

サーバーと Kura の場合は、**Server Backport Release**（`server-backport.yml`）または **Kura Backport Release**（`kura-backport.yml`）を使用します。昇格は RC の `X.Y.0` だけを公開します。すでに stable なラインにパッチを適用することはできません。

1. 選択した `X.Y` ラインの最新公開 stable コンポーネントタグから開始し、既存の `releases/server-X.Y.x` または `releases/kura-X.Y.x` ブランチに対して局所的な修正 PR を開きます。新しいマイナーまたはメジャーリリースがあっても、維持されているラインへのパッチ適用は妨げられません。無関係な main の変更は含めないでください。
2. ソース PR をレビューしてマージします。リモートのリリースブランチを取得し、コンポーネントのサポート対象プラットフォームと TLS の正負の制御を含めて、その **最終マージ tip** を資格認定します。マージ前のヘッドが合格しても、異なる squash またはマージコミットの資格認定にはなりません。
3. 個別の公開承認を得て、一致するバックポートワークフローを **from main** でディスパッチし、`source_sha` をその正確な資格認定済みマージ tip に、`base_tag` を現在の stable タグ（例：`server@X.Y.Z` または `kura@X.Y.Z`）に設定します。ワークフローは `X.Y.(Z+1)` を導出します。オペレーターはマイナーバージョンアップや canary コンテンツの昇格を選択しません。

計画段階では、正確なリモートブランチとベースタグを更新し、選択されたソースがブランチの tip と一致することを要求し、変更されていないソースやコンポーネント外の変更、その信頼ポリシー入力と検証を拒否し、解決されたベースコミットを固定します。main ソースの制御は、バージョン付きイメージと GitHub 公開の直前にこれらのチェックを繰り返します。ソースブランチ、stable ベース、または利用可能なバージョンが変更された場合は、新しいソースに置き換えるのではなく、停止して再資格認定してください。

バックポートは、GitHub の「Latest」ポインタや GHCR `:latest` を移動させることなく、既存のマルチプラットフォームパブリッシャーを使用します。公開はホスト型デプロイとは別個です。これらのワークフローは、ホスト型サーバーや Kura フリートを昇格させたり、canary 受け入れをバイパスしたり、インストールされたランタイムを資格認定したりしません。ビルドヘルパーと Dockerfile は引き続き選択された stable ソースから提供されます。制御は公開ゲートであり、認証情報不要のビルドジョブではありません。ビルドは最終ゲートの前にタグ付けされていないイメージダイジェストをアップロードできます。イメージと GitHub の公開はアトミックではありません。イメージタグが公開された後に後のゲートが失敗した場合は、部分的なリリースを検査し、元のソースと成果物を保持してください。既存のリリースを置き換えたり、そのタグの下で異なるバイトを使用したりしないでください。

## 適切なコミットメッセージの書き方

コミットメッセージはリリースノートに直接影響するため、明確で説明的なメッセージを書くことが重要です：

### 推奨事項：
- 現在形を使用する：「added feature」ではなく「add feature」
- 簡潔かつ説明的にする
- 変更がコンポーネント固有の場合はスコープを含める
- 該当する場合は課題を参照する：`fix(cli): resolve build cache issue (#1234)`

### 避けるべきこと：
- 「fix bug」や「update code」のような曖昧なメッセージを使用しない
- 複数の無関係な変更を 1 つのコミットに混ぜない
- 破壊的変更の情報を含めることを忘れない

### 破壊的変更

破壊的変更の場合、コミット本文に `BREAKING CHANGE:` を含めます：

```
feat(cli): change cache directory structure

BREAKING CHANGE: Cache files are now stored in a new directory structure.
Users need to clear their cache after updating.
```

## リリースワークフロー

CLI、サーバー、Kura はそれぞれ独自のチャネルワークフローセットを持ち、同じ形式に従います：

- `<component>-release.yml` - `main` へのコンポーネント関連のすべてのプッシュで canary を公開します（Kura のものは、`kura/` が変更されたときに `server-production-deployment.yml` が呼び出す再利用可能なワークフローです）
- `<component>-rc.yml` - 毎週月曜日にリリース候補版を作成します（昇格後の `workflow_run` を介して）、または手動で作成または反復します
- `<component>-promote.yml` - 毎週月曜日の 06:00 UTC に待機中の RC を stable に昇格させます、または soaking された RC を手動で昇格させます
- `<component>-build-publish.yml` - 上記 3 つが呼び出す共有ビルドおよび公開パイプライン

CLI、サーバー、Kura にはさらに、stable ライン上のパッチを作成するための `<component>-backport.yml` があります。コンポーネントのすべてのワークフローは 1 つの `<component>-publish` 並列グループを通じて直列化されるため、バージョン解決とタグ付けが競合することはありません。Kura は例外です。その canary は `kura-canary-publish` を使用し、RC、昇格、バックポートは `kura-stable-publish` を使用するため、長い stable ビルドがデプロイのカスケードをブロックすることはありません。タグの名前空間は互いに素であるため、2 つのグループが競合することはありません。

Helm チャートとインフラストラクチャイメージ（CAPI operator、runners controller、xcresult processor image、linux runner image など）は、引き続き `.github/workflows/server-production-deployment.yml` を介してリリースされます。これは `main` へのプッシュで実行され、ホストされたデプロイ向けに canary → 受け入れテスト → production とカスケードし、それらのインフラコンポーネントに変更が生じるたびに公開します。アプリ、キャッシュ、Gradle プラグイン、skills、Noora、およびスタンドアロンのインフラコントローラーはそれぞれ専用の `*-release.yml` ワークフローを持っています。これらはすべて変更検出を共有しています：`mise/tasks/release/components.json` が各コンポーネントのタグプレフィックスと include パスを宣言し、git cliff が一致するコミットをリリースノートに変換します。

CLI ビルド（`cli-build-publish.yml`）は、下流のツールがコマンドインターフェースを利用できるように、`tuist.spec.json` アーティファクト（`tuist --experimental-dump-help` から生成）も作成して公開します。

## リリースの監視

リリースは以下の方法で監視できます：
- [GitHub Releases ページ](https://github.com/tuist/tuist/releases)
- ワークフロー実行用の GitHub Actions タブ
- 各コンポーネントディレクトリの Changelog ファイル

## メリット

この継続的リリースアプローチにより、以下が可能になります：

- **迅速な提供**：変更はマージ直後にユーザーに届きます
- **ボトルネックの削減**：手動リリースを待つ必要がありません
- **明確なコミュニケーション**：コミットメッセージから自動生成される changelog
- **一貫したプロセス**：すべてのコンポーネントで同じリリースフロー
- **品質保証**：テスト済みの変更のみがリリースされます

## トラブルシューティング

リリースが失敗した場合：

1. 失敗したワークフローの GitHub Actions ログを確認する
2. コミットメッセージが従来の形式に従っていることを確認する
3. すべてのテストがパスしていることを確認する
4. コンポーネントが正常にビルドされていることを確認する

即時リリースが必要な緊急の修正の場合：
1. コミットに明確なスコープが含まれていることを確認する
2. マージ後、リリースワークフローを監視する
3. サーバーまたはアプリの場合、修正は次のプッシュで提供されます。必要に応じて、手動リリースをトリガーしてください
4. CLI の場合、修正は自動的に canary に反映されます。stable ユーザーに提供するには、メンテナンスされている stable ラインにバックポートしてください（[stable ラインへの修正のバックポート](#backporting-fixes-to-a-stable-line)を参照）

## App Store リリース

CLI とサーバーは上記の継続的リリースプロセスに従いますが、Apple の App Store レビュープロセスのため、**iOS アプリ** は例外です：

- **手動リリース**：iOS アプリのリリースには App Store への手動提出が必要です
- **レビューの遅延**：各リリースは Apple のレビュープロセスを経る必要があり、1〜7 日かかることがあります
- **変更のバッチ処理**：複数の変更は通常、各 iOS リリースでまとめてバンドルされます
- **TestFlight**：ベータ版は App Store リリース前に TestFlight を介して配布される場合があります
- **リリースノート**：App Store のガイドラインに合わせて具体的に記述する必要があります

iOS アプリは同じコミット規約に従い、changelog 生成に git cliff を使用しますが、ユーザーへの実際のリリースは頻度が低く、手動スケジュールで行われます。
