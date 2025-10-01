---
{
  "title": "Selective testing",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Use selective testing to run only the tests that have changed since the last successful test run."
}
---
# 選択的テスト{#selective-testing}。

プロジェクトが大きくなるにつれて、テストの量も増えていきます。長い間、PR や`main`
へのプッシュのたびにすべてのテストを実行すると、数十秒かかっていました。しかし、この方法では何千ものテストに対応できません。

CI上でテストを実行するたびに、ほとんどの場合、変更点に関係なくすべてのテストを再実行することになる。Tuistの選択的テストは、私たちの<LocalizedLink href="/guides/features/projects/hashing">ハッシングアルゴリズム</LocalizedLink>に基づいて、最後に成功したテスト実行以降に変更されたテストのみを実行することで、テストの実行自体を劇的に高速化するのに役立ちます。

選択的テストは、`xcodebuild`
で動作します。これはあらゆるXcodeプロジェクトをサポートし、Tuistでプロジェクトを生成する場合は、代わりに`tuist test`
コマンドを使用することができます。選択テストを始めるには、プロジェクトのセットアップに基づいた指示に従ってください：

- <LocalizedLink href="/guides/features/selective-testing/xcode-project">エックスコードビルド</LocalizedLink>
- <LocalizedLink href="/guides/features/selective-testing/generated-project">生成されたプロジェクト</LocalizedLink>

> [テストとソース間のコード内依存性を検出することが不可能なため、選択的テストの最大粒度はターゲットレベルです。したがって、選択的テストの利点を最大化するために、ターゲットを小さくして、集中させることを推奨します。

> [警告] テストカバレッジ
> テストカバレッジツールは、テストスイート全体を一度に実行することを想定しています。これは既知の制限事項であり、あなたが何か間違ったことをしているわけではありません。カバレッジがこのような状況でも意味のある洞察をもたらしているかどうか、チームの皆さんに考えていただくことをお勧めします。もしそうであれば、私たちは将来、カバレッジを選択的実行で適切に機能させる方法をすでに考えていますので、ご安心ください。


## プル/マージリクエストのコメント {#pullmerge-request-comments}

> [重要】Gitプラットフォームとの統合が必要
> プル/マージリクエストのコメントを自動的に取得するには、<LocalizedLink href="/guides/server/accounts-and-projects">Tuistプロジェクト</LocalizedLink>を<LocalizedLink href="/guides/server/authentication">Gitプラットフォーム</LocalizedLink>と統合してください。｝

Tuistプロジェクトが[GitHub](https://github.com)のようなGitプラットフォームと接続され、`tuist xcodebuild
test` または`tuist test` をCI
wortkflowの一部として使い始めると、Tuistはどのテストが実行され、どのテストがスキップされたかを含むコメントをプル/マージリクエストに直接投稿します:
![GitHub app comment with a Tuist Preview
link](/images/guides/features/selective-testing/github-app-comment.png).
