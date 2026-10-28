---
{
  "title": "Rust Flaky Tests",
  "titleTemplate": ":title · Flaky Tests · Test Insights · Features · Guides · Tuist",
  "description": "Detect and investigate flaky Cargo tests using CI history."
}
---
# Rust の不安定なテスト {#rust-flaky-tests}

Tuist は、Cargo テスト結果の一貫性の欠如を検出し、**Tests → Flaky Tests** でその調査を支援します。

> [!IMPORTANT] Requirements
> - <.localized_link href="/guides/features/test-insights/rust">Rust Test Insights</.localized_link> を設定してください。

## 不安定な検出の仕組み {#how-it-works}

Tuist は同じコミットに対する CI 実行を比較します。ある実行では成功し、別の実行では失敗するテストは、不安定（flaky）としてマークされる可能性があります。

通常のコマンドを使用して各実行を報告します：

```sh
tuist cargo test --workspace
```

Cargo は失敗したテストを自動的に再試行しません。同じコミットで CI ジョブを再実行することで、クロスラン検出のための別の結果が得られます。

## 不安定なテストの管理 {#managing-flaky-tests}

### 自動クリア

検出と復旧は、プロジェクトの「Flaky test detection」オートメーションを通じて実行されます。デフォルトでは、再トリガーがない場合、不安定フラグは 14 日後にクリアされます。**Settings → Automations** で復旧ウィンドウとアクションを編集できます。

### 手動管理

**Tests → Flaky Tests** を開いてテストの履歴を確認します。詳細ページから、手動で不安定としてマークしたり、マークを解除したりできます。

## 隔離とストレステスト {#quarantine}

Cargo 統合はまだ隔離を適用しません：ダッシュボードでミュートまたはスキップされたテストも引き続き実行され、その失敗は結果に影響します。新しいテストのストレステストも行いません。調査中に失敗するテストを繰り返すには、Cargo テストフィルターを使用します：

```sh
tuist cargo test -p store rejects_invalid_token
```

## Slack 通知 {#notifications}

テストが不安定になったときにチームに通知するために、<.localized_link href="/guides/integrations/slack#flaky-test-alerts">Slack flaky test alerts</.localized_link> を設定してください。
