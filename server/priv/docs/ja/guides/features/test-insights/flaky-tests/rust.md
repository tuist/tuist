---
{
  "title": "Rust Flaky Tests",
  "titleTemplate": ":title · Flaky Tests · Test Insights · Features · Guides · Tuist",
  "description": "Detect and investigate flaky Cargo tests using CI history."
}
---
# Rust の不安定なテスト {#rust-flaky-tests}

Tuist は一貫性のない Cargo テストの結果を検出し、**Tests → Flaky Tests** で調査するのを支援します。

> [!IMPORTANT] Requirements
> - <.localized_link href="/guides/features/test-insights/rust">Rust Test Insights</.localized_link> を設定してください。

## 不安定な検出の仕組み {#how-it-works}

Tuist は同じコミットに対する CI 実行を比較します。ある実行では成功し、別の実行では失敗するテストは不安定としてマークされる可能性があります。

通常のコマンドを使用して各実行を報告します:

```sh
tuist cargo test --workspace
```

Cargo は失敗したテストを自動的に再試行しません。同じコミットで CI ジョブを再実行することで、クロスラン検出のための別の結果が得られます。

## 不安定なテストの管理 {#managing-flaky-tests}

### 自動クリア

検出と回復はプロジェクトの「Flaky test detection」オートメーションを通じて実行されます。デフォルトでは、再トリガーがない場合、不安定フラグは 14 日後にクリアされます。**Settings → Automations** で回復期間とアクションを編集できます。

### 手動管理

**Tests → Flaky Tests** を開いてテストの履歴を確認します。詳細ページから手動で不安定としてマークしたり、マークを解除したりできます。

## 隔離とストレステスト {#quarantine}

詳細ページからテストをミュートまたはスキップするか、**Settings → Automations** で隔離を設定します。次の `tuist cargo test` はプロジェクトの現在の隔離状態を取得します:

- **Muted** テストは引き続き実行され、実際の結果を報告しますが、その失敗によってコマンドが失敗することはありません。他のテストの失敗、コンパイルエラー、クラッシュ、不完全な結果は通常通り失敗します。
- **Skipped** テストは実行から除外され、隔離されたスキップとして報告されます。マッチングにはパッケージ、ターゲット、Rust モジュールパス、およびテスト名が含まれるため、同名のテストは独立したままです。

ミュートは選択されたワークスペースのパッケージと機能を保持し、ミュートされたターゲットが失敗しても、選択されたすべてのターゲットを実行します。スキップ隔離には 1 つの選択されたパッケージが必要です: マルチパッケージのワークスペースコマンドではなく `tuist cargo test -p store` を使用してください。Tuist はマルチパッケージのスキップを拒否します。これは、コマンドを狭めることで Cargo の統合された依存関係の機能が変更される可能性があるためです。

隔離は <.localized_link href="/guides/features/test-sharding/rust">sharded Cargo runs</.localized_link> にも適用されます。Tuist が状態を取得できない場合、警告を表示して隔離なしで実行します。失敗は抑制されません。意図的に隔離なしで実行するには:

```sh
TUIST_TEST_SKIP_QUARANTINE=1 tuist cargo test --workspace
```

強制には標準の libtest ハーネスとキャプチャされたデフォルト出力が必要です。quiet、verbose、alternate-format、またはキャプチャされていない出力を持つコマンドは、隔離を適用する必要がある場合に失敗します。ターゲットの帰属が曖昧な場合は、`-p <package>` で正確なワークスペースパッケージを選択してください。カスタムハーネス、パッケージ/ターゲット名のグロブ、および解決されていないパッケージの選択はサポートされていません。Doctests もミュートまたはスキップできますが、Rustdoc のテストフィルタリングはすべての可能な例の名前のペアを区別できません。例をスキップすると有効な例もスキップされる場合、または部分的な doctest の除外が `--exact` を使用する場合、Tuist はスキップされた例を実行したり、有効なテストを黙って省略したりするのではなく、診断情報とともに失敗します。調査中は上記のオーバーライドを使用してください。

Tuist は新しい Cargo テストのストレステストを行いません。調査中に失敗するテストを繰り返すには、Cargo テストフィルタを使用します:

```sh
tuist cargo test -p store rejects_invalid_token
```

## Slack 通知 {#notifications}

テストが不安定になったときにチームに通知するために、<.localized_link href="/guides/integrations/slack#flaky-test-alerts">Slack flaky test alerts</.localized_link> を設定してください。
