---
{
  "title": "Bazelの不安定なテスト",
  "titleTemplate": ":title · 不安定なテスト · テストインサイト · 機能 · ガイド · Tuist",
  "description": "Bazelの不安定なテストを検出し、失敗をミュートし、隔離されたターゲットをスキップします。"
}
---
# Bazel の不安定なテスト {#bazel-flaky-tests}

> [!IMPORTANT]
> **要件**
>
> - <.localized_link href="/guides/features/test-insights/bazel">Bazel テストインサイト</.localized_link> を `tuist bazel setup` で設定します。

<!-- @snippet: ./_intro -->

## 不安定な検出の仕組み {#how-it-works}

Tuist は Bazel の `test.xml` レポートから個々のケースを取得し、リトライ間および継続的インテグレーションにおける同一コミットとターゲット選択の実行間で結果の不整合を検出します。ローカル実行は表示されますが、テストケースを自動的に不安定としてフラグ付けしません。

### テストのリトライ {#test-retries}

リトライはオプションであり、隔離とは独立しています。`--flaky_test_attempts=3` を指定すると、追加のリトライ 3 回ではなく、テストあたり最大 **合計 3 回の Bazel 試行** が有効になります。既存のリトライ設定を `.bazelrc` に維持するか、明示的に渡してください。

```sh
tuist bazel test -- --flaky_test_attempts=3 //app:tests
```

Tuist が結果を観測するには、リトライが実際に実行される必要があります。Bazel ターゲットの不安定サマリーだけでは、どの個別のケースが不安定だったかを特定できません。

### 実行横断的な検出 {#cross-run-detection}

実行を比較するにはコミットとブランチのメタデータが必要です。ビルド環境がすでに公開していない場合は、これを指定してください。

```sh
tuist bazel test -- \
  --build_metadata=CI=true \
  --build_metadata=GIT_COMMIT="$GIT_COMMIT" \
  --build_metadata=GIT_BRANCH="$GIT_BRANCH" //app:tests
```

ケースはターゲットラベル、クラス名（フォールバックとしてスイート名）、およびテスト名で識別されます。詳細は <.localized_link href="/guides/features/test-insights/bazel">Bazel テストインサイト</.localized_link> を参照してください。

<!-- @snippet: ./_managing -->

## 不安定なテストの隔離 {#quarantining}

<!-- @snippet: ./_quarantine-intro -->

`tuist bazel test` は各呼び出しの前に隔離ポリシーを取得し、基盤となる `bazel test` 実行に適用します。通常の `bazel test` でもテスト結果は報告されますが、隔離は適用されません。

```sh
tuist bazel test -- //app:tests
```

`--` 以降の引数は `bazel test` に転送されます。`--path` を使用してプロジェクトと作業ディレクトリを選択し、`--bazel` を使用して `bazelisk` などの別の実行ファイルを選択します。`--config=ci` などの名前付き Bazel 構成はオプションで、同じように動作します。

### ミュート {#mute}

主要な隔離ワークフローとして **ミュート** を使用します。ミュートされたケースは引き続き実行され、その失敗は表示されたままになり、正常な兄弟ケースは結果に影響を与え続けます。Tuist は、レポートが各失敗したターゲット内のすべての失敗をミュートされたケースに帰属させる場合にのみ、Bazel のテスト失敗終了を成功に変換します。ビルドエラー、タイムアウト、中断された実行、欠落または不完全なレポート、およびミュートセット外の失敗は、Bazel の失敗ステータスを維持します。

### スキップ {#skip}

スキップは Bazel ターゲット単位で動作します。1 つのケースをスキップすると、Bazel がすべてのテストフレームワークに対して個別のケースをフィルタリングできないため、正常なケースを含めてそのターゲット全体が除外されます。ターゲット全体を除外する意図がない限り、**ミュート** を優先してください。コマンドは除外されたすべてのターゲットラベルを表示するため、ビルドログには隔離ポリシーによって除外された内容が表示されます。

スキップされたターゲットが存在しなくなった場合、Tuist は警告でその名前を示し、その除外なしで実行します。古くなったケースを **有効** に戻して、そのポリシーを完全に削除してください。テストターゲットが残っていない場合、Bazel は通常の「テストが見つかりません」終了ステータスを維持します。

<!-- @snippet: ./_quarantined-passing -->

### 隔離されたテストの再実行 {#running-quarantined-tests-again}

修正を調査または検証するには、隔離ポリシーをバイパスします。

```sh
tuist bazel test --no-quarantine -- --nocache_test_results //app:tests
```

ケースを **有効** に戻して、後続の通常の実行でそのターゲットを含めるようにします。スキップされたケースは明示的に含まれるまで新しい実行を生成しないため、成功した新しい実行に基づく自動化では、それらを回復する前に検証実行が必要です。

### 制限事項 {#limitations}

- 明示的な `--build_event_json_file` または `--target_pattern_file` は、アクティブな隔離と組み合わせることはできません。ターゲットパターンを直接渡してください。
- Tuist が隔離ポリシーを取得できない場合、コマンドはテストを実行する前に停止します。部分的なポリシーが適用されることはありません。意図的に隔離なしで実行したい場合は `--no-quarantine` を使用してください。
- 古いスイートベースの識別子で記録されたミュートに一致する失敗はブロック状態を維持し、コマンドは再適用するポリシーの名前を示します。

基盤となる動作については、Bazel の [テストフィルター](https://bazel.build/docs/user-manual#test-filter)、[コマンドオプション](https://bazel.build/reference/command-line-reference)、および [ビルドイベントの説明](https://bazel.build/remote/bep-glossary) を参照してください。

<!-- @snippet: ./_slack -->

<!-- @snippet: ./_querying -->
