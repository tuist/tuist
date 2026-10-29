---
{
  "title": "Generated Xcode project",
  "titleTemplate": ":title · Flaky tests · Test insights · Features · Guides · Tuist",
  "description": "Detect, manage, and quarantine flaky tests in a Tuist-generated Xcode project."
}
---
# 生成されたXcodeプロジェクト {#generated-xcode-project-flaky-tests}

> [!WARNING]
> **要件**
>
> - <.localized_link href="/guides/features/test-insights/xcode">Xcodeテストインサイト</.localized_link>が設定されていること（自動生成されたスキームには`tuist inspect test`ポストアクションが含まれています。カスタムスキームではこれを追加する必要があります）。

Flakyテストとは、同じコードで複数回実行したときに異なる結果（合格または不合格）を返すテストのことです。これらはテストスイートへの信頼を損ない、誤った失敗の調査に開発者の時間を浪費させます。TuistはFlakyテストを自動的に検出し、時間経過に伴う追跡をサポートします。

![Flakyテストページ](/images/guides/features/test-insights/flaky-tests-page.png)

## Flaky検出の仕組み {#how-it-works}

Tuistは以下の2つの方法でFlakyテストを検出します。

### テストの再試行 {#test-retries}

再試行機能を使用してテストを実行すると、Tuistは各試行の結果を分析します。ある試行では失敗し、別の試行では成功するテストはFlakyとしてマークされます。

`-retry-tests-on-failure`または`-test-iterations`を`tuist test`経由で渡します。

```sh
tuist test --scheme MyScheme -- -retry-tests-on-failure -test-iterations 3
```

![Flakyテストケースの詳細](/images/guides/features/test-insights/flaky-test-case-detail.png)

### クロスラン検出 {#cross-run-detection}

テストの再試行を行わなくても、Tuistは同じコミットおよび同じスキームに対する異なるCIランの結果を比較することでFlakyテストを検出できます。あるCIランではテストが成功し、同じコミットとスキームの別のランでは失敗する場合、両方のランがFlakyとしてマークされます。

スキームは比較キーの一部です。同じテストでもスキームによって決定的に異なる動作をする可能性があるためです。例えば、特定のシミュレータデスティネーションに対してのみ有効なスナップショットテストや、異なるフラグでコンパイルされるテストターゲットなどが挙げられます。異なるスキームで同じコミットを2回実行した場合、それらは別の実行バリアントとして扱われ、互いをFlakyとしてフラグ付けすることはありません。

これは、再試行で捕捉できるほど一貫して失敗しないものの、依然として断続的なCI障害を引き起こすFlakyテストを検出するのに特に役立ちます。

## Flakyテストの管理 {#managing-flaky-tests}

### 自動クリア

検出とクリアは、プロジェクト上の**自動化アラート**を通じて実行されます。すべてのプロジェクトには、デフォルトの「Flakyテスト検出」自動化が用意されており、その*トリガー*はテストをFlakyとしてマークし、*リカバリー*は、テストが構成されたリカバリー期間（デフォルト**14日間**）中に再トリガーされずに経過した場合にフラグをクリアします。**設定 → 自動化**で編集して、リカバリー期間を変更したり、リカバリーアクション（例：隔離解除も行う）を入れ替えたり、リカバリーを完全に無効にしてテストを手動でクリアするまでFlakyマークのままにするように設定できます。

### 手動管理

テストケースの詳細ページから、テストをFlakyとして手動でマークしたり、マークを解除したりすることもできます。これは以下のような場合に便利です。
- 修正作業中に既知のFlakyテストを認識しておきたい場合
- インフラストラクチャの問題によりテストが誤ってフラグ付けされた場合

## Flakyテストの隔離 {#quarantining}

隔離は、Flakyテストを分離し、修正中にCIをブロックしないようにします。デフォルトでは**手動アクション**です。ダッシュボードのテストケース詳細ページから隔離、隔離解除、モードの切り替えを行います。ただし、**設定 → 自動化**の下にある**自動化アラート**に組み込むこともでき、テストがFlaky性の閾値を超えたときに自動的にミュート（またはスキップ）され、回復すると隔離解除されます。手動か自動かを問わず、すべての遷移はテストケースの監査ログに記録されます。

隔離されたテストは、以下の2つのモードのいずれかになります。

- **ミュート**: テストは引き続き実行されますが、`tuist test`が失敗をマスクします。失敗は依然としてFlakyテスト検出器に供給されるため、ビルドを壊さずにテストを監視し続けることができます。積極的に調査中のテストにこのモードを選択してください。
- **スキップ**: xcodebuildは`-skip-testing <identifier>`を受け取るため、テストは開始されません。新しい結果は生成されず、再度有効にするまでFlakyテストダッシュボードから除外されます。テストが壊れている、遅い、またはあまりにも持続的にFlakyで実行することがCI時間の無駄である場合にこのモードを選択してください。

### 隔離されたテストが合格として表示される理由 {#quarantined-passing}

- **ミュートされたテスト**は引き続き実行されます。失敗したミュートテストは、テストケースラン上で**失敗**として記録され、Flakyとしてフラグ付けされます。テストごとのステータスは書き換えられません。上書きされるのは**全体のテストラン**です。ラン内のすべての失敗テストケースがミュートされている場合、ラン全体は合格として報告されるため、ミュートされた失敗はCIを中断しません。
- **スキップされたテスト**はまったく実行されないため、ダッシュボードにはテストの最後の実際の実行からのステータスが引き続き表示されます。そのスナップショットは数週間前のものかもしれません。

### テストの実行 {#running-tests}

`tuist test`は両方のモードを自動的に尊重します。

```sh
tuist test
```

スキップされたテストは`-skip-testing`としてxcodebuildに渡され、開始されることはありません。ミュートされたテストは通常通り実行されます。失敗した場合、その失敗は結果のビルドステータスでマスクされます。

隔離を完全にバイパスし、ミュートおよびスキップされたテストを含めてすべてを実行するには:

```sh
tuist test --skip-quarantine
```

## 新しいテストのストレステスト {#stress-testing-new-tests}

ストレスゲートは、ブランチが追加したテストケースをそれぞれ新鮮なプロセスで複数回再実行し、Flakyであることが判明したものを報告します。数週間後ではなく、それを導入したプルリクエスト上で新しいFlakyテストを確認できます。

テストケースは、プロジェクトのデフォルトブランチで過去90日間にCIで実行されていない場合、またはその後そのブランチに着地したコミットで実行されていない場合に新規とみなされます。マージキューを使用する場合、キューが実行したテストケースは、キューのコミットが着地した時点で認識され、キューがそれをドロップした場合は新規のままとなります。コミットは、TuistがCIで収集する<.localized_link href="/guides/features/test-insights/xcode#git-history">Git履歴</.localized_link>を通じて照合されます。

### 有効化

ゲートはデフォルトでオフになっています。モードを設定してください。

- **`report`**: 各Flakyテストケースについて警告します。ランは依然として自身の結果に基づいて終了します。
- **`enforce`**: Flakyなテストケースはランを失敗させ、失敗したテストと同じ終了コードを返します。

どちらのモードでも、<.localized_link href="/guides/features/selective-testing/generated-xcode-project">選択的テスト</.localized_link>は、次のランでFlakyな新しいテストケースを含むテストターゲットをスキップしません。ターゲットは再度実行され、ゲートはテストケースがすべての再実行に合格するまで再度ストレステストを行います。

`report`で数週間開始し、`enforce`が何をブロックしていたかを確認してください。

パススルー引数の前に渡すか、`TUIST_TEST_STRESS_NEW_TESTS`を設定してCIレーンごとにモードを変更します:

```sh
tuist test --stress-new-tests report
```

### 各テストの再実行回数

最初のパスでテストケースにかかった時間によって異なります:

| 最初のパス | 再実行 |
| --- | --- |
| 最大5秒 | 10 |
| 最大10秒 | 5 |
| 最大30秒 | 3 |
| 最大5分 | 2 |
| 5分以上 | 再実行なし |

再実行は最初のパスでビルドされたものを再利用します。パスは200件のテストケースまたは10分のいずれかに達すると停止し、どの制限に達したかを報告します。

### ゲートが実行されない場合

- 最初のパスがすでに失敗しています。まずそれらのテストを修正してください。
- プロジェクトにデフォルトブランチがないか、そのブランチでCIがまだ何も実行されていません。
- プロジェクトのテストケースの30%以上が新規のように見えます。それほど多くを再実行するのは価値に見合いません。これは、Tuistへのレポートを始めたばかりのプロジェクトや、一度に多くのテストを移動させる名前変更後のプロジェクトで発生することが予想されます。

## Slack通知 {#slack-notifications}

Slack連携で<.localized_link href="/guides/integrations/slack#flaky-test-alerts">Flakyテストアラート</.localized_link>を設定することで、テストがFlakyになった瞬間に通知を受け取れます。

## Flakyおよび隔離状態のクエリ {#querying}

### CLI

`tuist test case`コマンドツリーは、Tuistがテストケースについて追跡するすべてを公開します:

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

同じデータはHTTP経由で利用可能です — ルート、フィルター、レスポンスフィールドの完全なリストについては、APIリファレンスの[テストケースエンドポイント](https://tuist.dev/api/docs#tag/test-cases)を参照してください。テストケースの状態（Flakyのマーク/解除、ミュート、スキップ）を変更するには、`is_flaky`または`state`を指定して`PATCH /api/projects/{account_handle}/{project_handle}/tests/test-cases/{test_case_id}`を送信します。同じ変更は`tuist test case update`として、および`update_test_case` Model Context Protocolツールとして利用可能です。
