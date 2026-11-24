---
{
  "title": "リリースチャンネル",
  "titleTemplate": ":title | セルフホスティング | サーバー | ガイド | Tuist",
  "description": "TuistがサーバーおよびKuraのDockerイメージをカナリー、リリース候補、安定版の各チャンネルでどのように配布するか、そして信頼できるラインにデプロイメントを固定する方法について説明します。"
}
---

# リリースチャンネル {#release-channels}

TuistサーバーとKuraキャッシュサーバーは、安定性の保証が異なる3つのGHCRイメージチャンネルを通じて提供されます。推奨されるインストールは**stable**で、週に1回更新されます。`main`への機能マージごとに進むわけではないため、アップグレードしても無関係な変更をまとめて取り込む必要がありません。早期採用者は**canary**でコミットごとのビルドを実行でき、**release candidate**チャンネルでは、安定版になる前のラインを事前に検証できます。

サーバーとKuraは同じ週次リリースサイクルに従い、どちらも<.localized_link href="/cli/release/channels">Tuist CLIのリリーススケジュール</.localized_link>と連動して動作します。

## 現在のリリース {#live-release-status}

各コンポーネントの現在のリリースは以下に表示されます。パッチやバックポートを含む今後のリリース窓および最近のリリースについては、<.localized_link href="/guides/server/self-host/release/calendar">リリースカレンダー</.localized_link>をご覧ください。

<.release_status status={@release_status} components="server,kura" calendar_path="/guides/server/self-host/release/calendar" locale={@locale} />

## チャンネル {#the-channels}

| チャンネル | バージョン形式 | 頻度 | `:latest`を追従するか? |
| --- | --- | --- | --- |
| Canary | `X.Y.0-canary.N`（例: `1.351.0-canary.5`） | `main`へのすべてのコミット | いいえ、明示的なオプトインが必要 |
| Release candidate | `X.Y.0-rc.N`（例: `1.351.0-rc.1`） | 毎週月曜日に`main`から切り出され、約1週間検証 | いいえ、明示的なオプトインが必要 |
| Stable | `X.Y.Z`（例: `1.350.2`、`1.351.0`） | クリーンな検証後、毎週月曜日に昇格 | **はい** |

Canaryおよびrelease candidateビルドはGitHubプレリリースとして公開されます。`:latest`解決時にプレリリースを除外するツールはこれらをスキップするため、明示的に指定しない限りこれらのバージョンに到達することはありません。

### Canary {#canary}

`main`へのすべてのコミットに対してcanaryイメージが公開されます。Canaryは常に**次の未リリースマイナーバージョン**を表します。リリース用にラインが切り出されると、`main`は次のマイナーバージョンに進みます（例: `1.350.0-canary.42`から`1.351.0-canary.1`へ）。Canaryは、本番環境をミラーリングし、回帰に対する最も早期のシグナルを提供するステージング環境や、報告した修正が安定版に到達する前に期待通りに動作するかを確認する場合に適したチャンネルです。

```
ghcr.io/tuist/tuist:1.351.0-canary.5
ghcr.io/tuist/kura:0.55.0-canary.5
```

### Release candidate {#release-candidate}

マイナーバージョンのリリース準備が整うと、そのラインは保護された`releases/server-<major>.<minor>.x`（または`releases/kura-<major>.<minor>.x`）ブランチに固定され、`X.Y.0-rc.1`として公開されます。このラインは機能追加が凍結されており、重要な修正と回帰のみが cherry-pick され、受け入れられた修正ごとにリリース候補が迭代します（`-rc.2`、`-rc.3`など）。検証期間が正常に終了すると、翌週の月曜日にそのラインはstableに昇格します。

```
ghcr.io/tuist/tuist:1.351.0-rc.1
ghcr.io/tuist/kura:0.55.0-rc.1
```

### Stable {#stable}

Stableは推奨されるチャンネルであり、すべてのドキュメントが参照するチャンネルです。stableマイナー（`X.Y.0`）は、release candidateが正常に検証された後にのみ公開され、新機能が`main`にマージされても進み**ません**。stableライン上のパッチ（`X.Y.1`、`X.Y.2`など）にはバックポートされた修正のみが含まれ、新機能は決して含まれません。`:latest`はstableへの昇格時だけ移動します。

```
ghcr.io/tuist/tuist:1.351.0
ghcr.io/tuist/kura:0.55.0
ghcr.io/tuist/tuist:latest
ghcr.io/tuist/kura:latest
```

## 月曜日のリリース列車 {#the-monday-train}

毎週月曜日の06:00 UTCに、3つのコンポーネントのリリース列車が連動して実行されます。

1. **06:00 UTC** — 昇格ジョブが実行されます。各ジョブは、まだstableになっていない最新のrelease candidateライン（通常は前週の月曜日に切り出されたライン）を昇格させ、該当するラインがない場合は何もしません。
2. **各昇格が完了した後** — release candidateジョブが`main`から次のラインを切り出すため、 freshly cut されたラインが同じ実行で昇格されることはありません。

昇格に失敗すると切り出しが保留されます。最新のstableより上位のrelease candidateラインのうち最も高いものだけが選択されるため、失敗の上に次のラインを切り出すと、リリースされなかったラインが孤立してしまいます。翌週の月曜日に、保留されていたラインが自動的に再試行されます。

## チャンネルのピン留め {#pinning-a-channel}

デプロイマニフェスト、Helm values、またはDocker Composeファイルで、必要な特定のタグをピン留めしてください。Helmチャートを使用する場合の例:

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

`:latest`は`ghcr.io/tuist/tuist`と`ghcr.io/tuist/kura`の両方で最新のstableを追跡し、月曜日の昇格時だけ移動します。`:latest`をピン留めすると、タグを更新せずに週次stableサイクルを利用できます。特定のバージョンをピン留めすると、アップグレード時期を完全に制御できます。

## 推奨戦略 {#recommended-strategy}

チャンネルが存在するのは、「最新の修正を取得する」ことと「最新の機能を取得する」ことを分離できるようにするためです。安全で手間のかからないデフォルトは以下の通りです。

1. **本番環境をstableマイナーラインにピン留めする**（例: `ghcr.io/tuist/tuist:1.351`）。このラインはバックポートされた修正のみを受け取り、新機能は決して含まれないため、日常のアップグレードは低リスクのままです。次のマイナーバージョンを採用する準備ができたら、ピン留めバージョンを更新してください。
2. **ステージング環境をcanary、または特定のrelease candidateタグで実行する**。ステージング環境は、ユーザーに影響する可能性のある回帰を検出します。`main`に近いほど、早期に発見できます。現在のrelease candidateラインでのステージング環境は良い中間策です。来週月曜日にstableとなる正確なバイトを事前に検証できます。
3. **実際にリリースされた内容については、[サーバーのチェンジログ](/changelog)を確認してください**。stableへの昇格はすべて、マージされたプルリクエストの一覧とともにここで発表されます。

新機能がstableになると自動的に本番環境にロールアウトされることを希望する場合は、本番環境を`:latest`のまま維持してください。ただし、タグは毎週月曜日の朝に進むため、それに応じてデプロイウィンドウを計画してください。

## バックポート {#backports}

常に2つのstableサーバー（およびKura）ラインがアクティブにメンテナンスされています。現在のラインは回帰問題とセキュリティ修正をバックポートプルリクエストとして受け取り、前のラインは重要な修正とセキュリティ修正のみを受け取ります。古いラインにはバックポートされません。修正を受け取るには、メンテナンスされているラインにアップグレードしてください。新しいラインがstableに昇格すると、それまでcurrentだったラインは「previous」になり、「previous」だったラインはバックポートの受け取りを停止します。

バックポートは必要に応じて`X.Y.(Z+1)`パッチリリースとして切り出されます。`:latest`を移動させることはありません。
