---
{
  "title": "Xcode project",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in an Xcode project."
}
---
# Xcodeプロジェクト{#xcode-project}

Xcodeプロジェクトでレジストリを使用してパッケージを追加するには、デフォルトのXcode UIを使用します。Xcodeの「`」→「Package
Dependencies」→「` 」タブにある「` 」+「`
」ボタンをクリックすると、レジストリ内のパッケージを検索できます。レジストリにパッケージが存在する場合、右上に「`」tuist.dev`
レジストリが表示されます：

![パッケージ依存関係の追加](/images/guides/features/build/registry/registry-add-package.png)

::: info
<!-- -->
Xcodeは現在、ソース管理パッケージをレジストリ対応パッケージに自動置換する機能をサポートしていません。解決を早めるには、ソース管理パッケージを手動で削除し、レジストリパッケージを追加する必要があります。
<!-- -->
:::
