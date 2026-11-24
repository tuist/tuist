---
{
  "title": "Xcodeの不安定なテスト",
  "titleTemplate": ":title · 不安定なテスト · テストインサイト · 機能 · ガイド · Tuist",
  "description": "Tuistを使用して、Xcodeプロジェクト内の不安定なテストを検出、管理、隔離します。"
}
---
# Xcode の不安定なテスト {#xcode-flaky-tests}

> [!IMPORTANT]
> **必要条件**
>
> - <.localized_link href="/guides/features/test-insights/xcode">Xcode テストインサイト</.localized_link> が構成されていること。Tuist は、各テスト実行でアップロードされるテストインサイトイベントから不安定なテストを検出します。

<!-- @snippet: ./_intro -->

![不安定なテストのページ](/images/guides/features/test-insights/flaky-tests-page.png)

## 不安定な検出の仕組み {#how-it-works}

Tuist は次の 2 つの方法で不安定なテストを検出します。

### テストの再試行 {#test-retries}

再試行機能を有効にしてテストを実行すると、Tuist は各試行の結果を分析します。一部の試行では失敗し、他の試行では成功するテストは、不安定としてマークされます。

`tuist xcodebuild test` を介して `-retry-tests-on-failure` または `-test-iterations` を渡します。

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

- **ミュート**: テストは引き続き実行されますが、`tuist xcodebuild test` によって失敗がマスクされます。失敗は依然として不安定なテストの検出器に送られるため、ビルドを壊すことなくテストを監視し続けることができます。 actively 調査中のテストにはこれを選択してください。
- **スキップ**: xcodebuild は `-skip-testing <identifier>` を受け取るため、テストは開始されません。新しい結果は生成されず、再度有効にするまで不安定なテストのダッシュボードから除外されます。テストが壊れている、遅い、またはあまりにも持続的に不安定で実行することが CI の時間を無駄にする場合にこれを選択してください。

<!-- @snippet: ./_quarantined-passing -->

### テストの実行 {#running-tests}

`tuist xcodebuild test` は両方のモードを自動的に尊重するパススルーラッパーです。xcodebuild を呼び出すのと同じ方法で使用します。

```sh
tuist xcodebuild test -scheme MyScheme
```

スキップされたテストは、xcodebuild の呼び出しに `-skip-testing <identifier>` として追加され、決して開始されません。ミュートされたテストは通常どおり実行されます。失敗した場合、その失敗は結果のビルドステータスでマスクされます。

#### 隔離のバイパス {#bypassing-quarantine}

`tuist xcodebuild test` は `--skip-quarantine` を受け入れ、ミュートおよびスキップされたテストを含むすべてを実行します。

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

これは `tuist xcodebuild test` の外部での安全なデフォルトです。ミュートされたテストの失敗マスクはそのコマンドを経由した場合のみ発生するため、両方のモードをスキップすることで誤った CI の失敗を回避できます。より細かな制御が必要な場合は、代わりに `tuist xcodebuild test` を経由してください。

## 新しいテストのストレステスト {#stress-testing-new-tests}

<!-- @snippet: ./_stress-intro -->

テストケースは、プロジェクトのデフォルトブランチで過去 90 日間に CI で実行されていない場合、またはそれ以降にそのブランチにマージされたコミット上で実行されていない場合に新規とみなされます。マージキューを使用する場合、キューが実行したテストケースは、キューのコミットがマージされると認識され、キューがそれを削除した場合でも新規のままとなります。コミットは、Tuist が CI で収集する <.localized_link href="/guides/features/test-insights/xcode#git-history">Git ヒストリー</.localized_link> を通じて照合されます。

<!-- @snippet: ./_stress-modes -->

パススルー引数の前に渡すか、`TUIST_TEST_STRESS_NEW_TESTS` を設定して CI レーンごとにモードを変更します。

```sh
tuist xcodebuild test --stress-new-tests report -scheme MyScheme
```

<!-- @snippet: ./_stress-reruns -->

再実行は、最初のパスでビルドされたものを再利用します。

<!-- @snippet: ./_stress-skipped -->

<!-- @snippet: ./_slack -->

<!-- @snippet: ./_querying -->
