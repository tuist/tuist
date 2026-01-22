---
{
  "title": "Flaky Tests",
  "titleTemplate": ":title · Test Insights · Features · Guides · Tuist",
  "description": "Automatically detect and track flaky tests in your CI pipelines."
}
---
# 不安定なテスト{#flaky-tests}

警告 要件
<!-- -->
- <LocalizedLink href="/guides/features/test-insights">Test
  Insights</LocalizedLink> は設定が必要です
<!-- -->
:::

不安定なテストとは、同じコードで複数回実行した際に異なる結果（合格または不合格）を生成するテストです。これらはテストスイートへの信頼を損ない、開発者が誤った失敗を調査する時間を浪費させます。Tuistは不安定なテストを自動的に検出し、時間の経過とともに追跡するのを支援します。

![Flaky Tests page](/images/guides/features/test-insights/flaky-tests-page.png)

## フラッキー検出の仕組み{#how-it-works}

Tuistは不安定なテストを2つの方法で検出します：

### テスト再試行{#test-retries}

Xcodeのリトライ機能（`-retry-tests-on-failure` または`-test-iterations`
を使用）でテストを実行すると、Tuistは各試行の結果を分析します。テストが一部の試行で失敗し、他の試行で成功する場合、フラッキーとしてマークされます。

例えば、テストが最初の試行では失敗するが再試行で成功する場合、Tuistはこれを不安定なテストとして記録します。

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -retry-tests-on-failure \
  -test-iterations 3
```

![不安定なテストケースの詳細](/images/guides/features/test-insights/flaky-test-case-detail.png)

### クロスラン検出{#cross-run-detection}

テストの再実行がなくても、Tuistは同一コミットに対する異なるCI実行間の結果を比較することで不安定なテストを検出できます。同一コミットに対してあるCI実行でテストが成功し、別の実行で失敗した場合、両方の実行が不安定なテストとしてマークされます。

これは、再試行では検出できないほど一貫して失敗しないが、それでも断続的なCI失敗を引き起こす不安定なテストを検出するのに特に有用です。

## 不安定なテストの管理{#managing-flaky-tests}

### 自動クリア

Tuistは、14日間不安定な動作を示していないテストから自動的に不安定フラグを解除します。これにより、修正されたテストが永久に不安定としてマークされ続けることが防止されます。

### 手動管理

テストケースの詳細ページから、手動でテストを不安定なテストとしてマークまたはマーク解除することもできます。これは以下の場合に便利です：
- 既知の不具合のあるテストを修正作業中に認識したい
- インフラストラクチャの問題により、テストが誤ってフラグ付けされました

## Slack通知{#slack-notifications}

Slack連携で<LocalizedLink href="/guides/integrations/slack#flaky-test-alerts">不安定なテスト通知</LocalizedLink>を設定すると、テストが不安定になった際に即時通知を受け取れます。
