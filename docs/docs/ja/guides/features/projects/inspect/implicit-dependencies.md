---
{
  "title": "Implicit imports",
  "titleTemplate": ":title · Inspect · Projects · Features · Guides · Tuist",
  "description": "Learn how to use Tuist to find implicit imports."
}
---
# 暗黙のインポート{#implicit-imports}

生のXcodeプロジェクトを用いたXcodeプロジェクトグラフのメンテナンスの複雑さを軽減するため、Appleは依存関係を暗黙的に定義できるようなビルドシステムを設計しました。つまり、アプリなどのプロダクトは、依存関係を明示的に宣言しなくても、フレームワークに依存することができます。小規模なプロジェクトであれば問題ありませんが、プロジェクトグラフが複雑になるにつれて、この暗黙的な定義が、信頼性の低いインクリメンタルビルドや、プレビューやコード補完などのエディタベースの機能に悪影響を及ぼす可能性があります。

問題は、暗黙の依存関係が発生するのを防ぐことができない点です。開発者は誰でも、Swiftコードに ``` や `` `
といったインポート文を追加することができ、それによって暗黙の依存関係が生成されてしまいます。そこでTuistの出番です。Tuistには、プロジェクト内のコードを静的に解析して暗黙の依存関係を調査するコマンドが用意されています。以下のコマンドを実行すると、プロジェクトの暗黙の依存関係が表示されます：

```bash
tuist inspect dependencies --only implicit
```

コマンドが暗黙のインポートを検出した場合、0以外の終了コードで終了します。

::: tip VALIDATE IN CI
<!-- -->
新しいコードがアップストリームにプッシュされるたびに、このコマンドを<LocalizedLink href="/guides/features/automate/continuous-integration">継続的インテグレーション</LocalizedLink>コマンドの一部として実行することを強く推奨します。
<!-- -->
:::

::: warning NOT ALL IMPLICIT CASES ARE DETECTED
<!-- -->
Tuistは静的コード解析を利用して暗黙の依存関係を検出するため、すべてのケースを検出できるとは限りません。例えば、Tuistはコード内のコンパイラ指令による条件付きインポートを理解することができません。
<!-- -->
:::
