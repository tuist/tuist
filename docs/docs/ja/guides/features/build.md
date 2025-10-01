---
{
  "title": "Build",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Learn how to use Tuist to build your projects efficiently."
}
---
# ビルド {#build}

プロジェクトは通常、ビルドシステムが提供するCLI（例：`xcodebuild`
）を通じてビルドされる。Tuistは、ユーザーエクスペリエンスを向上させ、ワークフローをプラットフォームと統合して最適化と分析を提供するために、それらをラップする。

`tuist generate` (必要であれば)でプロジェクトを生成し、プラットフォーム固有のCLIでビルドするよりも、`tuist build`
を使うことに何の価値があるのだろうと思うかもしれない。以下はその理由です：

- **単一コマンド：** `tuist build` プロジェクトをコンパイルする前に、必要であればプロジェクトが生成されるようにします。
- **美化された出力：**
  Tuistは[xcbeautify](https://github.com/cpisciotta/xcbeautify)のようなツールを使って出力をよりユーザーフレンドリーにする。
- <LocalizedLink href="/guides/features/cache"><bold>キャッシュ：</bold></LocalizedLink>リモートキャッシュからビルドアーティファクトを決定論的に再利用することで、ビルドを最適化します。
- **アナリティクス：** 他のデータポイントとの相関関係を持つ測定基準を収集・報告し、十分な情報に基づいた意思決定を行うための実用的な情報を提供します。

## 使用法 {#usage}

`tuist build` 必要に応じてプロジェクトを生成し、プラットフォーム固有のビルド・ツールを使ってビルドする。`--`
のターミネータを使用して、後続のすべての引数を基本ビルド・ツールに直接転送することをサポートします。これは、`tuist build`
ではサポートされていないが、基本的なビルド・ツールではサポートされている引数を渡す必要がある場合に便利です。

コードグループ
```bash [Build a scheme]
tuist build MyScheme
```
```bash [Build a specific configuration]
tuist build MyScheme -- -configuration Debug
```
```bash [Build all schemes without binary cache]
tuist build --no-binary-cache
```
:::
