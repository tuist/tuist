---
{
  "title": "選択的テスト",
  "titleTemplate": ":title · 機能 · ガイド · Tuist",
  "description": "Tuist Selective Testing で最新の変更の影響を受けるテストのみを実行し、継続的インテグレーションによるフィードバックを数秒で受け取れます。"
}
---
# 選択的テスト {#selective-testing}

プロジェクトが大きくなると、プッシュごとにすべてのテストを実行することが現実的ではなくなります。Tuist Selective Testingは、最後の成功した実行以降に変更された部分に影響を受けるテストのみを実行することで、テスト時間を大幅に短縮します。これには、<.localized_link href="/guides/features/projects/hashing">ハッシュアルゴリズム</.localized_link>を使用しています。

## サポートされているビルドシステム {#supported-build-systems}

- <.localized_link href="/guides/features/selective-testing/generated-xcode-project">Generated Xcode project</.localized_link>

他のビルドシステムのサポートも計画されています。
