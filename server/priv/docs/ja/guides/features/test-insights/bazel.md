---
{
  "title": "Bazel テストインサイト",
  "titleTemplate": ":title · テストインサイト · 機能 · ガイド · Tuist",
  "description": "Tuist ダッシュボードで Bazel のテスト分析を追跡し、テストのパフォーマンスと信頼性を監視します。"
}
---
# Bazel テストインサイト {#bazel-test-insights}

Tuist を介して Bazel テストを実行し、他のすべてのビルドシステムと同じテストダッシュボードにデータを送ります。

```bash
tuist bazel test -- //app:tests
```

`--` 以降の引数は `bazel test` に転送されます。`--path` を使用してプロジェクトと作業ディレクトリを選択し、`--bazel` を使用して `bazelisk` などの別の実行ファイルを選択します。通常の `bazel test` でもテスト結果は報告されますが、Tuist の検疫ポリシーの取得や適用は行いません。

> [!NOTE]
> `tuist bazel test` ラッパーは <.localized_link href="/guides/features/test-insights/flaky-tests/bazel">検疫されたテスト</.localized_link> にのみ必要です。通常のテスト実行におけるケースごとのレポートは、`.bazelrc.tuist` 内の `tuist bazel setup` によって設定されるため、単なる `bazel test` でも個別のケースが報告されます。

## 追跡対象 {#what-is-tracked}

Tuist は `test.xml` レポートを解析し、Bazel が各テストターゲットに対して生成する `test.log` 出力を取得して、共有のテスト実行モデルに集約します。各実行では以下を記録します。

- 個々のテストケースの合格、不合格、スキップされたステータス、および所要時間。
- テストターゲット、クラス、およびスイートの構造。
- Bazel で不安定なテストの再試行が構成されている場合の再試行回数。
- ターゲットの `test.log` から取得した失敗時の出力。

**テスト実行**、**テストケース**、および個々のテストページはすべて、Bazel でも他のビルドシステムと同様に動作します。

## ケースごとの JUnit レポートの出力 {#per-case-junit-reports}

ケースごとの行は、テストターゲットが Bazel が提供する `$XML_OUTPUT_FILE` パスに JUnit `test.xml` を書き込むことに依存します。ランナーがこれを書き込まない場合、Bazel はターゲット名に基づいた合成された単一ケースのレポートにフォールバックし、Tuist はターゲットごとに 1 行を表示します（テストケースリストでは **Bazel ターゲット** とラベル付けされ）、生 の `test.log` は実行ページで引き続き利用可能です。

ほとんどの Bazel テストルールはすでに実際の `test.xml` を生成します。

- `java_test` および `kt_jvm_test`: JUnit が組み込まれています。
- GoogleTest を使用した `cc_test`: 最近の gtest に対してコンパイルすると、ランナーが JUnit を書き込みます。古いセットアップでは `--gtest_output=xml:$XML_OUTPUT_FILE` が必要です。
- `py_test`: `--junitxml=$XML_OUTPUT_FILE` を使用して pytest を実行するか、`rules_python` pytest ランナーを使用します。
- `go_test`: `go test -json` を `gotestsum --junitfile=$XML_OUTPUT_FILE` にパイプするか、JUnit を出力するヘルパーでラップします。

`rules_rust` および `rules_rs` からの `rust_test` は標準の `libtest` ハーネスを実行しますが、安定版の Rust では JUnit を書き込みません。テストターゲットを、`libtest` 出力を解析して `$XML_OUTPUT_FILE` に JUnit を書き込むスクリプトでラップしてください。これにより、Tuist でケースごとの行を維持しつつ、同じ実行は単一の Bazel テストターゲットのままになります。

## テストの識別 {#test-identity}

ケースはターゲットラベル、クラス名（スイート名にフォールバック）、およびテスト名によって識別されます。これにより、異なるクラス内の同名のメソッドが区別されます。異なる包含スイート名を使用した古いレポートは、古い識別子の下で履歴を保持します。古い識別子に適用された状態変更は新しい識別子にも再適用する必要があり、コマンドは失敗が古い識別子と一致する場合に警告を発するため、どのポリシーを移行すべきかがわかります。

## CI コンテキストの提供 {#providing-ci-context}

Tuist は Bazel のビルドメタデータから git コミットおよびブランチ情報を読み取るため、同じコミットでの実行を環境間で比較できます。ほとんどの継続的インテグレーションシステムはこれらをすでに設定しています。設定されていない場合は、明示的に渡してください。

```bash
tuist bazel test -- \
  --build_metadata=CI=true \
  --build_metadata=GIT_COMMIT="$GIT_COMMIT" \
  --build_metadata=GIT_BRANCH="$GIT_BRANCH" //app:tests
```

同じ `--build_metadata` フラグは、<.localized_link href="/guides/features/build-insights/bazel#custom-metadata">Bazel ビルドインサイト</.localized_link> ページで呼び出しにタグを付けるために説明されているものなので、単一のフラグセットで両方の表面をカバーします。

## 不安定なテストと検疫 {#flaky-tests-and-quarantine}

再試行、実行横断的な不安定性の検出、およびケースごとの検疫（ミュートとスキップ）はすべて `tuist bazel test` を介して機能します。完全なワークフローについては <.localized_link href="/guides/features/test-insights/flaky-tests/bazel">Bazel の不安定なテスト</.localized_link> を参照してください。

## データ保持 {#data-retention}

Tuist は、テスト実行を生成した Bazel 呼び出し、そのログ、および保留中のテスト取り込みレコードを 90 日間保持します。テストケースとその実行履歴は他のすべてのビルドシステムと同じモデルを使用しており、その期間の対象外です。完全なポリシーについては <.localized_link href="/guides/server/data-retention">データ保持</.localized_link> を参照してください。
