---
{
  "title": "Rust の不安定なテスト",
  "titleTemplate": ":title · 不安定なテスト · テストインサイト · 機能 · ガイド · Tuist",
  "description": "CI の履歴を使用して、不安定な Cargo テストを検出して調査します。"
}
---
# Rust の不安定なテスト {#rust-flaky-tests}

Tuist は Cargo テストの結果の不整合を検出し、**Tests → Flaky Tests** で調査を支援します。

> [!IMPORTANT]
> **要件**
>
> - <.localized_link href="/guides/features/test-insights/rust">Rust Test Insights</.localized_link> を設定してください。

## 不安定さの検出方法 {#how-it-works}

Tuist は同じコミットに対する CI 実行を比較します。ある実行では合格し別の実行では失敗するテストは、不安定としてマークできます。

各実行は通常のコマンドで報告します:

```sh
tuist cargo test --workspace
```

Cargo は失敗したテストを自動的に再試行しません。同じコミットで CI ジョブを再実行すると、クロスラン検出のための別の結果が得られます。

<!-- @snippet: ./_managing -->

## 不安定なテストの隔離 {#quarantining}

詳細ページからテストをミュートまたはスキップするか、**Settings → Automations** で隔離を設定します。次の `tuist cargo test` はプロジェクトの現在の隔離状態を取得します:

- **Muted** テストは実行され実際の結果を報告しますが、その失敗によってコマンドが失敗することはありません。他のテストの失敗、コンパイルエラー、クラッシュ、不完全な結果は通常どおり失敗となります。
- **Skipped** テストは実行から除外され、隔離されたスキップとして報告されます。マッチングにはパッケージ、ターゲット、Rust モジュールパス、およびテスト名が含まれるため、同名のテストも独立して扱われます。

ミュートは選択されたワークスペースのパッケージとフィーチャを維持し、ミュートされたターゲットが失敗しても選択されたすべてのターゲットを実行します。スキップによる隔離には単一のパッケージ選択が必要です。`tuist cargo test -p store` を使用し、複数パッケージのワークスペースコマンドは避けてください。Tuist は複数パッケージのスキップを拒否します。これはコマンドを狭めることで Cargo の統合された依存関係フィーチャが変化する可能性があるためです。

隔離は <.localized_link href="/guides/features/test-sharding/rust">sharded Cargo runs</.localized_link> にも適用されます。Tuist が状態を取得できない場合、警告を出して隔離なしで実行します。失敗は抑制されません。意図的に隔離なしで実行するには:

```sh
TUIST_TEST_SKIP_QUARANTINE=1 tuist cargo test --workspace
```

### 制限事項 {#limitations}

- 適用には標準の libtest ハーネスとキャプチャされたデフォルト出力が必要です。quiet、verbose、alternate-format、または出力をキャプチャしないコマンドでは、隔離を適用する必要がある場合に失敗します。
- ターゲットの帰属が曖昧な場合は、`-p <package>` で正確なワークスペースパッケージを選択してください。カスタムハーネス、パッケージ/ターゲット名のグロブ、未解決のパッケージ選択はサポートされていません。
- Doctest もミュートまたはスキップできますが、Rustdoc のテストフィルタリングはすべての可能な例の名前のペアを区別できません。ある例をスキップすると有効な別の例もスキップされる場合や、部分的な doctest 除外で `--exact` が使用されている場合、Tuist はスキップされた例を実行したり有効なテストを黙って省略したりするのではなく、診断情報とともに失敗します。調査中は上記のオーバーライドを使用してください。

## 新しいテストの負荷テスト {#stress-testing-new-tests}

Tuist は新しい Cargo テストの負荷テストを行いません。調査中に失敗するテストを繰り返すには、Cargo テストフィルタを使用します:

```sh
tuist cargo test -p store rejects_invalid_token
```

<!-- @snippet: ./_slack -->

<!-- @snippet: ./_querying -->
