---
{
  "title": "リリースチャンネル",
  "titleTemplate": ":title | セルフホスティング | サーバー | ガイド | Tuist",
  "description": "Tuistがcanary、release candidate、stableの各チャンネルでサーバーおよびKuraのDockerイメージをどのように提供するか、そして信頼できるラインにデプロイメントを固定する方法について説明します。"
}
---

# リリースチャネル {#release-channels}

TuistサーバーとKuraキャッシュサーバーは、異なる安定性保証を持つ3つのGHCRイメージチャネルを通じて提供されます。推奨されるインストールは**stable**で、週に1回更新されます。`main`に機能がマージされるたびに進行するわけではないため、アップグレードしても無関係な変更のバッチを取り込む必要がなくなりました。早期採用者は引き続き**canary**でコミットごとのビルドを実行でき、**release candidate**チャネルを使用すると、stableになる前の upcoming line を十分に検証できます。

サーバーとKuraは同じ週次リリースサイクルに従い、どちらも[Tuist CLIのリリーススケジュール](/en/cli/release-channels)と連動して動作します。

## チャネル {#the-channels}

| チャネル | バージョン形式 | 頻度 | `:latest`を更新するか？ |
| --- | --- | --- | --- |
| Canary | `X.Y.0-canary.N`（例：`1.351.0-canary.5`） | `main`へのすべてのコミット | いいえ、明示的なオプトインが必要 |
| Release candidate | `X.Y.0-rc.N`（例：`1.351.0-rc.1`） | 毎週月曜日に`main`からカットされ、約1週間検証 | いいえ、明示的なオプトインが必要 |
| Stable | `X.Y.Z`（例：`1.350.2`、`1.351.0`） | 正常に検証された後、毎週月曜日にプロモート | **はい** |

Canaryおよびrelease candidateのビルドはGitHubのプレリリースとして公開されます。`:latest`を解決する際にプレリリースを除外するツールはこれらをスキップするため、明示的に指定しない限りこれらのバージョンに到達することはありません。

### Canary {#canary}

`main`へのすべてのコミットはcanaryイメージを公開します。Canaryは常に**次の未リリースマイナーバージョン**を表します。リリース用にラインがカットされると、`main`は次のマイナーバージョンに進みます（例：`1.350.0-canary.42`から`1.351.0-canary.1`へ）。Canaryは、本番環境をミラーリングし、回帰に対する最も早いシグナルを提供するステージング環境や、報告した修正がstableに到達する前に期待通りに動作することを確認するのに適したチャネルです。

```
ghcr.io/tuist/tuist:1.351.0-canary.5
ghcr.io/tuist/kura:0.55.0-canary.5
```

### Release candidate {#release-candidate}

マイナーバージョンの出荷準備が整うと、そのラインは保護された`releases/server-<major>.<minor>.x`（または`releases/kura-<major>.<minor>.x`）ブランチに凍結され、`X.Y.0-rc.1`として公開されます。このラインは機能凍結されており、重要な修正と回帰のみがチェリーピックされ、受け入れられた修正ごとにrelease candidateが更新されます（`-rc.2`、`-rc.3`など）。検証期間が正常に終了すると、そのラインは翌月曜日にstableへプロモートされます。

```
ghcr.io/tuist/tuist:1.351.0-rc.1
ghcr.io/tuist/kura:0.55.0-rc.1
```

### Stable {#stable}

Stableは推奨されるチャネルであり、すべてのドキュメントが参照するチャネルです。stableマイナーバージョン（`X.Y.0`）は、release candidateが正常に検証された場合にのみ公開され、新機能が`main`にマージされても**進行しません**。stableライン上のパッチ（`X.Y.1`、`X.Y.2`など）にはバックポートされた修正のみが含まれ、新機能は含まれません。`:latest`はstableのプロモート時のみ更新されます。

```
ghcr.io/tuist/tuist:1.351.0
ghcr.io/tuist/kura:0.55.0
ghcr.io/tuist/tuist:latest
ghcr.io/tuist/kura:latest
```

## 月曜日リリース {#the-monday-train}

毎週月曜日の06:00 UTCに、3つのコンポーネントのリリーストレインが連動して実行されます：

1. **06:00 UTC** — プロモートジョブが実行されます。各ジョブは、まだstableではない最新のrelease candidateライン（通常は前週月曜日にカットされたライン）をプロモートし、該当するラインがない場合は何もしません。
2. **各プロモート完了後** — release candidateジョブが`main`から次のラインをカットするため、新しくカットされたラインは同じ実行内でプロモートされることはありません。

プロモートに失敗するとカットが保留されます。最新のstableより上位のrelease candidateラインの中で最も高いもののみが選択されるため、失敗した状態で次のラインをカットすると、出荷されなかったラインが取り残されてしまいます。翌月曜日には保留されていたラインが自動的に再試行されます。

## チャネルの固定 {#pinning-a-channel}

デプロイマニフェスト、Helm values、またはDocker Composeファイルで、必要な特定のタグを固定してください。Helmチャートを使用した例：

```yaml
server:
  image:
    repository: ghcr.io/tuist/tuist
    tag: "1.350.2"          # Pinned to a stable patch
    # tag: "1.351.0-rc.1"   # Or opt into a release candidate to soak it
    # tag: "1.351.0-canary.5" # Or opt into a specific canary build

kuraRuntime:
  image:
    repository: ghcr.io/tuist/kura
    tag: "0.54.0"           # Same three channels apply to Kura
```

`:latest`は`ghcr.io/tuist/tuist`と`ghcr.io/tuist/kura`の両方で最新のstableを追跡し、月曜日のプロモート時にのみ更新されます。`:latest`を固定すると、タグを更新せずに週次stableサイクルを利用できます。特定のバージョンを固定すると、アップグレードのタイミングを完全に制御できます。

## 推奨戦略 {#recommended-strategy}

チャネルが存在するのは、「最新の修正を取得すること」と「最新機能を取得すること」を分離できるようにするためです。安全で手間のかからないデフォルト設定は以下の通りです：

1. **本番環境をstableマイナーラインに固定する**（例：`ghcr.io/tuist/tuist:1.351`）。このラインはバックポートされた修正のみを受け取り、新機能は含まれないため、日常のアップグレードは低リスクのままです。次のマイナーバージョンを採用する準備ができたら、固定バージョンを更新してください。
2. **ステージング環境をcanaryまたは特定のrelease candidateタグで実行する。** ステージング環境は、 otherwise ユーザーに到達してしまう回帰を検出します。`main`に近いほどステージングが追跡するため、より早期に問題を見つけられます。現在のrelease candidateライン上でステージング環境を実行することは良い中間策です。これは、翌月曜日にstableとなる正確なバイトを検証します。
3. **実際に出荷された内容については[Server changelog](/changelog)を確認してください。** stableのプロモートごとに、取り込まれたプルリクエストの一覧とともにアナウンスされます。

新機能がstableになると自動的に本番環境にロールアウトさせたい場合は、本番環境を`:latest`に設定してください。タグは毎週月曜日の朝に更新されるため、それに合わせてデプロイの時間枠を計画してください。

## バックポート {#backports}

いつでも2つのstableサーバー（およびKura）ラインが積極的にメンテナンスされています。現在のラインは回帰とセキュリティ修正をバックポートプルリクエストとして受け取り、前のラインは重要な修正とセキュリティ修正のみを受け取ります。古いラインにはバックポートされません。修正を受け取るには、メンテナンスされているラインにアップグレードしてください。新しいラインがstableにプロモートされると、それまで「current」だったラインは「previous」になり、「previous」だったラインはバックポートの受け取りを停止します。

バックポートは必要に応じて`X.Y.(Z+1)`パッチリリースとしてカットされます。これらは`:latest`を更新することはありません。
