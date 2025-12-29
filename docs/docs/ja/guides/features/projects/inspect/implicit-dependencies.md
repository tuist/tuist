---
{
  "title": "Implicit imports",
  "titleTemplate": ":title · Inspect · Projects · Features · Guides · Tuist",
  "description": "Learn how to use Tuist to find implicit imports."
}
---
# 暗黙の輸入{#implicit-imports}

生のXcodeプロジェクトでXcodeプロジェクトグラフを維持する複雑さを軽減するために、Appleは依存関係を暗黙的に定義できるようにビルドシステムを設計した。これは、ある製品、例えばアプリが、明示的に依存関係を宣言しなくても、フレームワークに依存できることを意味する。小規模であれば、これは問題ないが、プロジェクトグラフが複雑になるにつれて、暗黙的な依存関係は、信頼できないインクリメンタルビルドや、プレビューやコード補完のようなエディタベースの機能として現れるかもしれない。

問題は、暗黙の依存関係が起こるのを防ぐことができないということだ。どんな開発者でも、Swiftのコードに`import`
ステートメントを追加することができ、暗黙の依存関係が作られてしまう。そこでTuistの出番だ。Tuistは、プロジェクト内のコードを静的に分析することで、暗黙の依存関係を検査するコマンドを提供します。以下のコマンドは、あなたのプロジェクトの暗黙の依存関係を出力する：

```bash
tuist inspect implicit-imports
```

コマンドが暗黙のインポートを検出した場合、0以外の終了コードで終了する。

::: tip VALIDATE IN CI
<!-- -->
新しいコードがアップストリームにプッシュされるたびに、<LocalizedLink href="/guides/features/automate/continuous-integration">継続的インテグレーション</LocalizedLink>コマンドの一部としてこのコマンドを実行することを強く推奨する。
<!-- -->
:::

::: warning NOT ALL IMPLICIT CASES ARE DETECTED
<!-- -->
Tuistは暗黙の依存関係を検出するために静的コード解析に依存しているため、すべてのケースを検出できるわけではない。例えば、Tuistはコード中のコンパイラ指令による条件付きインポートを理解することができない。
<!-- -->
:::
