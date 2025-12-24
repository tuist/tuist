---
{
  "title": "Xcode project",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in an Xcode project."
}
---
# Xcodeプロジェクト{#xcode-project}

Xcode プロジェクトでレジストリを使用してパッケージを追加するには、デフォルトの Xcode UI を使用します。Xcode の`Package
Dependencies` タブの`+`
ボタンをクリックすると、レジストリでパッケージを検索できます。パッケージがレジストリで利用可能な場合、右上に`tuist.dev` レジストリが表示されます：

パッケージの依存関係の追加](/images/guides/features/build/registry/registry-add-package.png)。

::: info
<!-- -->
現在、Xcode
は、ソースコントロールパッケージをレジストリの同等物と自動的に置き換えることをサポートしていません。あなたは、手動でソースコントロールパッケージを削除し、解決をスピードアップするためにレジストリパッケージを追加する必要があります。
<!-- -->
:::
