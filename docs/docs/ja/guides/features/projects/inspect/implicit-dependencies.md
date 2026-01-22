---
{
  "title": "Implicit imports",
  "titleTemplate": ":title · Inspect · Projects · Features · Guides · Tuist",
  "description": "Learn how to use Tuist to find implicit imports."
}
---
# 暗黙のインポート{#implicit-imports}

Xcodeプロジェクトグラフの複雑な管理を軽減するため、Appleは依存関係を暗黙的に定義できるビルドシステムを設計しました。これにより、アプリなどのプロダクトは、明示的に依存関係を宣言しなくてもフレームワークに依存できます。小規模なプロジェクトでは問題ありませんが、プロジェクトグラフが複雑化するにつれ、この暗黙性が増分ビルドの不確実性や、プレビューやコード補完などのエディタ機能の不安定さとして現れる可能性があります。

問題は、暗黙の依存関係を発生させないようにできないことです。開発者はSwiftコードに`import``や``
`といった文を追加でき、それによって暗黙の依存関係が生成されます。ここでTuistの出番です。Tuistはプロジェクト内のコードを静的に解析し、暗黙の依存関係を検査するコマンドを提供します。以下のコマンドでプロジェクトの暗黙の依存関係を出力できます：

```bash
tuist inspect dependencies --only implicit
```

コマンドが暗黙のインポートを検出した場合、終了コードがゼロ以外で終了します。

::: tip VALIDATE IN CI
<!-- -->
新しいコードがアップストリームにプッシュされるたびに、このコマンドを<LocalizedLink href="/guides/features/automate/continuous-integration">継続的インテグレーション</LocalizedLink>コマンドの一部として実行することを強く推奨します。
<!-- -->
:::

::: warning NOT ALL IMPLICIT CASES ARE DETECTED
<!-- -->
Tuistは静的コード解析に依存して暗黙的な依存関係を検出するため、すべてのケースを捕捉できない可能性があります。例えば、Tuistはコード内のコンパイラ指令による条件付きインポートを理解できません。
<!-- -->
:::
