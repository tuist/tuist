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

<LocalizedLink href="/guides/features/projects">生成されたプロジェクト</LocalizedLink>でテストを選択的に実行するには、`tuist
test`
コマンドを使用します。このコマンドは、<LocalizedLink href="/guides/features/cache/module-cache">モジュールキャッシュ</LocalizedLink>と同様の方法でXcodeプロジェクトを<LocalizedLink href="/guides/features/projects/hashing">ハッシュ化</LocalizedLink>し、成功時にはハッシュを永続化して、将来の実行時に変更箇所を特定します。
次回のテスト実行時には、`tuist test`
がハッシュ値を透過的に使用し、前回の正常なテスト実行以降に変更があったテストのみをフィルタリングして実行します。

`tuist test` は
<LocalizedLink href="/guides/features/cache/module-cache">モジュールキャッシュ</LocalizedLink>と直接連携し、ローカルまたはリモートストレージから可能な限り多くのバイナリを利用することで、テストスイート実行時のビルド時間を短縮します。選択的テストとモジュールキャッシュの組み合わせにより、CI環境でのテスト実行時間を大幅に削減できます。

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
test`
の使用を開始すると、Tuistはプルリクエスト/マージリクエストに直接コメントを投稿します。実行されたテストとスキップされたテストが含まれます：![GitHubアプリコメント（Tuistプレビューリンク付き）](/images/guides/features/selective-testing/github-app-comment.png)
