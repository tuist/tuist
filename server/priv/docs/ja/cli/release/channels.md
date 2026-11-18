---
{
  "title": "リリースチャネル",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "TuistがCLIをカナリア、リリース候補、安定版の各チャネルでどのように提供するか、そしてチームが信頼できるラインに固定する方法について説明します。"
}
---

# リリースチャネル {#release-channels}

Tuist CLI は、異なる安定性保証を持つ 3 つのチャネルを通じて提供されます。推奨されるインストールは **stable** で、更新頻度は低く設定されています。機能がマージされるたびにバージョンが進むわけではないため、アップグレードしても無関係な変更をまとめて取り込む必要がありません。早期採用者は **canary** でコミットごとのビルドを実行でき、**release candidate** チャネルを使えば、チームは次のラインが stable になる前に試用できます。

## 現在のリリース {#live-release-status}

Stable への昇格は、毎週月曜日の 06:00 UTC にスケジュールされています。スケジュールされた昇格が成功すると、次のリリース候補が `main` から切り出され、後続の canary は次のマイナーバージョンに移行します。今後のウィンドウやパッチおよびバックポートを含む最近のリリースについては、<.localized_link href="/cli/release/calendar">リリースカレンダー</.localized_link> を参照してください。

<.release_status status={@release_status} components="cli" calendar_path="/cli/release/calendar" locale={@locale} />

## チャネル {#the-channels}

| チャネル | バージョン形式 | 頻度 | デフォルトで解決されるか？ |
| --- | --- | --- | --- |
| Canary | `X.Y.0-canary.N`（例：`4.201.0-canary.42`） | `main` へのすべてのコミット | いいえ - 明示的なオプトインが必要 |
| Release candidate | `X.Y.0-rc.N`（例：`4.200.0-rc.1`） | 毎週月曜日に `main` から切り出し、約 1 週間試用 | いいえ - 明示的なオプトインが必要 |
| Stable | `X.Y.Z`（例：`4.200.0`、`4.200.1`） | クリーンな試用期間の後、毎週月曜日に昇格 | **はい** |

Canary および release candidate のビルドはプレリリースとして公開されます。Mise や Homebrew などのツールは、`latest` の解決、単純なインストール、またはラインのピン留めを行う際にプレリリースを除外するため、明示的に指定しない限りこれらのバージョンに到達することはありません。

### Canary {#canary}

`main` へのすべてのコミットが canary として公開されます。Canary は常に **次の未リリースのマイナーバージョン** を表します。リリース用にラインが切り出されると、`main` は次のマイナーバージョンに進みます（例：`4.200.0-canary.42` から `4.201.0-canary.1` へ）。Canary は、可能な限り早いシグナルを求めている早期採用者や、報告または貢献した修正が stable に到達する前に期待通りに動作するかを確認したい場合に適したチャネルです。

### Release candidate {#release-candidate}

マイナーバージョンの出荷準備が整うと、そのラインは保護された `releases/<major>.<minor>.x` ブランチにフリーズされ、`X.Y.0-rc.1` として公開されます。このラインは機能フリーズされており、重要な修正と回帰のみが cherry-pick され、受け入れられた修正ごとに RC がインクリメントされます（`-rc.2`、`-rc.3`、…）。試用期間が正常に終了すると、そのラインは stable に昇格します。

### Stable {#stable}

Stable は推奨されるチャネルであり、すべてのドキュメントが指し示すチャネルです。Stable のマイナーバージョン（`X.Y.0`）は、リリース候補が正常に試用された後にのみ公開され、新機能が `main` にマージされても **進みません**。Stable ライン上のパッチ（`X.Y.1`、`X.Y.2`、…）にはバックポートされた修正のみが含まれ、新機能は含まれません。

## バージョンの選択 {#choosing-a-version}

<.localized_link href="/guides/install-tuist">Mise</.localized_link> を使用する場合（推奨）：

```bash
mise use tuist@latest              # Latest stable (recommended)
mise use tuist@4.200               # Pin to a stable line; receives backported fixes only
mise use tuist@4.200.1             # Pin to an exact stable patch
mise use tuist@4.201.0-rc.1        # Opt into a release candidate to soak it
mise use tuist@4.201.0-canary.42   # Opt into a specific canary build
```

Homebrew を使用する場合、`brew install --formula tuist` は常に最新の stable をインストールします。プレリリースは Formula を介して配布されません。

## 推奨戦略 {#recommended-strategy}

1. **Stable ラインにピン留めする**（例：`tuist@4.200`）。そのラインはバックポートされた修正のみを受け取り、新機能は追加されないため、日常のアップグレードは低リスクで済みます。
2. **新機能を意図的に導入する。** 次のマイナーバージョンの準備ができたら、release candidate チャネルで試用し、その後ピン留めを新しい stable ラインに移行します。
3. 可能な限り早いシグナルを求める早期採用者の場合は、重要度の低い環境で **canary を試す**。

## サポートとバックポート {#support-and-backports}

いつでも 2 つの stable ラインが積極的にメンテナンスされています：

| ライン | 対象 |
| --- | --- |
| 現在（`X.Y.x`） | 回帰とセキュリティ修正 |
| 以前（`X.(Y-1).x`） | 重要およびセキュリティ修正のみ |
| それより古いバージョン | なし — メンテナンス中のラインにアップグレードしてください |

修正はまず `main`（canary）に反映されます。回帰とセキュリティ修正は現在の stable ラインにバックポートされ、以前のラインには重要およびセキュリティ修正のみが適用されます。その他のバグ修正はバックポートされず、次のマイナーバージョンで提供されます。新しいラインが stable に昇格すると、それまで「現在」だったラインは「以前」になり、「以前」だったラインへのバックポートは停止します。

チャネルに関係なく、Tuist サーバーは過去 3 か月以内にリリースされたすべての CLI と <.localized_link href="/cli/compatibility">互換性</.localized_link> を維持するため、その期間内にアップグレードしていれば、stable ラインにピン留めしてもサポート対象外になることはありません。
