---
{
  "title": "リリースチャンネル",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Tuist が CLI を Canary、Release Candidate、Stable の各チャンネルでどのように提供するか、そしてチームが信頼できるバージョンに固定する方法を説明します。"
}
---

# リリースチャンネル {#release-channels}

Tuist CLI は、安定性の保証が異なる3つのチャンネルを通じて提供されます。推奨されるインストールは **stable** で、更新頻度は低く設定されています。新機能がマージされるたびにバージョンが進むわけではないため、アップグレードしても無関係な変更を一括で取り込む必要がありません。早期導入者は **canary** でコミットごとのビルドを実行でき、**release candidate** チャンネルでは、チームが次のラインを stable に昇格させる前に十分に検証できます。

## チャンネル {#the-channels}

| チャンネル | バージョン形式 | 更新頻度 | デフォルトで解決されるか？ |
| --- | --- | --- | --- |
| Canary | `X.Y.0-canary.N`（例: `4.201.0-canary.42`） | `main` へのすべてのコミット | いいえ — 明示的なオプトインが必要 |
| Release candidate | `X.Y.0-rc.N`（例: `4.200.0-rc.1`） | 毎週月曜日に `main` から切り出され、約1週間検証 | いいえ — 明示的なオプトインが必要 |
| Stable | `X.Y.Z`（例: `4.200.0`、`4.200.1`） | クリーンな検証後、毎週月曜日に昇格 | **はい** |

Canary および release candidate のビルドはプレリリースとして公開されます。Mise や Homebrew などのツールは、`latest` の解決時、bare インストール時、またはラインのピン留め時にプレリリースを除外するため、明示的に指定しない限りこれらのバージョンに到達することはありません。

### Canary {#canary}

`main` へのすべてのコミットが canary を公開します。Canary は常に **次の未リリースのマイナーバージョン** を表します。リリース用にラインが切り出されると、`main` は次のマイナーバージョンに進みます（例: `4.200.0-canary.42` から `4.201.0-canary.1` へ）。Canary は、可能な限り早いフィードバックを求める早期導入者や、報告または貢献した修正が stable に到達する前に期待通りに動作するかを確認したい場合に適したチャンネルです。

### Release candidate {#release-candidate}

マイナーバージョンの出荷準備が整うと、そのラインは保護された `releases/<major>.<minor>.x` ブランチにフリーズされ、`X.Y.0-rc.1` として公開されます。このラインは機能追加が凍結されており、重要な修正と回帰修正のみが cherry-pick され、受け入れられた修正ごとに RC がインクリメントされます（`-rc.2`、`-rc.3`、…）。検証期間がクリーンに終了すると、そのラインは stable に昇格します。

### Stable {#stable}

Stable は推奨されるチャンネルであり、すべてのドキュメントが参照するバージョンです。stable のマイナーバージョン（`X.Y.0`）は、release candidate がクリーンに検証された場合にのみ公開され、新機能が `main` にマージされても **進みません**。stable ライン上のパッチ（`X.Y.1`、`X.Y.2`、…）にはバックポートされた修正のみが含まれ、新機能は決して含まれません。

## バージョンの選択 {#choosing-a-version}

<.localized_link href="/guides/install-tuist">Mise</.localized_link> を使用する場合（推奨）:

```bash
mise use tuist@latest              # Latest stable (recommended)
mise use tuist@4.200               # Pin to a stable line; receives backported fixes only
mise use tuist@4.200.1             # Pin to an exact stable patch
mise use tuist@4.201.0-rc.1        # Opt into a release candidate to soak it
mise use tuist@4.201.0-canary.42   # Opt into a specific canary build
```

Homebrew を使用する場合、`brew install --formula tuist` は常に最新の stable をインストールします。プレリリースは formula を通じて配布されません。

## 推奨戦略 {#recommended-strategy}

1. **stable ラインにピン留めする**（例: `tuist@4.200`）。このラインはバックポートされた修正のみを受け取り、新機能は追加されないため、日常のアップグレードは低リスクで済みます。
2. **新機能を意図的に導入する。** 次のマイナーバージョンの準備ができたら、release candidate チャンネルで検証し、その後ピン留めを新しい stable ラインに移行します。
3. 可能な限り早いフィードバックを求める早期導入者であれば、重要でない環境で **canary を試す**。

## サポートとバックポート {#support-and-backports}

いつでも2つの stable ラインが積極的にメンテナンスされています:

| ライン | 受け取る修正 |
| --- | --- |
| 現在（`X.Y.x`） | 回帰修正とセキュリティ修正 |
| 以前（`X.(Y-1).x`） | 重要な修正とセキュリティ修正のみ |
| より古いバージョン | なし — メンテナンス中のラインにアップグレードしてください |

修正はまず `main`（canary）に取り込まれます。回帰修正とセキュリティ修正は現在の stable ラインにバックポートされ、以前のラインには重要な修正とセキュリティ修正のみが適用されます。その他のバグ修正はバックポートされず、次のマイナーバージョンで提供されます。新しいラインが stable に昇格すると、それまで current だったラインは「previous」になり、「previous」だったラインはバックポートの受け取りを停止します。

チャンネルに関係なく、Tuist サーバーは過去3ヶ月以内にリリースされた任意の CLI と <.localized_link href="/cli/compatibility">互換性</.localized_link> を維持するため、その期間内にアップグレードしていれば、stable ラインにピン留めしてもサポート対象外になることはありません。
