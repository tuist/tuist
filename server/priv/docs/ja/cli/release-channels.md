---
{
  "title": "リリースチャンネル",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Tuist が Canary、リリース候補、安定版の各チャンネルで CLI をどのように提供するか、そしてチームが信頼できるバージョンに固定する方法を説明します。"
}
---

# リリースチャネル {#release-channels}

Tuist CLI は、安定性の保証が異なる 3 つのチャネルを通じて提供されます。推奨されるインストールは **stable** で、更新頻度は低く抑えられています。新機能がマージされるたびにバージョンが進むわけではないため、アップグレード時に無関係な変更をまとめて受け入れる必要がありません。早期採用者は **canary** でコミットごとのビルドを実行でき、**release candidate** チャネルでは、チームが次のラインを stable に昇格する前に十分に検証できます。

## チャネル {#the-channels}

| チャネル | バージョン形式 | 更新頻度 | デフォルトで解決されるか？ |
| --- | --- | --- | --- |
| Canary | `X.Y.0-canary.N`（例: `4.201.0-canary.42`） | `main` へのすべてのコミット | いいえ — 明示的なオプトインが必要 |
| Release candidate | `X.Y.0-rc.N`（例: `4.200.0-rc.1`） | 毎週月曜日に `main` から切り出され、約 1 週間検証 | いいえ — 明示的なオプトインが必要 |
| Stable | `X.Y.Z`（例: `4.200.0`、`4.200.1`） | クリーンな検証後に毎週月曜日昇格 | **はい** |

Canary および release candidate のビルドはプレリリースとして公開されます。Mise や Homebrew などのツールは、`latest` の解決、最小限のインストール、またはラインのピン留めを行う際にプレリリースを除外するため、明示的に指定しない限りこれらのバージョンに到達することはありません。

### Canary {#canary}

`main` へのすべてのコミットが canary として公開されます。Canary は常に **次の未リリースのマイナーバージョン** を表します。リリース用にラインが切り出されると、`main` は次のマイナーバージョンに進みます（例: `4.200.0-canary.42` から `4.201.0-canary.1` へ）。Canary は、可能な限り早い段階でフィードバックを得たい早期採用者や、報告または貢献した修正が stable に到達する前に期待通りに動作することを確認したい場合に適したチャネルです。

### Release candidate {#release-candidate}

マイナーバージョンの出荷準備が整うと、そのラインは保護された `releases/<major>.<minor>.x` ブランチに固定され、`X.Y.0-rc.1` として公開されます。このラインは機能追加が凍結されており、重要な修正と回帰のみが cherry-pick され、受け入れられた修正ごとに RC がインクリメントされます（`-rc.2`、`-rc.3`、…）。検証期間が問題なく終了すると、そのラインは stable に昇格します。

### Stable {#stable}

Stable は推奨されるチャネルであり、すべてのドキュメントが参照するチャネルです。stable のマイナーバージョン（`X.Y.0`）は、release candidate が問題なく検証された場合にのみ公開され、新機能が `main` にマージされても **進みません**。stable ライン上のパッチ（`X.Y.1`、`X.Y.2`、…）にはバックポートされた修正のみが含まれ、新機能は含まれません。

## バージョンの選択 {#choosing-a-version}

[Mise](/en/guides/install-tuist) を使用する場合（推奨）:

```bash
mise use tuist@latest              # Latest stable (recommended)
mise use tuist@4.200               # Pin to a stable line; receives backported fixes only
mise use tuist@4.200.1             # Pin to an exact stable patch
mise use tuist@4.201.0-rc.1        # Opt into a release candidate to soak it
mise use tuist@4.201.0-canary.42   # Opt into a specific canary build
```

Homebrew を使用する場合、`brew install --formula tuist` は常に最新の stable をインストールします。プレリリースは formula 経由では配布されません。

## 推奨戦略 {#recommended-strategy}

1. **stable ラインにピン留めする**（例: `tuist@4.200`）。このラインはバックポートされた修正のみを受け取り、新機能は追加されないため、日常的なアップグレードのリスクを低く抑えられます。
2. **新機能を意図的に導入する。** 次のマイナーバージョンの準備ができたら、release candidate チャネルで検証し、その後ピン留めを新しい stable ラインに移行します。
3. **canary を試す**。可能な限り早い段階でフィードバックを得たい早期採用者は、重要度の低い環境で canary を試してください。

## サポートとバックポート {#support-and-backports}

常に 2 つの stable ラインが積極的にメンテナンスされています:

| ライン | 受け取る修正 |
| --- | --- |
| 現在（`X.Y.x`） | 回帰とセキュリティ修正 |
| 以前（`X.(Y-1).x`） | 重要な修正とセキュリティ修正のみ |
| それより古いバージョン | なし — メンテナンス中のラインにアップグレードしてください |

修正はまず `main`（canary）に取り込まれます。回帰とセキュリティ修正は現在の stable ラインにバックポートされ、以前のラインには重要な修正とセキュリティ修正のみが適用されます。その他のバグ修正はバックポートされず、次のマイナーバージョンで提供されます。新しいラインが stable に昇格すると、それまで current だったラインが「previous」になり、「previous」だったラインはバックポートの受け取りを停止します。

チャネルに関係なく、Tuist サーバーは過去 3 か月以内にリリースされた任意の CLI と[互換性](/en/cli/compatibility)を保ちます。そのため、その期間内にアップグレードする限り、stable ラインにピン留めしてもサポート対象外になることはありません。
