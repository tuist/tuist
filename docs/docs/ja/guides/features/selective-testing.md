---
{
  "title": "Selective testing",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Use selective testing to run only the tests that have changed since the last successful test run."
}
---
# 選択的検査{#selective-testing}

プロジェクトが成長するにつれて、テストの数も増加します。長らく、`main へのすべてのプルリクエストやプッシュに対して全テストを実行するには、`
で数十秒を要していました。しかしこの解決策は、チームが抱える数千ものテストには対応できません。

CIでのテスト実行時には、変更の有無に関わらず全テストを再実行している可能性が高いです。Tuistの選択的テスト機能は、<LocalizedLink href="/guides/features/projects/hashing">ハッシュアルゴリズム</LocalizedLink>に基づき前回の成功実行以降に変更されたテストのみを実行することで、テスト実行自体を大幅に高速化します。

選択的テストは、`xcodebuild`
で動作します。これはあらゆるXcodeプロジェクトをサポートします。Tuistでプロジェクトを生成している場合は、代わりに`tuist test`
コマンドを使用できます。これは<LocalizedLink href="/guides/features/cache">バイナリキャッシュ</LocalizedLink>との統合など、追加の利便性を提供します。選択的テストを開始するには、プロジェクト設定に基づいて以下の手順に従ってください：

- <LocalizedLink href="/guides/features/selective-testing/xcode-project">xcodebuild</LocalizedLink>
- <LocalizedLink href="/guides/features/selective-testing/generated-project">生成されたプロジェクト</LocalizedLink>

::: warning MODULE VS FILE-LEVEL GRANULARITY
<!-- -->
テストとソース間のコード内依存関係を検出できないため、選択的テストの最大粒度はターゲットレベルとなります。したがって、選択的テストの効果を最大化するため、ターゲットを小さく焦点を絞った状態に保つことを推奨します。
<!-- -->
:::

::: warning TEST COVERAGE
<!-- -->
テストカバレッジツールはテストスイート全体が一括実行されることを前提としているため、選択的テスト実行とは互換性がありません。つまり、テスト選択時にカバレッジデータが実態を反映しない可能性があります。これは既知の制限事項であり、操作ミスを意味するものではありません。
この状況下でカバレッジが依然として有意義な知見をもたらしているか、チームで検討することを推奨します。もしそうであれば、将来的に選択的実行とカバレッジを適切に連携させる方法を既に検討中ですのでご安心ください。
<!-- -->
:::


## プル/マージリクエストのコメント{#pullmerge-request-comments}

::: warning INTEGRATION WITH GIT PLATFORM REQUIRED
<!-- -->
自動プルリクエスト/マージリクエストコメントを取得するには、<LocalizedLink href="/guides/server/accounts-and-projects">Tuistプロジェクト</LocalizedLink>を<LocalizedLink href="/guides/server/authentication">Gitプラットフォーム</LocalizedLink>と連携させてください。
<!-- -->
:::

Tuistプロジェクトを[GitHub](https://github.com)などのGitプラットフォームと連携し、CIワークフローの一環として`tuist
xcodebuild test` または`tuist test`
を実行すると、Tuistはプルリクエスト/マージリクエストに直接コメントを投稿します。実行されたテストとスキップされたテストが含まれます:
![GitHubアプリへのTuistプレビューリンク付きコメント](/images/guides/features/selective-testing/github-app-comment.png)
