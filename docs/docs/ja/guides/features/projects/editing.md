---
{
  "title": "Editing",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to use Tuist's edit workflow to declare your project leveraging Xcode's build system and editor capabilities."
}
---
# 編集{#editing}

変更がXcodeのUIを通して行われる従来のXcodeプロジェクトやSwiftパッケージとは異なり、Tuist管理プロジェクトは、**マニフェストファイル**
に含まれるSwiftコードで定義されます。もしあなたがSwift Packagesと`Package.swift`
ファイルに精通しているなら、アプローチは非常に似ています。

任意のテキストエディタを使用してこれらのファイルを編集することができますが、私たちはそのためにTuist-providedワークフロー、`tuist edit`
を使用することをお勧めします。このワークフローは、すべてのマニフェスト・ファイルを含むXcodeプロジェクトを作成し、それらの編集とコンパイルを可能にします。Xcodeを使用するおかげで、**コード補完、シンタックスハイライト、エラーチェックのすべての利点を得ることができます**
。

## プロジェクトの編集{#edit-the-project}

プロジェクトを編集するには、Tuistプロジェクトのディレクトリまたはサブディレクトリで次のコマンドを実行します：

```bash
tuist edit
```

コマンドは、グローバルディレクトリに Xcode プロジェクトを作成し、Xcode
で開きます。プロジェクトには、すべてのマニフェストが有効であることを確認するためにビルドできる`Manifests` ディレクトリが含まれています。

::: info GLOB-RESOLVED MANIFESTS
<!-- -->
`tuist edit` は、プロジェクトのルート・ディレクトリ（`Tuist.swift`
ファイルを含むディレクトリ）から`**/{Manifest}.swift`
というグロブを使用して、インクルードするマニフェストを解決します。プロジェクトのルートに有効な`Tuist.swift` があることを確認してください。
<!-- -->
:::

### マニフェストファイルの無視{#ignoring-manifest-files}

あなたのプロジェクトに、実際の Tuist マニフェストではない、マニフェストファイルと同じ名前の Swift ファイル（例:`Project.swift`
）がサブディレクトリに含まれている場合、`.tuistignore` ファイルをプロジェクトのルートに作成し、編集プロジェクトから除外することができます。

`.tuistignore` ファイルは、グロブパターンを使用して、無視するファイルを指定します：

```gitignore
# Ignore all Project.swift files in the Sources directory
Sources/**/Project.swift

# Ignore specific subdirectories
Tests/Fixtures/**/Workspace.swift
```

これは、Tuistマニフェストファイルと同じ命名規則を使用するテストフィクスチャやサンプルコードがある場合に特に便利です。

## ワークフローの編集と生成{#edit-and-generate-workflow}

お気づきかもしれないが、編集は生成されたXcodeプロジェクトからはできない。これは生成されたプロジェクトがTuistに依存しないようにするための設計であり、将来Tuistから移行する際に労力をかけずに移行できるようにするためである。

プロジェクトを反復するときは、Xcode プロジェクトを編集するために、ターミナルセッションから`tuist edit`
を実行し、別のターミナルセッションを使って`tuist generate` を実行することを推奨します。
