---
title: コードレビュー
titleTemplate: :title - Tuist に貢献する
description: Tuistへの貢献を、コードレビューを通じて学ぶ
---

# コードレビュー

プルリクエストのレビューはよくある貢献の形です。 継続的インテグレーション (CI) によってコードが期待通りに動作することが保証されていても、それだけでは十分ではありません。 設計、コードの構造・アーキテクチャ、テストの品質、タイポなど、自動化できない貢献要素が存在します。 以下の項では、コードレビューのプロセスに関するさまざまな観点を取り上げます。

## 可読性

そのコードは意図を明確に示していますか？ **If you need to spend a bunch of time figuring out what the code does, the code implementation needs to be improved.** Suggest splitting the code into smaller abstractions that are easier to understand. 代替案として、そして最終手段として、レビュイーはコードの背後にある理由を説明するコメントを追加することができます。 プルリクエストの説明などの文脈がなくても、近い将来にそのコードを理解できるかどうか、自分自身に問いかけてみてください。

## 最小単位のプルリクエスト

巨大なプルリクエストはレビューが難しく、詳細を見逃しやすくなります。 プルリクエストが大きくなりすぎて管理が難しくなった場合は、作成者に分割するよう提案してください。

> [!NOTE] 例外
> 変更が密接に結びついていて分割できない場合など、プルリクエストを分割できないケースがいくつかあります。 そのような場合、作成者は変更内容とその理由について明確に説明する必要があります。

## 整合性

変更がプロジェクト全体と整合性を保っていることが重要です。 整合性の欠如はメンテナンスを複雑にするため、避けるべきです。 ユーザーへのメッセージ出力やエラー報告の方法が既に決まっている場合は、それに従うべきです。 もし作成者がプロジェクトの標準に異議を唱えている場合は、議論を深めるために Issue を作成するよう提案してください。

## テスト

テストは、安心してコードを変更できるようにしてくれます。 プルリクエストのコードはすべてテストされ、すべてのテストが通っている必要があります。 良いテストとは、一貫して同じ結果を生み出し、理解しやすく、保守しやすいテストのことです。 レビュワーは実装コードのレビューに多くの時間を費やしますが、テストもコードである以上同様に重要です。

## 破壊的な変更

Breaking changes are a bad user experience for users of Tuist. Contributions should avoid introducing breaking changes unless it’s strictly necessary. There are many language features that we can leverage to evolve the interface of Tuist without resorting to a breaking change. Whether a change is breaking or not might not be obvious. A method to verify whether the change is breaking is running Tuist against the fixture projects in the fixtures directory. It requires putting ourselves in the user’s shoes and imagine how the changes would impact them.
