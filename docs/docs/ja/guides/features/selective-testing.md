---
{
  "title": "Selective testing",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Use selective testing to run only the tests that have changed since the last successful test run."
}
---
# 選択的検査{#selective-testing}

`
プロジェクトが大きくなるにつれて、テストの数も増えていきます。長い間、`のmainブランチへのプルリクエストやプッシュのたびにすべてのテストを実行するには、数十秒かかっていました。しかし、この方法では、チームが抱える数千ものテストに対応することはできません。

CIでのテスト実行のたびに、変更の有無にかかわらず、すべてのテストを再実行している可能性が高いでしょう。Tuistの選択的テスト機能は、当社の<LocalizedLink href="/guides/features/projects/hashing">ハッシュアルゴリズム</LocalizedLink>に基づいて、前回の正常なテスト実行以降に変更があったテストのみを実行することで、テスト実行そのものを大幅に高速化します。

<LocalizedLink href="/guides/features/projects">生成されたプロジェクト</LocalizedLink>でテストを選択的に実行するには、`tuist
test`
コマンドを使用します。このコマンドは、<LocalizedLink href="/guides/features/cache/module-cache">モジュールキャッシュ</LocalizedLink>と同様の方法でXcodeプロジェクトを<LocalizedLink href="/guides/features/projects/hashing">ハッシュ化</LocalizedLink>し、成功時にはハッシュを永続化して、将来の実行時に変更箇所を特定します。
次回のテスト実行時には、`tuist test`
がハッシュ値を透過的に使用し、前回の正常なテスト実行以降に変更があったテストのみをフィルタリングして実行します。

`tuist test` は
<LocalizedLink href="/guides/features/cache/module-cache">モジュールキャッシュ</LocalizedLink>と直接連携し、ローカルまたはリモートストレージから可能な限り多くのバイナリを利用することで、テストスイート実行時のビルド時間を短縮します。選択的テストとモジュールキャッシュの組み合わせにより、CI環境でのテスト実行時間を大幅に削減できます。

::: warning MODULE VS FILE-LEVEL GRANULARITY
<!-- -->
テストとソース間のコード内依存関係を検出することは不可能なため、選択的テストの最大粒度はターゲットレベルとなります。したがって、選択的テストの効果を最大限に引き出すために、ターゲットは小さく、焦点を絞ったものにしておくことをお勧めします。
<!-- -->
:::

::: warning TEST COVERAGE
<!-- -->
テストカバレッジツールは、テストスイート全体が一度に実行されることを前提としているため、選択的なテスト実行とは互換性がありません。つまり、テスト選択機能を使用する場合、カバレッジデータが実際の状況を反映していない可能性があります。これは既知の制限事項であり、あなたが何か間違ったことをしているわけではありません。
このような状況下でもカバレッジが依然として有意義な知見をもたらしているかどうか、チームで検討することをお勧めします。もしそうであるならば、将来的に選択的な実行でもカバレッジが適切に機能するよう、すでに検討を進めていることをご安心ください。
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
