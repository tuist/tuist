---
{
  "title": "Gradle の不安定なテスト",
  "titleTemplate": ":title · 不安定なテスト · テストインサイト · 機能 · ガイド · Tuist",
  "description": "Tuist を使用して、Gradle プロジェクトの不安定なテストを検出、管理、隔離します。"
}
---
# Gradle の不安定なテスト {#gradle-flaky-tests}

> [!IMPORTANT]
> **要件**
>
> - <.localized_link href="/guides/features/test-insights/gradle">Gradle テストインサイト</.localized_link> が設定されていること。

<!-- @snippet: ./_intro -->

![不安定なテストのページ](/images/guides/features/test-insights/flaky-tests-page.png)

## 不安定な検出の仕組み {#how-it-works}

Tuist は次の 2 つの方法で不安定なテストを検出します。

### テストの再試行 {#test-retries}

再試行機能を使ってテストを実行すると、Tuist は各試行の結果を分析します。一部の試行で失敗し、他の試行で成功するテストは不安定としてマークされます。

[Test Retry プラグイン](https://github.com/gradle/test-retry-gradle-plugin) や同様の仕組みを使って失敗したテストを再実行できます。Tuist は、一部の試行で成功し他の試行で失敗するテストを検出します。

プラグインを `build.gradle.kts` に追加してください。

```kotlin
plugins {
    id("org.gradle.test-retry") version "1.6.2"
}

tasks.test {
    retry {
        maxRetries = 3
        maxFailures = 5
        failOnPassedAfterRetry = false
    }
}
```

![不安定なテストケースの詳細](/images/guides/features/test-insights/flaky-test-case-detail.png)

### クロスラン検出 {#cross-run-detection}

テストの再試行がなくても、Tuist は同じコミットと同じ Gradle プロジェクトに対する異なる CI ランの結果を比較することで不安定なテストを検出できます。ある CI ランでは成功し、同じコミットとプロジェクトの別のランでは失敗する場合、その失敗した実行は不安定としてマークされます。

Gradle プロジェクトは比較キーの一部です。同じテストでもプロジェクトによって決定的に異なる動作をする可能性があるためです。たとえば、異なる依存関係でコンパイルされた共有テストクラスや、異なるモジュールフィクスチャ上で実行される場合などです。異なる Gradle プロジェクトで同じコミットの 2 回の実行は別の実行バリアントとして扱われ、互いを不安定としてフラグ付けしません。

これは、再試行で捕捉できるほど一貫して失敗しないものの、依然として断続的な CI 障害を引き起こす不安定なテストを検出するのに特に役立ちます。

<!-- @snippet: ./_managing -->

## 不安定なテストの隔離 {#quarantining}

<!-- @snippet: ./_quarantine-intro -->

隔離されたテストは次の 2 つのモードのいずれかになります。

- **Muted**: テストは引き続き実行されますが、プラグインが `ignoreFailures = true` を設定し、隔離されていない失敗の場合のみビルドを再失敗させます。失敗は依然として不安定テスト検出器に送られるため、ビルドを壊さずにテストを監視し続けられます。 actively 調査中のテストにこのモードを選択してください。
- **Skipped**: プラグインが Gradle の `excludeTestsMatching` を使ってテストを除外するため、テストはまったく開始されません。新しい結果は生成されず、再度有効にするまで不安定テストダッシュボードから除外されます。テストが壊れている、遅い、またはあまりにも持続的に不安定で実行しても CI 時間を無駄にする場合にこのモードを選択してください。

<!-- @snippet: ./_quarantined-passing -->

### 隔離の有効化 {#enabling-quarantine}

隔離は **CI で自動的に有効** になり（`CI` 環境変数が設定されている場合）、ローカルビルドでは無効になります。プラグインは各テストタスクの前に Tuist サーバーから隔離されたテストのリストを取得します。ミュートされたテストは通常通り実行され、失敗はマスクされます。スキップされたテストはフィルターで除外されます。

これを `settings.gradle.kts` で明示的に制御できます。

```kotlin
tuist {
    testQuarantine {
        enabled = true  // or false to disable
    }
}
```

`enabled` が設定されていない場合、自動検出がデフォルトになります。CI では有効、ローカルでは無効です。

## 新しいテストのストレステスト {#stress-testing-new-tests}

<!-- @snippet: ./_stress-intro -->

テストケースは、プロジェクトのデフォルトブランチで過去 90 日間に CI で実行されていない場合、またはその後そのブランチに取り込まれたコミットで実行されていない場合に新規とみなされます。マージキューがある場合、キューが実行したテストケースはキューのコミットが取り込まれた時点で認識され、キューがそれを削除した場合は新規のままとなります。コミットは、Tuist が CI で収集する <.localized_link href="/guides/features/test-insights/gradle#git-history">Git ヒストリー</.localized_link> を通じて照合されます。

<!-- @snippet: ./_stress-modes -->

`settings.gradle.kts` で宣言するか、`TUIST_TEST_STRESS_NEW_TESTS` を設定して CI レーンごとにモードを変更できます。

```kotlin
tuist {
    stressNewTests {
        mode = "report" // or "enforce"
    }
}
```

隔離とは異なり、このゲートには CI を考慮したデフォルトがありません。`mode` が設定されていない場合、どこでも実行されません。

<!-- @snippet: ./_stress-reruns -->

各再実行はその 1 つのテストケースに絞り込まれたネストされた Gradle ビルドであり、すべての再実行で新しいテスト JVM が用意されます。

<!-- @snippet: ./_stress-skipped -->

<!-- @snippet: ./_slack -->

<!-- @snippet: ./_querying -->
