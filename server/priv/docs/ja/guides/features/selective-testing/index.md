---
{
  "title": "選択的テスト",
  "titleTemplate": ":title · 機能 · ガイド · Tuist",
  "description": "Tuist Selective Testing を使用して、最新の変更の影響を受けるテストのみを実行し、継続的インテグレーションによるフィードバックを数秒で受け取れます。"
}
---
# 選択的テスト {#selective-testing}

プロジェクトが大きくなるにつれて、すべてのプッシュで全テストを実行することは現実的でなくなります。Tuist Selective Testingは、<.localized_link href="/guides/features/projects/hashing">ハッシュアルゴリズム</.localized_link>を使用して、最後の成功した実行以降に変更された部分に影響を受けるテストのみを実行することで、テスト時間を大幅に短縮します。

## 対応しているビルドシステム {#supported-build-systems}

- <.localized_link href="/guides/features/selective-testing/generated-xcode-project">Generated Xcode project</.localized_link>

他のビルドシステムのサポートも計画されています。
