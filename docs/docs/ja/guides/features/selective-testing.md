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

To run tests selectively with your
<LocalizedLink href="/guides/features/projects">generated
project</LocalizedLink>, use the `tuist test` command. The command
<LocalizedLink href="/guides/features/projects/hashing">hashes</LocalizedLink>
your Xcode project the same way it does for the
<LocalizedLink href="/guides/features/cache/module-cache">module
cache</LocalizedLink>, and on success, it persists the hashes to determine what
has changed in future runs. In future runs, `tuist test` transparently uses the
hashes to filter down the tests and run only the ones that have changed since
the last successful test run.

`tuist test` integrates directly with the
<LocalizedLink href="/guides/features/cache/module-cache">module
cache</LocalizedLink> to use as many binaries from your local or remote storage
to improve the build time when running your test suite. The combination of
selective testing with module caching can dramatically reduce the time it takes
to run tests on your CI.

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

Once your Tuist project is connected with your Git platform such as
[GitHub](https://github.com), and you start using `tuist test` as part of your
CI workflow, Tuist will post a comment directly in your pull/merge requests,
including which tests were run and which skipped: ![GitHub app comment with a
Tuist Preview
link](/images/guides/features/selective-testing/github-app-comment.png)
