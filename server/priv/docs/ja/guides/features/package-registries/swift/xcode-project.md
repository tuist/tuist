---
{
  "title": "Xcode プロジェクト",
  "titleTemplate": ":title · Swift · Package Registries · Features · Guides · Tuist",
  "description": "Xcode プロジェクトで Tuist Registry を使用する方法を学びます。"
}
---
# Xcode プロジェクト {#xcode-project}

Xcode プロジェクトでレジストリを使用してパッケージを追加するには、デフォルトの Xcode UI を使用します。Xcode の `Package Dependencies` タブにある `+` ボタンをクリックすると、レジストリ内のパッケージを検索できます。パッケージがレジストリで利用可能な場合、右上に `tuist.dev` レジストリが表示されます。

![パッケージ依存関係の追加](/images/guides/features/build/registry/registry-add-package.png)

## ソースコントロールパッケージの解決 {#resolving-source-control-packages}

追加したパッケージの推移的な依存関係など、ソースコントロール URL で宣言されたパッケージは、デフォルトではソースコントロールから解決されます。`tuist registry setup` は、以下のユーザーデフォルトを設定することで、代わりにレジストリからそれらを解決するように Xcode を構成します。

```bash
defaults write com.apple.dt.Xcode IDEPackageDependencySCMToRegistryTransformation useRegistryIdentityAndSources
```

その後、Xcode はレジストリに同等のパッケージが存在する場合はそこからソースコントロールパッケージを解決し、存在しない場合はソースコントロールにフォールバックします。

> [!NOTE]
> これはプロジェクト設定ではなくマシンごとの Xcode 設定であるため、レジストリ設定ファイルをコミットしてもチームの他のメンバーと共有されません。各開発者は自分のマシンで `tuist registry setup` を一度実行する必要があります。この設定は、そのマシンのすべての Xcode プロジェクトに適用されます。
