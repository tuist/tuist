---
{
  "title": "Gradle の不安定なテスト",
  "titleTemplate": ":title · 不安定なテスト · テストインサイト · 機能 · ガイド · Tuist",
  "description": "Tuist を使用して、Gradle プロジェクトの不安定なテストを検出、管理、隔離します。"
}
---
# Gradle の不安定なテスト {#gradle-flaky-tests}

> [!IMPORTANT]
> **必要条件**
>
> - <.localized_link href="/guides/features/test-insights/gradle">Gradle テストインサイト</.localized_link>が設定されていること。

<!-- @snippet: ./_intro -->

![不安定なテストのページ](/images/guides/features/test-insights/flaky-tests-page.png)

## 不安定なテストの検出方法 {#how-it-works}

Tuist は以下の 2 つの方法で不安定なテストを検出します。

### テストのリトライ {#test-retries}

リトライ機能を使ってテストを実行すると、Tuist は各試行の結果を分析します。一部の試行で失敗し、他の試行で成功するテストは不安定としてマークされます。

[Test Retry プラグイン](https://github.com/gradle/test-retry-gradle-plugin)や同様の仕組みを使って失敗したテストを再実行できます。Tuist は、一部の試行で成功し他の試行で失敗するテストを検出します。

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

テストのリトライを使わなくても、Tuist は同じコミットと同じ Gradle プロジェクトに対する異なる CI ランの結果を比較することで不安定なテストを検出できます。ある CI ランで成功し、同じコミットとプロジェクトの別のランで失敗した場合、その失敗した実行は不安定としてマークされます。

Gradle プロジェクトは比較キーの一部です。同じテストでもプロジェクトによって決定的に異なる振る舞いをすることがあるためです。たとえば、異なる依存関係でコンパイルされた共有テストクラスや、異なるモジュールフィクスチャで実行される場合などです。異なる Gradle プロジェクトで同じコミットを 2 回実行しても、それぞれ別の実行バリアントとして扱われ、互いに不安定としてフラグを立てません。

これは、リトライでは捕捉できないほど一貫性のない失敗を起こすものの、依然として断続的な CI 失敗を引き起こす不安定なテストを検出するのに特に役立ちます。

<!-- @snippet: ./_managing -->

## 不安定なテストの隔離 {#quarantining}

<!-- @snippet: ./_quarantine-intro -->

隔離されたテストは次の 2 つのモードのいずれかになります。

- **ミュート**: テストは引き続き実行されますが、プラグインが `ignoreFailures = true` を設定し、隔離されていない失敗が発生した場合のみビルドを再失敗させます。失敗情報は不安定テスト検出器に引き続き送られるため、ビルドを壊さずにテストを監視し続けられます。actively 調査中のテストにこのモードを選択してください。
- **スキップ**: プラグインが Gradle の `excludeTestsMatching` を使ってテストを除外するため、テストはまったく開始されません。新しい結果は生成されず、再度有効にするまで不安定テストダッシュボードから外れます。テストが壊れている、遅い、またはあまりにも持続的に不安定で実行することが CI 時間の無駄遣いになる場合にこのモードを選択してください。

<!-- @snippet: ./_quarantined-passing -->

### 隔離の有効化 {#enabling-quarantine}

隔離は **CI で自動的に有効**になり（`CI` 環境変数が設定されている場合）、ローカルビルドでは無効になります。プラグインは各テストタスクの前に Tuist サーバーから隔離されたテストのリストを取得します。ミュートされたテストは通常通り実行され、失敗はマスクされます。スキップされたテストは除外されます。

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

テストケースは、プロジェクトのデフォルトブランチで過去 90 日間に CI で実行されていない場合、またはその後そのブランチに取り込まれたコミットで実行されていない場合に新規とみなされます。マージキューを使用する場合、キューが実行したテストケースはキューのコミットが取り込まれると認識され、キューがそれを削除した場合は新規のままとなります。コミットのマッチングは、Tuist が CI で収集する <.localized_link href="/guides/features/test-insights/gradle#git-history">Git ヒストリー</.localized_link>を通じて行われます。

<!-- @snippet: ./_stress-modes -->

`settings.gradle.kts` で宣言するか、`TUIST_TEST_STRESS_NEW_TESTS` を設定して CI レーンごとにモードを変更できます。

```kotlin
tuist {
    stressNewTests {
        mode = "report" // or "enforce"
    }
}
```

隔離とは異なり、このゲートには CI を意識したデフォルト値がありません。`mode` が設定されていない場合、どこでも実行されません。

<!-- @snippet: ./_stress-reruns -->

各再実行はその 1 つのテストケースに絞り込まれたネストされた Gradle ビルドであり、すべての再実行で新しいテスト JVM が使用されます。

<!-- @snippet: ./_stress-skipped -->

<!-- @snippet: ./_slack -->

<!-- @snippet: ./_querying -->
