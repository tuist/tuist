---
{
  "title": "リリース",
  "titleTemplate": ":title | コントリビューター | Tuist",
  "description": "Tuist の継続的リリースプロセスの仕組みを学ぶ"
}
---
# リリース

Tuist は、変更が main ブランチにマージされると自動的に新しいバージョンを公開します。CLI、サーバー、Kura キャッシュサーバーはすべてリリースチャネル（canary、release candidate、stable）を通じて配布されるため、推奨されるインストールは安定しており、頻繁な更新が行われません。リリース候補版の作成と stable への昇格は、意図的かつ毎週行われる手順です。アプリは継続的にリリースされます（iOS アプリは TestFlight への継続的なデプロイのみを行います。詳細は[こちら](#app-store-release)をご覧ください）。

## 概要

以下の主要コンポーネントをリリースしています：
- **Tuist CLI** - コマンドラインツール。canary、release candidate、stable の[チャネル](#release-channels)を通じて配布されます
- **Tuist Server** - バックエンドサービス。CLI と同じチャネルモデルで配布されます
- **Kura** - キャッシュサーバー。CLI と同じチャネルモデルで配布されます
- **Tuist App** - macOS および iOS アプリ。継続的にリリースされます（iOS アプリは TestFlight への継続的なデプロイのみを行います。詳細は[こちら](#app-store-release)をご覧ください）

`main` へのすべてのプッシュにより、CLI、サーバー、Kura の canary プレリリースが公開されます。これらの各コンポーネントの stable リリースは、メンテナーが十分な期間テストされたリリース候補版を昇格させた場合にのみ作成され、毎週のスケジュールで 3 つのリリース列車が連動して実行されます（[リリースチャネル](#release-channels)を参照）。アプリは `main` へのすべてのプッシュで stable を公開します。

## 仕組み

### 1. コミット規約

コミットメッセージの構造化には [Conventional Commits](https://www.conventionalcommits.org/) を使用しています。これにより、ツールが変更の性質を理解し、バージョンアップを決定し、適切な changelog を生成できます。

形式：`type(scope): description`

#### コミットタイプとその影響

| タイプ | 説明 | バージョンへの影響 | 例 |
|------|-------------|----------------|---------|
| `feat` | 新機能または機能追加 | マイナーバージョンアップ（x.Y.z） | `feat(cli): add support for Swift 6` |
| `fix` | バグ修正 | パッチバージョンアップ（x.y.Z） | `fix(app): resolve crash when opening projects` |
| `docs` | ドキュメントの変更 | リリースなし | `docs: update installation guide` |
| `style` | コードスタイルの変更 | リリースなし | `style: format code with swiftformat` |
| `refactor` | コードのリファクタリング | リリースなし | `refactor(server): simplify auth logic` |
| `perf` | パフォーマンスの改善 | パッチバージョンアップ | `perf(cli): optimize dependency resolution` |
| `test` | テストの追加/変更 | リリースなし | `test: add unit tests for cache` |
| `chore` | メンテナンスタスク | リリースなし | `chore: update dependencies` |
| `ci` | CI/CD の変更 | リリースなし | `ci: add workflow for releases` |

CLI では、これらのアップによって canary バージョンと changelog のグループ化が決定されます。stable CLI バージョンのマイナーライン（`X.Y.0`）は手動で作成され、stable パッチ（`X.Y.Z`）はバックポートからのみ提供されるため、`feat` または `fix` は即時の stable リリースではなく、以下のチャネルフローを通じて CLI ユーザーに届けられます。

#### 破壊的変更

破壊的変更はメジャーバージョンアップ（X.0.0）を引き起こし、コミット本文に記載する必要があります：

```
feat(cli): change default cache location

BREAKING CHANGE: The cache is now stored in ~/.tuist/cache instead of .tuist-cache.
Users will need to clear their old cache directory.
```

### 2. 変更検出

各コンポーネントは [git cliff](https://git-cliff.org/) を使用して以下の処理を行います：
- 最後のリリース以降のコミットを分析
- スコープ（cli、app、server）でコミットをフィルタリング
- リリース可能な変更があるかどうかを判定
- changelog を自動生成

### 3. リリースパイプライン

リリース可能な変更が検出された場合：

1. **バージョン計算**：パイプラインが次のバージョン番号を決定
2. **Changelog 生成**：git cliff がコミットメッセージから changelog を作成
3. **ビルドプロセス**：コンポーネントのビルドとテストを実行
4. **アーティファクト生成**：CLI バンドル、チェックサム、および `tuist --experimental-dump-help` から生成される `tuist.spec.json` CLI 仕様など、リリース固有のアセットを作成
5. **リリース作成**：アーティファクトを含む GitHub リリースを作成
6. **配布**：パッケージマネージャーに更新をプッシュ（例：CLI の Homebrew）

アプリの場合、これはマージごとに stable リリースを生成します。CLI、サーバー、Kura の場合、この同じ自動パイプラインは **canary** プレリリースのみを生成します。リリース候補版と stable リリースは毎週のリリース列車で作成されます（[リリースチャネル](#release-channels)を参照）。

### 4. スコープフィルタリング

各コンポーネントは、関連する変更がある場合にのみリリースされます：

- **CLI**：`(cli)` スコープを持つコミット、またはスコープなしのコミット
- **App**：`(app)` スコープを持つコミット
- **Server**：`(server)` スコープを持つコミット

## リリースチャネル

CLI、サーバー、Kura は `main` へのすべてのプッシュで stable リリースに昇格しません。それぞれが 3 つのチャネルを通じて出荷されるため、推奨されるインストールは安定しており変化が緩やかである一方、早期採用者はコミットごとのビルドを利用できます。ユーザー向けドキュメントは <.localized_link href="/cli/release-channels">CLI リリースチャネル</.localized_link> および <.localized_link href="/guides/server/self-host/release-channels">サーバーリリースチャネル</.localized_link> にあります。このセクションはメンテナー向けの運用マニュアルです。

すべてのコンポーネントで同じ 3 つのチャネルを使用します：

| チャネル | バージョン | 作成者 |
|---------|---------|--------|
| Canary | `X.Y.0-canary.N` | 自動的に、`main` へのコンポーネントに影響するすべてのプッシュ時（`<component>-release.yml`。Kura の場合は `kura/` が変更されたときに `server-production-deployment.yml` によって呼び出される） |
| Release candidate | `X.Y.0-rc.N` | 毎週月曜日、または手動で、`releases/<component>-<major>.<minor>.x` ブランチ上（`<component>-rc.yml`） |
| Stable | `X.Y.Z` | 毎週月曜日、または手動で、十分な期間テストされた RC を昇格させることで（`<component>-promote.yml`）。パッチは `<component>-backport.yml` 経由 |

Canary と RC ビルドは GitHub プレリリースとして公開されます（「Latest」とマークされることはなく、GHCR 上の `:latest` は移動せず、CLI の Homebrew にもプッシュされないため）、パッケージマネージャーとイメージリゾルバーは明示的なオプトインの場合のみこれらを取得します。Canary は常に次の未リリースのマイナーバージョンを対象とします。RC ラインが作成されると、`main` の canary は次のマイナーバージョンに進みます。

ホスト型 Tuist は stable 列車を待ちません。サーバーはコミットごとにデプロイされ、ホスト型 canary と本番環境は最新の Kura canary を実行します。デプロイのカスケードはその canary 自体をデプロイ前に公開するため、`kura-release.yml` には独自のトリガーがありません。Kura リリースツールの変更のみ（`mise/tasks/kura/**`、`kura-*.yml` ワークフロー）では canary は作成されません。

バージョン番号を手動で選ぶことはありません。各チャネルの次のバージョンは、以下のワークフローが呼び出す `mise/tasks/<component>/release/channel-version.sh` によって既存の git タグから導出されます。

リリースブランチはコンポーネントごとに名前空間分けされています（`releases/server-X.Y.x`、`releases/kura-X.Y.x`、CLI の場合は `releases/X.Y.x`）。これにより、3 つのコンポーネントのラインが同じマイナーバージョンで衝突することはありません。

### 毎週のスケジュール

毎週月曜日の 06:00 UTC に、3 つのコンポーネントの昇格ジョブが連動して実行されます。**CLI Promote to Stable**、**Server Promote to Stable**、**Kura Promote to Stable** です。それぞれがまだ stable ではない最新の RC ラインを昇格させます。通常は前週の月曜日に作成されたラインです。そのようなラインがない場合、そのジョブは何も公開しません。

昇格が完了すると、結果にかかわらず、対応する **Release Candidate** ワークフロー（`cli-rc.yml`、`server-rc.yml`、`kura-rc.yml`）が `workflow_run` 経由で起動し、`main` から次のラインを作成します。

スケジュールされた実行のいずれかが失敗またはキャンセルされた場合、Slack にメッセージが投稿されます。リリースブランチに最新の RC 以降のコミットがある場合、昇格は失敗します。そのラインを出荷するには、そこに新しい RC を作成し、手動で昇格させてください。そうでない場合は、次の月曜日に新しいラインが代わりに昇格されます。

### リリース候補版の作成

毎週のスケジュール外で新しいラインを作成するには（以下のコンポーネントのワークフロー名に置き換えてください）：

1. `branch` 入力を空にして、**\<Component\> Release Candidate** ワークフロー（例：`server-rc.yml`）を実行します。
2. `X.Y.0-rc.1` が公開され、成功すると、ビルドされたコミットで保護された `releases/<component>-X.Y.x` ブランチが作成されます。

重要な修正や回帰を soaking ラインに取り込むには、PR を介してリリースブランチに cherry-pick し（バックポートと同じフローです。CI は cherry-pick を行いません）、その後 RC を反復します：

1. `releases/<component>-X.Y.x` からブランチを切り、修正を cherry-pick し、リリースブランチへの PR を開き、競合があれば解決してマージします。
2. `branch=releases/<component>-X.Y.x` で **Release Candidate** ワークフローを再度実行します。これにより、ブランチ HEAD から `X.Y.0-rc.(N+1)` が公開されます。

soaking ラインは機能フリーズされています。重要な修正と回帰のみが取り込まれます。

### stable への昇格

毎週のスケジュール外でラインを昇格させるには、その RC が問題なく soaking された後に行います：

1. `branch=releases/<component>-X.Y.x` で **\<Component\> Promote to Stable** ワークフロー（例：`server-promote.yml`）を実行します。
2. `make_latest=true` で semver タグ付きイメージを公開し、GHCR の `:latest` タグと GitHub の「Latest」ポインタを移動します。CLI はさらに Homebrew formula を更新します。

ブランチ HEAD が最新の RC が指すコミットと正確に一致しない限り、昇格は実行されません。したがって、最後の RC 以降にラインにマージされた修正がある場合は、新しい RC を作成し、stable として出荷できるまで soaking させなければなりません。

### stable ラインへの修正のバックポート

ラインが stable になったら、CLI 専用の **Backport Release** ワークフロー（`cli-backport.yml`）を使用してパッチを出荷します。`releases/X.Y.x` への修正を PR を介して cherry-pick し、そのブランチでワークフローを実行して `X.Y.(Z+1)` を作成します。バックポートは「Latest」ポインタや Homebrew formula を移動しません。同時に 2 つのラインが維持されます。現在のラインは回帰とセキュリティ修正を受け入れ、前のラインは重要な修正とセキュリティ修正のみを受け入れます。その他のバグ修正はバックポートされず、次のマイナーバージョンで出荷されます。

サーバーと Kura の場合は、**Server Backport Release**（`server-backport.yml`）または **Kura Backport Release**（`kura-backport.yml`）を使用します。昇格は RC の `X.Y.0` のみを公開します。すでに stable なラインにパッチを適用することはできません。

1. 選択した `X.Y` ラインの最新公開 stable コンポーネントタグから開始し、既存の `releases/server-X.Y.x` または `releases/kura-X.Y.x` ブランチにサージカルな修正 PR を開きます。新しいマイナーまたはメジャーリリースがあっても、維持されているラインへのパッチ適用は妨げられません。無関係な main の変更は含めないでください。
2. ソース PR をレビューしてマージします。リモートリリースブランチを取得し、コンポーネントのサポート対象プラットフォームと TLS のポジティブ/ネガティブコントロールを含めて、その **final merged tip** を認定します。マージ前のヘッドが合格しても、異なる squash またはマージコミットの認定にはなりません。
3. 個別の公開承認を得て、一致するバックポートワークフローを **from main** でディスパッチし、`source_sha` をその正確に認定されたマージ済みチップに、`base_tag` を現在の stable タグ（`server@X.Y.Z` や `kura@X.Y.Z` など）に設定します。ワークフローは `X.Y.(Z+1)` を導出します。オペレーターはマイナーバージョンアップや canary コンテンツの昇格を選択しません。

計画段階では、正確なリモートブランチとベースタグを更新し、選択されたソースがブランチの先端と一致することを要求し、変更されていないソースやコンポーネント外の変更、その信頼ポリシー入力と検証を拒否し、解決されたベースコミットを固定します。main ソースのコントロールは、バージョン付きイメージと GitHub の公開直前にこれらのチェックを繰り返します。ソースブランチ、stable ベース、または利用可能なバージョンが変更された場合は、新しいソースに置き換えるのではなく、停止して再認定してください。

バックポートは、GitHub の「Latest」ポインタや GHCR `:latest` を移動することなく、既存のマルチプラットフォームパブリッシャーを使用します。公開はホスト型デプロイとは別です。これらのワークフローは、ホスト型サーバーや Kura フリートを昇格させたり、canary 受け入れを bypass したり、インストールされたランタイムを認定したりしません。ビルドヘルパーと Dockerfile は引き続き選択された stable ソースから取得されます。コントロールは公開ゲートであり、認証情報不要のビルドジョブではありません。ビルドは最終ゲートの前にタグなしのイメージダイジェストをアップロードできます。イメージと GitHub の公開はアトミックではありません。イメージタグが公開された後に後のゲートが失敗した場合、部分的なリリースを検査し、元のソースと成果物を保持してください。既存のリリースを置き換えたり、そのタグの下で異なるバイトを使用したりしないでください。

## 適切なコミットメッセージの書き方

コミットメッセージはリリースノートに直接影響するため、明確で説明的なメッセージを書くことが重要です：

### 推奨事項：
- 現在形を使用する：「added feature」ではなく「add feature」
- 簡潔かつ説明的にする
- 変更がコンポーネント固有の場合、スコープを含める
- 該当する場合、issue を参照する：`fix(cli): resolve build cache issue (#1234)`

### 避けるべきこと：
- 「fix bug」や「update code」のような曖昧なメッセージを使用しない
- 複数の無関係な変更を 1 つのコミットに混ぜない
- 破壊的変更の情報を含めるのを忘れない

### 破壊的変更

破壊的変更の場合は、コミット本文に `BREAKING CHANGE:` を含めます：

```
feat(cli): change cache directory structure

BREAKING CHANGE: Cache files are now stored in a new directory structure.
Users need to clear their cache after updating.
```

## リリースワークフロー

CLI、サーバー、Kura はそれぞれ独自のチャネルワークフローセットを持ち、同じ形状に従います：

- `<component>-release.yml` - `main` へのコンポーネントに影響するプッシュごとに canary を公開します（Kura の場合は、`kura/` が変更されたときに `server-production-deployment.yml` が呼び出す再利用可能なワークフローです）
- `<component>-rc.yml` - 毎週月曜日にリリース候補版を作成します（昇格後の `workflow_run` 経由）、または手動で作成または反復します
- `<component>-promote.yml` - 毎週月曜日の 06:00 UTC に pending RC を stable に昇格させます、または soaking された RC を手動で昇格させます
- `<component>-build-publish.yml` - 上記 3 つが呼び出す共有ビルドおよび公開パイプライン

CLI、サーバー、Kura にはさらに、stable ラインのパッチを作成するための `<component>-backport.yml` があります。コンポーネントのすべてのワークフローは 1 つの `<component>-publish` 並行グループを通じてシリアル化されるため、バージョン解決とタグ付けが競合することはありません。Kura は例外です。その canary は `kura-canary-publish` を使用し、RC、昇格、バックポートは `kura-stable-publish` を使用するため、長い stable ビルドがデプロイのカスケードをブロックすることはありません。タグの名前空間は互いに素であるため、2 つのグループが衝突することはありません。

Helm チャートとインフラストラクチャイメージ（CAPI operator、runners controller、xcresult processor image、linux runner image など）は、引き続き `.github/workflows/server-production-deployment.yml` を介してリリースされます。これは `main` へのプッシュで実行され、ホスト型デプロイのために canary → 受け入れテスト → production とカスケードし、それらのインフラコンポーネントが変更されるたびに公開します。アプリ、キャッシュ、Gradle プラグイン、skills、Noora、およびスタンドアロンのインフラコントローラーはそれぞれ専用の `*-release.yml` ワークフローを持っています。これらはすべて変更検出を共有しています：`mise/tasks/release/components.json` が各コンポーネントのタグプレフィックスと include パスを宣言し、git cliff が一致するコミットをリリースノートに変換します。

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
2. コミットメッセージが conventional format に従っていることを確認する
3. すべてのテストが合格していることを確認する
4. コンポーネントが正常にビルドされていることを確認する

即時リリースが必要な緊急修正の場合：
1. コミットに明確なスコープが含まれていることを確認する
2. マージ後、リリースワークフローを監視する
3. サーバーまたはアプリの場合、修正は次のプッシュで提供されます。必要に応じて、手動リリースをトリガーしてください
4. CLI の場合、修正は自動的に canary に反映されます。stable ユーザーに提供するには、メンテナンスされている stable ラインにバックポートしてください（[stable ラインへの修正のバックポート](#backporting-fixes-to-a-stable-line)を参照）

## App Store リリース

CLI と Server は上記の継続的リリースプロセスに従いますが、Apple の App Store レビュープロセスのため、**iOS アプリ**は例外です：

- **手動リリース**：iOS アプリのリリースには App Store への手動提出が必要です
- **レビューの遅延**：各リリースは Apple のレビュープロセスを経る必要があり、1〜7 日かかることがあります
- **変更のバンドル**：複数の変更は通常、各 iOS リリースでまとめてバンドルされます
- **TestFlight**：App Store リリース前にベータ版を TestFlight で配布できます
- **リリースノート**：App Store のガイドラインに合わせて具体的に記述する必要があります

iOS アプリは同じコミット規約に従い、changelog 生成に git cliff を使用しますが、実際のユーザーへのリリースは頻度が低く、手動スケジュールで行われます。
