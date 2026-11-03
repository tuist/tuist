---
{
  "title": "リリースチャンネル",
  "titleTemplate": ":title | セルフホスティング | サーバー | ガイド | Tuist",
  "description": "Tuist が Canary、リリース候補版、安定版の各チャンネルでサーバーおよび Kura の Docker イメージをどのように提供するか、そして信頼できるバージョンにデプロイメントを固定する方法について説明します。"
}
---

# リリースチャンネル {#release-channels}

Tuist サーバーと Kura キャッシュサーバーは、異なる安定性保証を持つ 3 つの GHCR イメージチャンネルを通じて提供されます。推奨されるインストールは **stable** で、週に 1 回更新されます。`main` に機能がマージされるたびに進むわけではないため、アップグレードしても無関係な変更をまとめて取り込む必要がなくなります。早期採用者は **canary** でコミットごとのビルドを実行でき、**release candidate** チャンネルを使えば、次のラインが stable になる前に試用できます。

サーバーと Kura は同じ週次リリースサイクルに従い、どちらも [Tuist CLI のリリーススケジュール](/en/cli/release-channels) と連動して動作します。

## チャンネル {#the-channels}

| チャンネル | バージョン形式 | 更新頻度 | `:latest` を移動するか？ |
| --- | --- | --- | --- |
| Canary | `X.Y.0-canary.N`（例: `1.351.0-canary.5`） | `main` へのすべてのコミット | いいえ、明示的なオプトインが必要 |
| Release candidate | `X.Y.0-rc.N`（例: `1.351.0-rc.1`） | 毎週月曜日に `main` から切り出され、約 1 週間試用 | いいえ、明示的なオプトインが必要 |
| Stable | `X.Y.Z`（例: `1.350.2`、`1.351.0`） | 正常な試用期間を経て、毎週月曜日に昇格 | **はい** |

Canary および release-candidate ビルドは GitHub のプレリリースとして公開されます。`:latest` の解決時にプレリリースを除外するツールはこれらをスキップするため、明示的に指定しない限りこれらのバージョンに到達することはありません。

### Canary {#canary}

`main` へのすべてのコミットで canary イメージが公開されます。Canary は常に **次の未リリースのマイナーバージョン** を表します。リリース用にラインが切り出されると、`main` は次のマイナーバージョンに進みます（例: `1.350.0-canary.42` から `1.351.0-canary.1` へ）。Canary は、本番環境をミラーリングし、回帰に対する最も早いシグナルを提供するステージング環境や、報告した修正が stable に到達する前に期待通りに動作することを確認する場合に適したチャンネルです。

```
ghcr.io/tuist/tuist:1.351.0-canary.5
ghcr.io/tuist/kura:0.55.0-canary.5
```

### Release candidate {#release-candidate}

マイナーバージョンのリリース準備が整うと、そのラインは保護された `releases/server-<major>.<minor>.x`（または `releases/kura-<major>.<minor>.x`）ブランチに凍結され、`X.Y.0-rc.1` として公開されます。このラインは機能追加が凍結されており、重要な修正と回帰のみが cherry-pick され、受け入れられた修正ごとに release candidate が更新されます（`-rc.2`、`-rc.3` など）。試用期間が正常に終了すると、そのラインは翌週の月曜日に stable へ昇格します。

```
ghcr.io/tuist/tuist:1.351.0-rc.1
ghcr.io/tuist/kura:0.55.0-rc.1
```

### Stable {#stable}

Stable は推奨されるチャンネルであり、すべてのドキュメントが指し示すものです。stable のマイナーバージョン（`X.Y.0`）は、release candidate が正常に試用された場合にのみ公開され、新機能が `main` にマージされても **進みません**。stable ライン上のパッチ（`X.Y.1`、`X.Y.2` など）にはバックポートされた修正のみが含まれ、新機能は含まれません。`:latest` は stable への昇格時에만移動します。

```
ghcr.io/tuist/tuist:1.351.0
ghcr.io/tuist/kura:0.55.0
ghcr.io/tuist/tuist:latest
ghcr.io/tuist/kura:latest
```

## 月曜日のリリース列車 {#the-monday-train}

毎週月曜日の 06:00 UTC に、3 つのコンポーネントのリリース列車が連動して実行されます。

1. **06:00 UTC** — 昇格ジョブが実行されます。各ジョブは、まだ stable ではない最新の release-candidate ライン（通常は前週の月曜日に切り出されたライン）を昇格させ、該当するラインがない場合は何もしません。
2. **各昇格が完了した後** — release-candidate ジョブが `main` から次のラインを切り出すため、 freshly cut されたラインは同じ実行中で昇格されることはありません。

昇格に失敗すると切り出しが保留されます。最新の stable より上の最も高い release-candidate ラインのみが選択されるため、失敗の上に次のラインを切り出すと、リリースされなかったラインが行き場を失います。翌週の月曜日に、保留されていたラインが自動的に再試行されます。

## チャンネルの固定 {#pinning-a-channel}

デプロイマニフェスト、Helm values、または Docker Compose ファイルで、希望する特定のタグを固定してください。Helm チャートを使用する場合の例:

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

`:latest` は `ghcr.io/tuist/tuist` と `ghcr.io/tuist/kura` の両方で最新の stable を追跡し、月曜日の昇格時에만移動します。`:latest` を固定すると、タグを更新せずに週次の stable 更新リズムを得られます。特定のバージョンを固定すると、アップグレードのタイミングを完全に制御できます。

## 推奨戦略 {#recommended-strategy}

チャンネルが存在するのは、「最新の修正を取得する」ことと「最新の機能を取得する」ことを分離できるようにするためです。安全で手間のかからないデフォルトは次のとおりです。

1. **本番環境を stable のマイナーラインに固定する**（例: `ghcr.io/tuist/tuist:1.351`）。このラインはバックポートされた修正のみを受け取り、新機能は含まれないため、日常のアップグレードは低リスクのままです。次のマイナーバージョンを採用する準備ができたら、固定バージョンを更新してください。
2. **ステージング環境を canary または特定の release-candidate タグで実行する。** ステージング環境は、 otherwise ユーザーに到達してしまう回帰を検出します。`main` に近いほど、早期に発見できます。現在の release-candidate ライン上でステージング環境を実行することは良い中間策です。翌週の月曜日に stable になる正確なバイトを試用できます。
3. **実際にリリースされた内容については、[Server changelog](/changelog) を確認してください。** stable への昇格ごとに、取り込まれたプルリクエストの一覧とともにアナウンスされます。

新機能が stable になった時点で本番環境に自動的にロールアウトさせたい場合は、本番環境を `:latest` に設定してください。タグは毎週月曜日の朝に進むため、それに合わせてデプロイの時間帯を計画してください。

## バックポート {#backports}

stable のサーバー（および Kura）ラインは常に2つがアクティブにメンテナンスされています。現在のラインは回帰とセキュリティ修正をバックポートプルリクエストとして受け取り、前のラインは重要かつセキュリティ関連の修正のみを受け取ります。古いラインにはバックポートされません。修正を受け取るには、メンテナンスされているラインにアップグレードしてください。新しいラインが stable に昇格すると、それまで「current」だったラインが「previous」になり、「previous」だったラインはバックポートの受け取りを停止します。

バックポートは必要に応じて `X.Y.(Z+1)` パッチリリースとして切り出されます。`:latest` を移動させることはありません。
