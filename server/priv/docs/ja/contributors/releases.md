---
{
  "title": "リリース",
  "titleTemplate": ":title | コントリビューター | Tuist",
  "description": "Tuist の継続的リリースプロセスの仕組みを学ぶ"
}
---
# リリース

変更が main ブランチにマージされると、Tuist は新しいバージョンを自動的に公開します。CLI、サーバー、Kura キャッシュサーバーはすべてリリースチャネル（canary、release candidate、stable）を通じて提供されるため、推奨されるインストールは安定しており頻繁な更新が行われません。リリース候補の作成と stable への昇格は、意図的かつ毎週行われる手順です。アプリは継続的にリリースされます（iOS アプリは TestFlight への継続的なデプロイのみを行います。詳細は[こちら](#app-store-release)をご覧ください）。

## 概要

以下の主要コンポーネントをリリースしています：
- **Tuist CLI** - コマンドラインツール。canary、release candidate、stable の[チャネル](#release-channels)を通じて提供されます
- **Tuist Server** - バックエンドサービス。CLI と同じチャネルモデルで提供されます
- **Kura** - キャッシュサーバー。CLI と同じチャネルモデルで提供されます
- **Tuist App** - macOS および iOS アプリ。継続的にリリースされます（iOS アプリは TestFlight への継続的なデプロイのみを行います。詳細は[こちら](#app-store-release)をご覧ください）

`main` へのすべてのプッシュにより、CLI、サーバー、Kura の canary プレリリースが公開されます。これらの各コンポーネントの stable リリースは、メンテナーが十分に検証されたリリース候補を昇格させたときのみ作成され、毎週のスケジュールで 3 つのリリースプロセスが連動して実行されます（詳細は[リリースチャネル](#release-channels)をご覧ください）。アプリは `main` へのすべてのプッシュで stable を公開します。

## 仕組み

### 1. コミット規約

コミットメッセージの構造化には [Conventional Commits](https://www.conventionalcommits.org/) を使用しています。これにより、ツールが変更の内容を理解し、バージョンアップを決定し、適切な changelog を生成できます。

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

CLI では、これらのアップによって canary バージョンと changelog のグループ化が決まります。stable CLI バージョンのマイナーライン（`X.Y.0`）は手動で作成され、stable パッチ（`X.Y.Z`）はバックポートからのみ提供されるため、`feat` または `fix` は即時の stable リリースではなく、以下のチャネルフローを通じて CLI ユーザーに届きます。

#### 破壊的変更

破壊的変更はメジャーバージョンアップ（X.0.0）を引き起こし、コミット本文に示す必要があります：

```
feat(cli): change default cache location

BREAKING CHANGE: The cache is now stored in ~/.tuist/cache instead of .tuist-cache.
Users will need to clear their old cache directory.
```

### 2. 変更検出

各コンポーネントは [git cliff](https://git-cliff.org/) を使用して以下の処理を行います：
- 前回リリース以降のコミットを分析
- スコープ（cli、app、server）ごとにコミットをフィルタリング
- リリース可能な変更があるかどうかを判定
- changelog を自動生成

### 3. リリースパイプライン

リリース可能な変更が検出された場合：

1. **バージョン計算**：パイプラインが次のバージョン番号を決定
2. **Changelog 生成**：git cliff がコミットメッセージから changelog を作成
3. **ビルドプロセス**：コンポーネントをビルドおよびテスト
4. **アーティファクト生成**：CLI バンドル、チェックサム、`tuist --experimental-dump-help` から生成された `tuist.spec.json` CLI 仕様など、リリース固有のアセットを作成
5. **リリース作成**：アーティファクト付きの GitHub リリースを作成
6. **配布**：パッケージマネージャーに更新をプッシュ（例：CLI の Homebrew）

アプリの場合、これはマージごとに stable リリースを生成します。CLI、サーバー、Kura の場合、この同じ自動パイプラインは **canary** プレリリースのみを生成します。リリース候補と stable リリースは毎週のリリーストレインで作成されます（詳細は[リリースチャネル](#release-channels)をご覧ください）。

### 4. スコープフィルタリング

各コンポーネントは、関連する変更がある場合にのみリリースされます：

- **CLI**：`(cli)` スコープまたはスコープなしのコミット
- **App**：`(app)` スコープのコミット
- **Server**：`(server)` スコープのコミット

## リリースチャネル

CLI、サーバー、Kura は `main` へのすべてのプッシュで stable リリースに昇格されるわけではありません。推奨されるインストールが安定して緩やかに更新されるよう、また早期採用者がコミットごとのビルドを利用できるよう、それぞれが 3 つのチャネルを通じて出荷されます。ユーザー向けドキュメントは <.localized_link href="/cli/release-channels">CLI リリースチャネル</.localized_link> および <.localized_link href="/guides/server/self-host/release-channels">サーバーリリースチャネル</.localized_link> にあります。このセクションはメンテナー向けの運用ガイドです。

すべてのコンポーネントで同じ 3 つのチャネルを使用しています：

| チャネル | バージョン | 作成者 |
|---------|---------|--------|
| Canary | `X.Y.0-canary.N` | 自動。`main` へのコンポーネントに影響するすべてのプッシュ時（`<component>-release.yml`。Kura の場合、`kura/` が変更された際に `server-production-deployment.yml` によって呼び出されます） |
| リリース候補 | `X.Y.0-rc.N` | 毎週月曜日、または手動。`releases/<component>-<major>.<minor>.x` ブランチ上（`<component>-rc.yml`） |
| Stable | `X.Y.Z` | 毎週月曜日、または手動。十分に検証された RC を昇格させることで（`<component>-promote.yml`）。パッチは `<component>-backport.yml` を経由 |

Canary と RC ビルドは GitHub プレリリースとして公開されます（「Latest」マークは付かず、GHCR 上の `:latest` は移動せず、CLI の Homebrew にもプッシュされません）。そのため、パッケージマネージャーやイメージリゾルバーは明示的なオプトイン時のみこれらを取得します。Canary は常に次の未リリースのマイナーバージョンを対象とします。RC ラインが作成されると、`main` の canary は次のマイナーバージョンに進みます。

ホスト版 Tuist は stable トレインを待ちません。サーバーはコミットごとにデプロイされ、ホスト版 canary と本番環境は最新の Kura canary を実行します。デプロイのカスケードはその canary 自体をデプロイ前に公開するため、`kura-release.yml` には独自のトリガーがありません。Kura リリースツールの変更のみ（`mise/tasks/kura/**`、`kura-*.yml` ワークフロー）では canary は作成されません。

バージョン番号を手動で選択することはありません。各チャネルの次のバージョンは、以下のワークフローが呼び出す `mise/tasks/<component>/release/channel-version.sh` によって既存の git タグから導出されます。

リリースブランチはコンポーネントごとに名前空間化されています（`releases/server-X.Y.x`、`releases/kura-X.Y.x`、CLI の場合は `releases/X.Y.x`）。これにより、3 つのコンポーネントのラインが同じマイナーバージョンで衝突することはありません。

### 毎週のスケジュール

毎週月曜日の 06:00 UTC に、3 つのコンポーネントの昇格ジョブが連動して実行されます：**CLI Promote to Stable**、**Server Promote to Stable**、**Kura Promote to Stable**。それぞれがまだ stable になっていない最新の RC ラインを昇格させます。通常、これは前週月曜日に作成されたラインです。そのようなラインがない場合、そのジョブは何も公開しません。

昇格が完了すると、結果にかかわらず、対応する **Release Candidate** ワークフロー（`cli-rc.yml`、`server-rc.yml`、`kura-rc.yml`）が `workflow_run` を介して起動し、`main` から次のラインを作成します。

スケジュールされた実行のいずれかが失敗またはキャンセルされた場合、Slack にメッセージが投稿されます。リリースブランチに最新の RC 以降のコミットがある場合、昇格は失敗します。そのラインを出荷するには、新しい RC を作成して手動で昇格させてください。そうでない場合は、次の月曜日に新しいラインが代わりに昇格されます。

### リリース候補の作成

毎週のスケジュール外で新しいラインを作成するには（以下のコンポーネントのワークフロー名に置き換えてください）：

1. 空の `branch` 入力で **\<Component\> Release Candidate** ワークフロー（例：`server-rc.yml`）を実行します。
2. これにより `X.Y.0-rc.1` が公開され、成功するとビルドされたコミットで保護された `releases/<component>-X.Y.x` ブランチが作成されます。

重要な修正や回帰を soaking ラインに取り込むには、PR を介してリリースブランチに cherry-pick し（バックポートと同じフローです。CI は決して cherry-pick しません）、その後 RC を反復します：

1. `releases/<component>-X.Y.x` からブランチを作成し、修正を cherry-pick して、リリースブランチへの PR を開き、競合があれば解決してマージします。
2. `branch=releases/<component>-X.Y.x` で **Release Candidate** ワークフローを再度実行します。これにより、ブランチの HEAD から `X.Y.0-rc.(N+1)` が公開されます。

soaking ラインは機能フリーズされています。重要な修正と回帰のみが含まれます。

### stable への昇格

毎週のスケジュール外でラインを昇格させるには、その RC が問題なく soaking された後に行います：

1. `branch=releases/<component>-X.Y.x` で **\<Component\> Promote to Stable** ワークフロー（例：`server-promote.yml`）を実行します。
2. これにより、`make_latest=true` を使用して semver タグ付きイメージが公開され、GHCR の `:latest` タグと GitHub の「Latest」ポインタが移動します。CLI はさらに Homebrew formula を更新します。

ブランチの HEAD が最新の RC が指しているコミットと完全に一致しない限り、昇格は実行されません。したがって、最後の RC 以降にラインにマージされた修正がある場合は、新しい RC を作成し、stable として出荷できるまで soaking させる必要があります。

### stable ラインへの修正のバックポート

ラインが stable になると、CLI 専用の **Backport Release** ワークフロー（`cli-backport.yml`）を使用してパッチを出荷します。`releases/X.Y.x` への修正を PR を介して cherry-pick し、そのブランチでワークフローを実行して `X.Y.(Z+1)` を作成します。バックポートは「Latest」ポインタや Homebrew formula を移動させません。同時に 2 つのラインが維持されます。現在のラインは回帰とセキュリティ修正を受け入れ、前のラインは重要な修正とセキュリティ修正のみを受け入れます。その他のバグ修正はバックポートされず、次のマイナーバージョンで出荷されます。

サーバーと Kura の場合、現在のバックポートは古いリリースブランチに対して昇格ワークフローを実行することで作成されます。今後の作業で、CLI に倣った専用のバックポートワークフローが追加される予定です。

## 適切なコミットメッセージの書き方

コミットメッセージはリリースノートに直接影響するため、明確で説明的なメッセージを書くことが重要です：

### 行うべきこと：
- 現在形を使用する：「added feature」ではなく「add feature」
- 簡潔でありながら説明的である
- 変更がコンポーネント固有の場合、スコープを含める
- 該当する場合は issue を参照する：`fix(cli): resolve build cache issue (#1234)`

### 避けるべきこと：
- 「fix bug」や「update code」のような曖昧なメッセージを使用しない
- 複数の無関係な変更を 1 つのコミットに混ぜない
- 破壊的変更の情報を含めるのを忘れない

### 破壊的変更

破壊的変更の場合、コミット本文に `BREAKING CHANGE:` を含めます：

```
feat(cli): change cache directory structure

BREAKING CHANGE: Cache files are now stored in a new directory structure.
Users need to clear their cache after updating.
```

## リリースワークフロー

CLI、サーバー、Kura はそれぞれ独自のチャネルワークフローセットを持ち、同じ形式に従います：

- `<component>-release.yml` - `main` へのコンポーネントに影響するすべてのプッシュで canary を公開します（Kura の場合は、`kura/` が変更されたときに `server-production-deployment.yml` が呼び出す再利用可能なワークフローです）
- `<component>-rc.yml` - 毎週月曜日にリリース候補を作成します（昇格後の `workflow_run` を介して）、または手動で作成または反復します
- `<component>-promote.yml` - 毎週月曜日の 06:00 UTC に pending RC を stable に昇格させるか、soaking された RC を手動で昇格させます
- `<component>-build-publish.yml` - 上記 3 つが呼び出す共有ビルドおよび公開パイプライン

CLI にはさらに、stable ラインでパッチを作成するための `cli-backport.yml` があります。コンポーネントのすべてのワークフローは 1 つの `<component>-publish` 同時実行グループを通じて直列化されるため、バージョン解決とタグ付けが競合することはありません。Kura は例外です。canary は `kura-canary-publish` を使用し、RC と昇格は `kura-stable-publish` を使用するため、長時間の RC または昇格ビルドがデプロイのカスケードを妨げることはありません。タグの名前空間は互いに素であるため、2 つのグループが衝突することはありません。

Helm チャートとインフラストラクチャイメージ（CAPI operator、runners controller、xcresult processor image、linux runner image など）は依然として `.github/workflows/server-production-deployment.yml` を介してリリースされます。これは `main` へのプッシュで実行され、ホストデプロイのために canary → 受け入れテスト → 本番環境へとカスケードし、それらのインフラコンポーネントが変更されると公開します。アプリ、キャッシュ、Gradle プラグイン、skills、Noora、およびスタンドアロンのインフラコントローラーはそれぞれ専用の `*-release.yml` ワークフローを持っています。これらはすべて変更検出を共有します。`mise/tasks/release/components.json` は各コンポーネントのタグプレフィックスと include パスを宣言し、git cliff が一致するコミットをリリースノートに変換します。

CLI ビルド（`cli-build-publish.yml`）は、下流のツールがコマンドインターフェースを利用できるように、`tuist --experimental-dump-help` から生成された `tuist.spec.json` アーティファクトも作成および公開します。

## リリースの監視

リリースは以下を通じて監視できます：
- [GitHub Releases ページ](https://github.com/tuist/tuist/releases)
- ワークフロー実行用の GitHub Actions タブ
- 各コンポーネントディレクトリ内のチェンジログファイル

## メリット

この継続的リリースアプローチにより、以下が実現されます：

- **迅速な提供**：変更はマージ直後にユーザーに届きます
- **ボトルネックの削減**：手動リリースを待つ必要がありません
- **明確なコミュニケーション**：コミットメッセージから自動生成されるチェンジログ
- **一貫したプロセス**：すべてのコンポーネントで同じリリースフロー
- **品質保証**：テスト済みの変更のみがリリースされます

## トラブルシューティング

リリースが失敗した場合：

1. 失敗したワークフローの GitHub Actions ログを確認する
2. コミットメッセージが conventional format に従っていることを確認する
3. すべてのテストがパスしていることを確認する
4. コンポーネントが正常にビルドされていることを確認する

即時リリースが必要な緊急の修正の場合：
1. コミットに明確なスコープが含まれていることを確認する
2. マージ後、リリースワークフローを監視する
3. サーバーまたはアプリの場合、修正は次のプッシュで提供されます。必要に応じて、手動リリースをトリガーしてください
4. CLI の場合、修正は自動的に canary に反映されます。stable ユーザーに届けるには、メンテナンス中の stable ラインにバックポートしてください（[stable ラインへの修正のバックポート](#backporting-fixes-to-a-stable-line)を参照）

## App Store リリース

CLI と Server は上記の継続的リリースプロセスに従いますが、Apple の App Store レビュープロセスのため、**iOS アプリ**は例外となります：

- **手動リリース**：iOS アプリのリリースには App Store への手動提出が必要です
- **レビューの遅延**：各リリースは Apple のレビュープロセスを経る必要があり、1〜7日かかる場合があります
- **変更のバッチ化**：複数の変更は通常、各 iOS リリースでまとめてバンドルされます
- **TestFlight**：ベータ版は App Store リリース前に TestFlight を介して配布される場合があります
- **リリースノート**：App Store のガイドラインに合わせて具体的に作成する必要があります

iOS アプリは同じコミット規約に従い、git cliff を使用してチェンジログを生成しますが、実際のユーザーへのリリースは頻度が低く、手動のスケジュールで行われます。
