---
{
  "title": "生成されたXcodeプロジェクト",
  "titleTemplate": ":title · 不安定なテスト · テストインサイト · 機能 · ガイド · Tuist",
  "description": "Tuistで生成されたXcodeプロジェクトにおいて、不安定なテストを検出し、管理し、隔離します。"
}
---
# 生成されたXcodeプロジェクト {#generated-xcode-project-flaky-tests}

> [!IMPORTANT]
> **要件**
>
> - <.localized_link href="/guides/features/test-insights/xcode">Xcodeテストインサイト</.localized_link>が設定されていること（自動生成されたスキームには`tuist inspect test`ポストアクションが含まれています。カスタムスキームではこれを追加する必要があります）。

<!-- @snippet: ./_intro -->

![不安定なテストページ](/images/guides/features/test-insights/flaky-tests-page.png)

## 不安定なテストの検出方法 {#how-it-works}

Tuistは以下の2つの方法で不安定なテストを検出します：

### テストの再試行 {#test-retries}

再試行機能を使用してテストを実行すると、Tuistは各試行の結果を分析します。ある試行では失敗し、別の試行では成功するテストは、不安定としてマークされます。

`tuist test`を通じて`-retry-tests-on-failure`または`-test-iterations`を渡します：

```sh
tuist test MyScheme -- -retry-tests-on-failure -test-iterations 3
```

![不安定なテストケースの詳細](/images/guides/features/test-insights/flaky-test-case-detail.png)

<!-- @snippet: ./_xcode-cross-run -->

<!-- @snippet: ./_managing -->

## 不安定なテストの隔離 {#quarantining}

<!-- @snippet: ./_quarantine-intro -->

隔離されたテストは、次の2つのモードのいずれかになります：

- **ミュート**：テストは引き続き実行されますが、`tuist test`によって失敗がマスクされます。失敗情報は依然として不安定なテスト検出器に送られるため、ビルドを壊さずにテストを監視し続けることができます。積極的に調査中のテストにこのモードを選択してください。
- **スキップ**：xcodebuildは`-skip-testing <identifier>`を受け取るため、テストは開始されません。新しい結果は生成されず、再度有効にするまで不安定なテストダッシュボードから除外されます。テストが壊れている、遅い、またはあまりにも持続的に不安定で実行することがCI時間の無駄になる場合にこのモードを選択してください。

<!-- @snippet: ./_quarantined-passing -->

### テストの実行 {#running-tests}

`tuist test`は両方のモードを自動的に尊重します：

```sh
tuist test
```

スキップされたテストは`-skip-testing`としてxcodebuildに渡され、開始されることはありません。ミュートされたテストは通常通り実行されます。失敗した場合、その失敗は結果のビルドステータスでマスクされます。

隔離を完全に bypass し、ミュートおよびスキップされたテストを含むすべてを実行するには：

```sh
tuist test --skip-quarantine
```

## 新しいテストのストレステスト {#stress-testing-new-tests}

<!-- @snippet: ./_stress-intro -->

テストケースは、プロジェクトのデフォルトブランチで過去90日間にCIで実行されていない場合、またはその後そのブランチに取り込まれたコミットで実行されていない場合に新規とみなされます。マージキューを使用する場合、キューが実行したテストケースは、キューのコミットが取り込まれた時点で認識され、キューがそれを削除した場合でも新規のままとなります。コミットは、TuistがCIで収集する<.localized_link href="/guides/features/test-insights/xcode#git-history">Git履歴</.localized_link>を通じて照合されます。

<!-- @snippet: ./_stress-modes -->

どちらのモードでも、<.localized_link href="/guides/features/selective-testing/generated-xcode-project">選択的テスト</.localized_link>は、不安定な新しいテストケースを含むテストターゲットを次の実行でスキップしません。ターゲットは再度実行され、ゲートはすべての再試行に合格するまでテストケースを再度ストレステストします。

パススルー引数の前にこれを渡すか、`TUIST_TEST_STRESS_NEW_TESTS`を設定してCIレーンごとにモードを変更します：

```sh
tuist test --stress-new-tests report
```

<!-- @snippet: ./_stress-reruns -->

再試行は、最初のパスでビルドされたものを再利用します。

<!-- @snippet: ./_stress-skipped -->

<!-- @snippet: ./_slack -->

<!-- @snippet: ./_querying -->
