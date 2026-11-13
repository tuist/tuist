---
{
  "title": "Xcodeの不安定なテスト",
  "titleTemplate": ":title · 不安定なテスト · テストインサイト · 機能 · ガイド · Tuist",
  "description": "Tuistを使用して、Xcodeプロジェクト内の不安定なテストを検出、管理、隔離します。"
}
---
# Xcode の不安定なテスト {#xcode-flaky-tests}

> [!IMPORTANT]
> **要件**
>
> - <.localized_link href="/guides/features/test-insights/xcode">Xcode テストインサイト</.localized_link> が設定されていること。Tuist は、各テスト実行でアップロードされたテストインサイトのイベントから不安定なテストを検出します。

<!-- @snippet: ./_intro -->

![不安定なテストのページ](/images/guides/features/test-insights/flaky-tests-page.png)

## 不安定な検出の仕組み {#how-it-works}

Tuist は以下の 2 つの方法で不安定なテストを検出します。

### テストのリトライ {#test-retries}

リトライ機能を使ってテストを実行すると、Tuist は各試行の結果を分析します。一部の試行では失敗し、他の試行では成功するテストは、不安定としてマークされます。

`-retry-tests-on-failure` または `-test-iterations` を `tuist xcodebuild test` に渡します。

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -retry-tests-on-failure \
  -test-iterations 3
```

![不安定なテストケースの詳細](/images/guides/features/test-insights/flaky-test-case-detail.png)

<!-- @snippet: ./_xcode-cross-run -->

<!-- @snippet: ./_managing -->

## 不安定なテストの隔離 {#quarantining}

<!-- @snippet: ./_quarantine-intro -->

隔離されたテストは、次の 2 つのモードのいずれかになります。

- **ミュート**: テストは引き続き実行されますが、`tuist xcodebuild test` が失敗をマスクします。失敗は依然として不安定なテストの検出器にフィードされるため、ビルドを壊すことなくテストを監視し続けることができます。積極的に調査中のテストにはこれを選択してください。
- **スキップ**: xcodebuild は `-skip-testing <identifier>` を受け取るため、テストは開始されません。新しい結果は生成されず、再度有効にするまで不安定なテストのダッシュボードから除外されます。テストが壊れている場合、遅い場合、またはあまりにも持続的に不安定で実行することが CI の時間を無駄にする場合にこれを選択してください。

<!-- @snippet: ./_quarantined-passing -->

### テストの実行 {#running-tests}

`tuist xcodebuild test` は両方のモードを自動的に尊重するパススルーラッパーです。xcodebuild を呼び出すのと同じ方法で使用します。

```sh
tuist xcodebuild test -scheme MyScheme
```

スキップされたテストは `-skip-testing <identifier>` として xcodebuild の呼び出しに追加され、決して開始されません。ミュートされたテストは通常通り実行されます。失敗した場合、その失敗は結果のビルドステータスでマスクされます。

#### 隔離のバイパス {#bypassing-quarantine}

`tuist xcodebuild test` は `--skip-quarantine` を受け付け、ミュートおよびスキップされたテストを含めてすべてを実行します。

```sh
tuist xcodebuild test --skip-quarantine -scheme MyScheme
```

#### xcodebuild を直接呼び出す {#calling-xcodebuild-directly}

`tuist xcodebuild test` を経由できない場合は、`tuist test case list` を使用して隔離されたテストを `-skip-testing` 引数に自分で展開します。

```sh
xcodebuild test \
  -scheme MyScheme \
  $(tuist test case list --quarantined --skip-testing)
```

これは `tuist xcodebuild test` の外部での安全なデフォルトです。ミュートされたテストの失敗マスキングはそのコマンドを経由した場合のみ発生するため、両方のモードをスキップすることで誤った CI の失敗を回避できます。より細かい制御が必要な場合は、代わりに `tuist xcodebuild test` を経由してください。

## 新しいテストのストレステスト {#stress-testing-new-tests}

<!-- @snippet: ./_stress-intro -->

テストケースは、プロジェクトのデフォルトブランチで過去 90 日間 CI で実行されていない場合、またはそれ以降にそのブランチにマージされたコミットで実行されていない場合に新規とみなされます。マージキューを使用する場合、キューが実行したテストケースは、キューのコミットがマージされると認識され、キューがそれを削除した場合でも新規のままとなります。コミットは、Tuist が CI で収集する <.localized_link href="/guides/features/test-insights/xcode#git-history">Git の履歴</.localized_link> を通じて照合されます。

<!-- @snippet: ./_stress-modes -->

これをパススルー引数の前に渡すか、`TUIST_TEST_STRESS_NEW_TESTS` を設定して CI レーンごとにモードを変更します。

```sh
tuist xcodebuild test --stress-new-tests report -scheme MyScheme
```

<!-- @snippet: ./_stress-reruns -->

再実行では、最初のパスでビルドされたものが再利用されます。

<!-- @snippet: ./_stress-skipped -->

<!-- @snippet: ./_slack -->

<!-- @snippet: ./_querying -->
