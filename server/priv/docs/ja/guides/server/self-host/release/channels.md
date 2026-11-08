---
{
  "title": "リリースチャネル",
  "titleTemplate": ":title | セルフホスティング | サーバー | ガイド | Tuist",
  "description": "TuistがサーバーとKuraのDockerイメージをcanary、release candidate、stableの各チャネルでどのように提供するか、および信頼できるラインにデプロイメントを固定する方法について説明します。"
}
---

# リリースチャネル {#release-channels}

TuistサーバーとKuraキャッシュサーバーは、異なる安定性保証を持つ3つのGHCRイメージチャネルを通じて提供されます。推奨されるインストールは**stable**で、週に1回更新されます。`main`に機能がマージされるたびに進行するわけではないため、アップグレードしても無関係な変更の束を吸収する必要がなくなります。早期採用者は引き続き**canary**でコミットごとのビルドを実行でき、**release candidate**チャネルを使用すると、安定版になる前に今後のラインを十分に検証できます。

サーバーとKuraは同じ週次スケジュールで動作し、どちらも<.localized_link href="/cli/release/channels">Tuist CLIのリリーススケジュール</.localized_link>と連動して公開されます。

## 現在のリリース {#live-release-status}

各コンポーネントの現在のリリースを以下に示します。パッチやバックポートを含む今後のウィンドウと最近のリリースについては、<.localized_link href="/guides/server/self-host/release/calendar">リリースカレンダー</.localized_link>をご覧ください。

<.release_status status={@release_status} components="server,kura" calendar_path="/guides/server/self-host/release/calendar" locale={@locale} />

## チャネル {#the-channels}

| チャネル | バージョン形式 | 頻度 | `:latest`を更新するか？ |
| --- | --- | --- | --- |
| Canary | `X.Y.0-canary.N`（例：`1.351.0-canary.5`） | `main`へのすべてのコミット | いいえ、明示的なオプトインが必要 |
| Release candidate | `X.Y.0-rc.N`（例：`1.351.0-rc.1`） | 毎週月曜日に`main`からカットされ、約1週間検証 | いいえ、明示的なオプトインが必要 |
| Stable | `X.Y.Z`（例：`1.350.2`、`1.351.0`） | クリーンな検証後、毎週月曜日に昇格 | **はい** |

Canaryおよびrelease candidateビルドはGitHubプレリリースとして公開されます。`:latest`を解決する際にプレリリースを除外するツールはこれらをスキップするため、明示的に指定しない限りこれらのバージョンに到達することはありません。

### Canary {#canary}

`main`へのすべてのコミットに対してcanaryイメージが公開されます。Canaryは常に**次の未リリースマイナーバージョン**を表します。リリース用にラインがカットされると、`main`は次のマイナーバージョンに進みます（例えば、`1.350.0-canary.42`から`1.351.0-canary.1`へ）。Canaryは、本番環境をミラーリングし、回帰に対する最も早いシグナルを提供するステージング環境や、報告した修正が安定版に到達する前に期待通りに動作することを確認するのに適したチャネルです。

```
ghcr.io/tuist/tuist:1.351.0-canary.5
ghcr.io/tuist/kura:0.55.0-canary.5
```

### Release candidate {#release-candidate}

マイナーバージョンのリリース準備が整うと、そのラインは保護された`releases/server-<major>.<minor>.x`（または`releases/kura-<major>.<minor>.x`）ブランチに固定され、`X.Y.0-rc.1`として公開されます。このラインは機能追加が凍結されており、重要な修正と回帰のみが cherry-pick され、受け入れられた修正ごとにリリース候補が更新されます（`-rc.2`、`-rc.3`など）。検証期間が正常に終了すると、そのラインは翌週の月曜日にstableへ昇格します。

```
ghcr.io/tuist/tuist:1.351.0-rc.1
ghcr.io/tuist/kura:0.55.0-rc.1
```

### Stable {#stable}

Stableは推奨されるチャネルであり、すべてのドキュメントが指し示すものです。stableのマイナーバージョン（`X.Y.0`）は、release candidateがクリーンに検証された場合にのみ公開され、新機能が`main`にマージされても**進行しません**。stableライン上のパッチ（`X.Y.1`、`X.Y.2`など）にはバックポートされた修正のみが含まれ、新機能は決して含まれません。`:latest`はstableへの昇格時のみ更新されます。

```
ghcr.io/tuist/tuist:1.351.0
ghcr.io/tuist/kura:0.55.0
ghcr.io/tuist/tuist:latest
ghcr.io/tuist/kura:latest
```

## 月曜日のトレイン {#the-monday-train}

毎週月曜日の06:00 UTCに、3つのコンポーネントのリリーストレインが連動して実行されます。

1. **06:00 UTC** — 昇格ジョブが実行されます。各ジョブは、まだstableではない最新のrelease candidateライン（通常は前週の月曜日にカットされたライン）を昇格させ、該当するラインがない場合は何もしません。
2. **各昇格が完了した後** — release candidateジョブが`main`から次のラインをカットするため、新たにカットされたラインが同じ実行で昇格されることはありません。

昇格に失敗するとカットが保留されます。最新のstableより上位のrelease candidateラインのうち、最も高いもののみが選択されるため、失敗した状態で次のラインをカットすると、リリースされなかったラインが取り残されてしまいます。翌週の月曜日に、保留されていたラインが自動的に再試行されます。

## チャネルの固定 {#pinning-a-channel}

デプロイメントマニフェスト、Helm values、またはDocker Composeファイルで、必要な特定のタグを固定してください。Helmチャートを使用した例：

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

`ghcr.io/tuist/tuist`と`ghcr.io/tuist/kura`の両方における`:latest`は、最新のstableを追跡し、月曜日の昇格時にのみ更新されます。`:latest`を固定すると、タグを更新せずに週次のstableサイクルを利用でき、特定のバージョンを固定すると、アップグレードのタイミングを完全に制御できます。

## 推奨戦略 {#recommended-strategy}

チャネルが存在するのは、「最新の修正を取得する」ことと「最新の機能を取得する」ことを分離できるようにするためです。安全で手間のかからないデフォルトは以下の通りです。

1. **本番環境をstableのマイナーラインに固定する**（例：`ghcr.io/tuist/tuist:1.351`）。このラインはバックポートされた修正のみを受け取り、新機能は含まれないため、日常のアップグレードは低リスクのままです。次のマイナーバージョンを採用する準備ができたら、固定バージョンを更新してください。
2. **ステージング環境をcanary、または特定のrelease candidateタグで実行する**。ステージングにより、ユーザーに届いてしまう回帰を検出できます。`main`に近いほど、早期に発見できます。現在のrelease candidateラインでのステージング環境は良い中間地点です。来週月曜日にstableとなる正確なバイトを事前検証できます。
3. **実際にリリースされた内容については、[サーバーのチェンジログ](/changelog)を確認してください**。stableへの昇格はすべて、取り込まれたプルリクエストの一覧とともにここで発表されます。

新機能がstableになった時点で本番環境に自動的にロールアウトさせたい場合は、本番環境を`:latest`に設定したままにしてください。ただし、タグは毎週月曜日の朝に進むため、それに合わせてデプロイウィンドウを計画してください。

## バックポート {#backports}

常に2つのstableサーバー（およびKura）ラインが積極的にメンテナンスされています。現在のラインは回帰とセキュリティ修正をバックポートプルリクエストとして受け入れ、前のラインは重要な修正とセキュリティ修正のみを受け入れます。古いラインにはバックポートされません。修正を受け取るには、メンテナンスされているラインにアップグレードしてください。新しいラインがstableに昇格すると、それまでcurrentだったラインは「previous」になり、「previous」だったラインはバックポートの受け入れを停止します。

バックポートは必要に応じて`X.Y.(Z+1)`パッチリリースとしてカットされます。`:latest`を進めることはありません。
