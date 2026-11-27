---
{
  "title": "リリースチャンネル",
  "titleTemplate": ":title | セルフホスティング | サーバー | ガイド | Tuist",
  "description": "TuistがCanary、Release Candidate、Stableの各チャンネルでサーバーおよびKuraのDockerイメージをどのように提供するか、そして信頼できるラインにデプロイメントを固定する方法について説明します。"
}
---

# リリースチャネル {#release-channels}

Tuist サーバーと Kura キャッシュサーバーは、安定性の保証が異なる 3 つの GHCR イメージチャネルを通じて提供されます。推奨されるインストールは **stable** で、週に 1 回更新されます。`main` に機能がマージされるたびに進むわけではないため、アップグレードしても無関係な変更を一括で取り込む必要がありません。早期導入者は **canary** でコミットごとのビルドを実行でき、**release candidate** チャネルでは、stable になる前に今後のラインを十分に検証できます。

サーバーと Kura は同じ週次サイクルで動作し、どちらも <.localized_link href="/cli/release/channels">Tuist CLI のリリーススケジュール</.localized_link> と連動して公開されます。

## 現在のリリース {#live-release-status}

各コンポーネントの現在のリリースを以下に示します。パッチやバックポートを含む今後のリリース枠および最近のリリースについては、<.localized_link href="/guides/server/self-host/release/calendar">リリースカレンダー</.localized_link> を参照してください。

<.release_status status={@release_status} components="server,kura" calendar_path="/guides/server/self-host/release/calendar" locale={@locale} />

## チャネル {#the-channels}

| チャネル | バージョン形式 | 更新頻度 | `:latest` を移動するか？ |
| --- | --- | --- | --- |
| Canary | `X.Y.0-canary.N`（例: `1.351.0-canary.5`） | `main` へのすべてのコミット | いいえ、明示的なオプトインが必要 |
| Release candidate | `X.Y.0-rc.N`（例: `1.351.0-rc.1`） | 毎週月曜日に `main` から切り出し、約 1 週間検証 | いいえ、明示的なオプトインが必要 |
| Stable | `X.Y.Z`（例: `1.350.2`、`1.351.0`） | 問題なく検証された後、毎週月曜日に昇格 | **はい** |

Canary および release-candidate ビルドは GitHub のプレリリースとして公開されます。`:latest` を解決する際にプレリリースを除外するツールはこれらをスキップするため、明示的に指定しない限りこれらのバージョンに到達することはありません。

### Canary {#canary}

`main` へのすべてのコミットで canary イメージが公開されます。Canary は常に **次の未リリースのマイナーバージョン** を表します。リリース用にラインが切り出されると、`main` は次のマイナーバージョンに進みます（例: `1.350.0-canary.42` から `1.351.0-canary.1` へ）。Canary は、本番環境をミラーリングし、回帰に関する最も早期のシグナルを提供するステージング環境や、報告した修正が stable に到達する前に期待通りに動作することを検証するのに適したチャネルです。

```
ghcr.io/tuist/tuist:1.351.0-canary.5
ghcr.io/tuist/kura:0.55.0-canary.5
```

### Release candidate {#release-candidate}

マイナーバージョンの出荷準備が整うと、そのラインは保護された `releases/server-<major>.<minor>.x`（または `releases/kura-<major>.<minor>.x`）ブランチに凍結され、`X.Y.0-rc.1` として公開されます。このラインは機能追加が凍結されており、重要な修正と回帰のみが cherry-pick され、受け入れられた修正ごとにリリース候補が更新されます（`-rc.2`、`-rc.3` など）。検証期間が問題なく終了すると、そのラインは翌週の月曜日に stable へ昇格します。

```
ghcr.io/tuist/tuist:1.351.0-rc.1
ghcr.io/tuist/kura:0.55.0-rc.1
```

### Stable {#stable}

Stable は推奨されるチャネルであり、すべてのドキュメントが指し示すものです。stable のマイナーバージョン（`X.Y.0`）は、release candidate が問題なく検証された後にのみ公開され、新機能が `main` にマージされても **進みません**。stable ライン上のパッチ（`X.Y.1`、`X.Y.2` など）にはバックポートされた修正のみが含まれ、新機能は含まれません。`:latest` は stable への昇格時のみ移動します。

```
ghcr.io/tuist/tuist:1.351.0
ghcr.io/tuist/kura:0.55.0
ghcr.io/tuist/tuist:latest
ghcr.io/tuist/kura:latest
```

## 月曜日のトレイン {#the-monday-train}

毎週月曜日の 06:00 UTC に、3 つのコンポーネントのリリーストレインが連動して実行されます。

1. **06:00 UTC** — 昇格ジョブが実行されます。各ジョブは、まだ stable ではない最新の release-candidate ライン（通常は前週の月曜日に切り出されたライン）を昇格させ、該当するラインがない場合は何もしません。
2. **各昇格が完了した後** — release-candidate ジョブが `main` から次のラインを切り出すため、新しく切り出されたラインが同じ実行で昇格されることはありません。

昇格に失敗すると切り出しが保留されます。最新の stable より上の最も高い release-candidate ラインのみが選択されるため、失敗した状態で次のラインを切り出すと、出荷されなかったラインが取り残されてしまいます。翌週の月曜日に、保留されていたラインが自動的に再試行されます。

## チャネルの固定 {#pinning-a-channel}

デプロイマニフェスト、Helm の値、または Docker Compose ファイルで、必要な特定のタグを固定してください。Helm チャートを使用する場合の例:

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

`:latest` は `ghcr.io/tuist/tuist` と `ghcr.io/tuist/kura` の両方で最新の stable を追跡し、月曜日の昇格時のみ移動します。`:latest` を固定すると、タグを更新せずに週次の stable サイクルを利用できます。特定のバージョンを固定すると、アップグレードのタイミングを完全に制御できます。

## 推奨戦略 {#recommended-strategy}

チャネルが存在するのは、「最新の修正を取得する」ことと「最新の機能を取得する」ことを分離できるようにするためです。安全で手間のかからないデフォルトは次のとおりです。

1. **本番環境を stable のマイナーラインに固定する**（例: `ghcr.io/tuist/tuist:1.351`）。そのラインはバックポートされた修正のみを受け取り、新機能は含まれないため、日常のアップグレードは低リスクのままです。次のマイナーバージョンを採用する準備ができたら、固定バージョンを更新してください。
2. **ステージング環境を canary または特定の release-candidate タグで実行する**。ステージングにより、ユーザーに影響するはずだった回帰を検出でき、`main` に近いほど早期に発見できます。現在の release-candidate ラインでのステージング環境は良い中間地点です。翌週の月曜日に stable となる正確なバイトを soak できます。
3. **実際にリリースされた内容については、[サーバーのチェンジログ](/changelog) を確認してください**。stable の昇格ごとに、マージされたプルリクエストの一覧とともにアナウンスされます。

新機能が stable になった時点で本番環境に自動的にロールアウトさせたい場合は、本番環境を `:latest` に維持してください。タグは毎週月曜日の朝に進むため、それに合わせてデプロイの時間帯を計画してください。

## バックポート {#backports}

常に2つの stable サーバー（および Kura）ラインが積極的にメンテナンスされています。現在のラインは回帰とセキュリティ修正をバックポートプルリクエストとして受け入れ、前のラインは重要かつセキュリティ修正のみを受け入れます。古いラインにはバックポートされません。修正を受け取るには、メンテナンスされているラインにアップグレードしてください。新しいラインが stable に昇格すると、それまで current だったラインが「previous」になり、「previous」だったラインはバックポートの受け入れを停止します。

バックポートは必要に応じて `X.Y.(Z+1)` パッチリリースとして切り出されます。`:latest` を移動させることはありません。
