---
{
  "title": "Xcode Flaky Tests",
  "titleTemplate": ":title · Flaky Tests · Test Insights · Features · Guides · Tuist",
  "description": "Detect, manage, and quarantine flaky tests in Xcode projects with Tuist."
}
---
# Xcodeの不安定なテスト {#xcode-flaky-tests}

> [!WARNING]
> **要件**
>
> - <.localized_link href="/guides/features/test-insights/xcode">Xcodeテストインサイト</.localized_link> が構成されていること。Tuistは、各テスト実行によってアップロードされたテストインサイトイベントから不安定なテストを検出します。

不安定なテストとは、同じコードで複数回実行した際に異なる結果（合格または不合格）を生み出すテストのことです。これらはテストスイートへの信頼を損ない、誤った失敗の調査に開発者の時間を浪費させます。Tuistは不安定なテストを自動的に検出し、時間経過に伴う追跡をサポートします。

![不安定なテストページ](/images/guides/features/test-insights/flaky-tests-page.png)

## 不安定な検出の仕組み {#how-it-works}

Tuistは以下の2つの方法で不安定なテストを検出します：

### テスト再試行 {#test-retries}

再試行機能を使用してテストを実行すると、Tuistは各試行の結果を分析します。ある試行では失敗し、他の試行では成功するテストは、不安定としてマークされます。

`-retry-tests-on-failure` または `-test-iterations` を `tuist xcodebuild test` に渡します：

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -retry-tests-on-failure \
  -test-iterations 3
```

![不安定なテストケースの詳細](/images/guides/features/test-insights/flaky-test-case-detail.png)

### クロスラン検出 {#cross-run-detection}

テスト再試行を行わなくても、Tuistは同じコミット、スキーム、および報告された宛先（デバイス名、プラットフォーム、OSバージョン）における異なるCI実行間で結果を比較することで、不安定なテストを検出できます。一致するCI実行の1つでテストが合格し、別の実行で失敗した場合、失敗した実行は不安定としてマークされます。これは、どの結果が先に到着するかに関係なく機能します。

同じテストでも、スキームや宛先によって一貫して異なる動作をする場合があります。例えば、iOS 26では合格し、iOS 27では失敗しても、それは不安定性を示すものではありません。異なるスキーム、デバイス、プラットフォーム、またはOSバージョンからの結果は、互いに不安定としてフラグを立てません。

帰属可能な宛先がない結果は、既知の宛先を持つ結果とは別に、他の帰属不能な結果と比較されます。これには、宛先メタデータが欠落または不完全なレポートや、複数の異なる宛先を含むレポートが含まれます。個々のテスト結果をまだ宛先に帰属させることができないためです。このグループ内の環境間の差異は、依然として誤った不安定分類を生む可能性があります。再試行ベースの検出は引き続き適用されます。既存の履歴的な不安定分類は変更されません。

これは、再試行で捕捉できるほど一貫して失敗しないものの、依然として断続的なCI失敗を引き起こす不安定なテストを捕捉するのに特に役立ちます。

## 不安定なテストの管理 {#managing-flaky-tests}

### 自動クリア

検出とクリアは、プロジェクト上の **自動化アラート** を介して実行されます。すべてのプロジェクトには、デフォルトの「不安定なテスト検出」自動化が付与されており、その *トリガー* はテストを不安定としてマークし、*リカバリー* は、テストが設定されたリカバリーウィンドウ（デフォルト **14日**）の間再トリガーされずに経過するとフラグを解除します。**設定 → 自動化** でこれを編集し、リカバリーウィンドウを変更したり、リカバリーアクション（例：隔離解除も行う）を入れ替えたり、リカバリーを完全に無効にして、手動でクリアするまでテストが不安定としてマークされたままになるようにすることができます。

### 手動管理

テストケース詳細ページから、テストを手動で不安定としてマークしたり、そのマークを外したりすることもできます。これは以下の場合に便利です：
- 修正作業中に既知の不安定なテストを認識したい場合
- インフラストラクチャの問題によりテストが誤ってフラグ付けされた場合

## 不安定なテストの隔離 {#quarantining}

隔離は、不安定なテストを分離し、修正中にCIをブロックしないようにします。デフォルトでは **手動アクション** です — ダッシュボードのテストケース詳細ページから隔離、隔離解除、モードの切り替えを行います — が、**設定 → 自動化** の下の **自動化アラート** に組み込むこともでき、不安定性の閾値を超えるとテストが自動的にミュート（またはスキップ）され、回復すると隔離解除されます。手動か自動化かを問わず、すべての遷移はテストケースの監査ログに記録されます。

隔離されたテストは、以下の2つのモードのいずれかになります：

- **ミュート**：テストは引き続き実行されますが、`tuist xcodebuild test` が失敗をマスクします。失敗は依然として不安定テスト検出器に供給されるため、ビルドを壊さずにテストを監視し続けることができます。積極的に調査中のテストにこれを選択してください。
- **スキップ**：xcodebuildは `-skip-testing <identifier>` を受け取るため、テストは決して開始されません。新しい結果は生成されず、再度有効にするまで不安定テストダッシュボードから除外されます。テストが壊れている、遅い、またはあまりにも持続的に不安定で実行することがCI時間の無駄である場合にこれを選択してください。

### 隔離されたテストが合格として表示される理由 {#quarantined-passing}

- **ミュートされたテスト** は依然として実行されます。失敗したミュートテストは、テストケース実行上で **失敗** として記録され、不安定としてフラグ付けされます — テストごとのステータスは書き換えられません。上書きされるのは **全体のテスト実行** です：実行内のすべての失敗テストケースがミュートされている場合、実行全体は合格として報告されるため、ミュートされた失敗はCIを壊しません。
- **スキップされたテスト** はまったく実行されないため、ダッシュボードはテストの最後の実際の実行からのステータスを表示し続けます — そのスナップショットは数週間前のものである可能性があります。

### テストの実行 {#running-tests}

`tuist xcodebuild test` は両方のモードを自動的に尊重するパススルーラッパーです。xcodebuildを呼び出すのと同じ方法で使用します：

```sh
tuist xcodebuild test -scheme MyScheme
```

スキップされたテストは、xcodebuild呼び出しに `-skip-testing <identifier>` として追加され、決して開始されません。ミュートされたテストは通常通り実行されます。失敗した場合、その失敗は結果のビルドステータスでマスクされます。

#### 隔離のバイパス

`tuist xcodebuild test` は `--skip-quarantine` を受け入れ、ミュートおよびスキップされたテストを含め、すべてを実行します：

```sh
tuist xcodebuild test --skip-quarantine -scheme MyScheme
```

#### xcodebuildを直接呼び出す

`tuist xcodebuild test` を経由できない場合は、`tuist test case list` を使用して、隔離されたテストを自分で `-skip-testing` 引数に展開します：

```sh
xcodebuild test \
  -scheme MyScheme \
  $(tuist test case list --quarantined --skip-testing)
```

これは `tuist xcodebuild test` の外部での安全なデフォルトです：ミュートされたテストの失敗マスキングは、そのコマンドを経由した場合のみ発生するため、両方のモードをスキップすることで虚偽のCI失敗を回避します。より細かい制御が必要な場合は、代わりに `tuist xcodebuild test` を経由してください。

## 新しいテストのストレステスト {#stress-testing-new-tests}

ストレステストゲートは、ブランチが追加したテストケースをそれぞれ新しいプロセスで複数回再実行し、不安定であることが判明したものを報告します。数週間後ではなく、それを導入したプルリクエスト上で新しい不安定なテストを確認できます。

テストケースは、プロジェクトのデフォルトブランチで過去90日間にCIで実行されていない場合、またはそれ以降にそのブランチにマージされたコミット上で実行されていない場合に新しいとカウントされます。マージキューを使用している場合、キューが実行したテストケースは、キューのコミットがマージされた時点で認識され、キューがそれを削除した場合でも新しい状態を維持します。コミットのマッチングは、TuistがCIで収集する<.localized_link href="/guides/features/test-insights/xcode#git-history">Git履歴</.localized_link>を通じて行われます。

### 有効化

ゲートはデフォルトでオフになっています。モードを設定してください：

- **`report`**：各不安定なテストケースについて警告します。実行はその自身の結果に基づいて終了します。
- **`enforce`**：不安定なテストケースがあると実行が失敗し、失敗したテストと同じ終了コードになります。

`report`を数週間使用して、`enforce`が何をブロックしていたかを確認してください。

パススルー引数の前に渡すか、`TUIST_TEST_STRESS_NEW_TESTS`を設定してCIレーンごとにモードを変更します：

```sh
tuist xcodebuild test --stress-new-tests report -scheme MyScheme
```

### 各テストの再実行回数

最初のパスでのテストケースの実行時間によって異なります：

| 最初のパス | 再実行 |
| --- | --- |
| 最大5秒 | 10 |
| 最大10秒 | 5 |
| 最大30秒 | 3 |
| 最大5分 | 2 |
| 5分以上 | 再実行なし |

再実行では、最初のパスでビルドされたものを利用します。パスは200テストケースまたは10分のいずれかに達すると停止し、どの制限に達したかを報告します。

### ゲートが実行されない場合

- 最初のパスがすでに失敗しています。まずそれらのテストを修正してください。
- プロジェクトにデフォルトブランチがないか、まだCIで何も実行されていません。
- プロジェクトのテストケースの30%以上が新しいように見えます。それほど多くを再実行するのはコストに見合いません。これは、Tuistへのレポートを始めたばかりのプロジェクトや、一度に多くのテストを移動させる名前変更の後などで発生することがあります。

## Slack通知 {#slack-notifications}

Slack連携で<.localized_link href="/guides/integrations/slack#flaky-test-alerts">不安定なテストのアラート</.localized_link>を設定することで、テストが不安定になった際に即座に通知を受け取ることができます。

## 不安定および隔離状態のクエリ {#querying}

### CLI

`tuist test case`コマンドツリーは、Tuistがテストケースについて追跡しているすべてを公開します：

```sh
tuist test case list --flaky                       # only flaky test cases
tuist test case list --quarantined                 # only muted or skipped test cases
tuist test case show <test_case_id>                # detail: flakiness rate, last status, run counts
tuist test case events <test_case_id>              # audit log: marked_flaky, muted, skipped, ...
tuist test case run list <test_case_id>            # run history with status and duration
tuist test case run show <test_case_run_id>        # single run, including failure breakdown
```

これらすべてはスクリプト用に`--json`を受け入れます。

### REST API

同じデータはHTTP経由でも利用可能です — ルート、フィルター、レスポンスフィールドの完全なリストについては、APIリファレンスの[テストケースエンドポイント](https://tuist.dev/api/docs#tag/test-cases)を参照してください。テストケースの状態（不安定のマーク/解除、ミュート、スキップ）を変更するには、`is_flaky`または`state`を使用して`PATCH /api/projects/{account_handle}/{project_handle}/tests/test-cases/{test_case_id}`を送信してください。同じ変更は`tuist test case update`としても、また`update_test_case` Model Context Protocolツールとしても利用可能です。
