---
{
  "title": "Bazel テストインサイト",
  "titleTemplate": ":title · テストインサイト · 機能 · ガイド · Tuist",
  "description": "Tuist ダッシュボードで Bazel のテスト分析を追跡し、テストのパフォーマンスと信頼性を監視します。"
}
---
# Bazelテストインサイト {#bazel-test-insights}

Tuist経由でBazelテストを実行すると、他のビルドシステムと同じテストダッシュボードにデータを送れます。

```bash
tuist bazel test -- //app:tests
```

`--`以降の引数は`bazel test`に転送されます。`--path`を使ってプロジェクトとワーキングディレクトリを選択し、`--bazel`を使って`bazelisk`などの別の実行ファイルを選択できます。通常の`bazel test`でもテスト結果はレポートされますが、Tuistの検疫ポリシーの取得や適用は行いません。

> [!NOTE]
> `tuist bazel test`ラッパーは<.localized_link href="/guides/features/test-insights/flaky-tests/bazel">検疫対象のテスト</.localized_link>でのみ必要です。通常のテスト実行におけるケースごとのレポートは、`tuist bazel setup`によって`.bazelrc.tuist`内で設定されるため、単なる`bazel test`でも個別のケースがレポートされます。

## 追跡対象 {#what-is-tracked}

Tuistは`test.xml`レポートを解析し、Bazelが各テストターゲットに対して生成する`test.log`出力を取得して、共通のテスト実行モデルに集約します。各実行では以下を記録します。

- 個別のテストケースの合格・不合格・スキップステータスと所要時間。
- テストターゲット、クラス、およびスイートの構造。
- Bazelで不安定なテストの再試行が設定されている場合の再試行回数。
- ターゲットの`test.log`から取得した失敗時の出力。

**テスト実行**、**テストケース**、および個別のテストページは、Bazelでも他のビルドシステムと同様に動作します。

## ケースごとのJUnitレポートの出力 {#per-case-junit-reports}

ケースごとの行は、テストターゲットがBazelから提供される`$XML_OUTPUT_FILE`パスにJUnit `test.xml`を書き込むことに依存します。ランナーがこれを書き込まない場合、Bazelはターゲット名を付けた合成された単一ケースのレポートにフォールバックし、Tuistはターゲットごとに1行を表示します（テストケース一覧では**Bazelターゲット**としてラベル付け）。生の`test.log`は実行ページで引き続き利用可能です。

ほとんどのBazelテストルールはすでに実際の`test.xml`を出力します。

- `java_test`および`kt_jvm_test`：JUnitが組み込まれています。
- GoogleTestを使用した`cc_test`：最新のgtestに対してコンパイルされるとランナーがJUnitを書き込みます。古い環境では`--gtest_output=xml:$XML_OUTPUT_FILE`が必要です。
- `py_test`：`--junitxml=$XML_OUTPUT_FILE`を使用してpytestを利用するか、`rules_python`のpytestランナーを使用します。
- `go_test`：`go test -json`を`gotestsum --junitfile=$XML_OUTPUT_FILE`にパイプするか、JUnitを出力するヘルパーでラップします。

`rules_rust`および`rules_rs`からの`rust_test`は標準の`libtest`ハーネスを実行しますが、安定版のRustではJUnitを書き出しません。テストターゲットを、`libtest`出力を解析して`$XML_OUTPUT_FILE`にJUnitを書き込むスクリプトでラップしてください。これにより、Tuistでケースごとの行を維持しつつ、同じ実行は単一のBazelテストターゲットのままになります。

## テストの識別 {#test-identity}

ケースはターゲットラベル、クラス名（スイート名にフォールバック）、およびテスト名で識別されます。これにより、異なるクラス内の同名メソッドが区別されます。異なる包含スイート名を使用した古いレポートは、古い識別子のもとで履歴を保持します。古い識別子に適用された状態変更は新しい識別子にも再適用する必要があり、コマンドは失敗が古い識別子と一致した場合に警告を出し、どのポリシーを移行すべきかを示します。

## CIコンテキストの提供 {#providing-ci-context}

TuistはBazelのビルドメタデータからGitコミットおよびブランチ情報を読み取るため、同じコミットでの実行を環境間で比較できます。ほとんどの継続的インテグレーションシステムはこれらを既に設定していますが、設定されていない場合は明示的に渡してください。

```bash
tuist bazel test -- \
  --build_metadata=CI=true \
  --build_metadata=GIT_COMMIT="$GIT_COMMIT" \
  --build_metadata=GIT_BRANCH="$GIT_BRANCH" //app:tests
```

同じ`--build_metadata`フラグは、<.localized_link href="/guides/features/build-insights/bazel#custom-metadata">Bazelビルドインサイト</.localized_link>ページで呼び出しにタグを付けるために説明されているものなので、単一のフラグセットで両方の表面をカバーします。

## 不安定なテストと検疫 {#flaky-tests-and-quarantine}

再試行、実行横断的な不安定性の検出、およびケースごとの検疫（ミュートとスキップ）はすべて`tuist bazel test`を通じて機能します。完全なワークフローについては<.localized_link href="/guides/features/test-insights/flaky-tests/bazel">Bazelの不安定なテスト</.localized_link>をご覧ください。

## データ保持 {#data-retention}

Tuistは、テスト実行を生成したBazelの呼び出し、そのログ、および保留中のテスト取り込みレコードを90日間保持します。テストケースとその実行履歴は他のすべてのビルドシステムと同じモデルを使用しており、この期間の対象外です。完全なポリシーについては<.localized_link href="/guides/server/data-retention">データ保持</.localized_link>をご覧ください。
