---
{
  "title": "Editing",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to use Tuist's edit workflow to declare your project leveraging Xcode's build system and editor capabilities."
}
---
# 編集{#editing}

従来のXcodeプロジェクトやSwiftパッケージとは異なり、変更はXcodeのUIではなく、Tuist管理プロジェクトは**マニフェストファイル**
内のSwiftコードで定義されます。Swiftパッケージや`のPackage.swiftファイル` に慣れている方なら、このアプローチは非常に似ています。

これらのファイルは任意のテキストエディタで編集可能ですが、Tuist提供のワークフロー（`tuist edit`
）の使用を推奨します。このワークフローは全マニフェストファイルを含むXcodeプロジェクトを生成し、編集とコンパイルを可能にします。Xcode利用により、**のコード補完・構文強調・エラーチェック機能（**
）を全て活用できます。

## プロジェクトを編集する{#edit-the-project}

プロジェクトを編集するには、Tuistプロジェクトディレクトリまたはサブディレクトリで以下のコマンドを実行できます：

```bash
tuist edit
```

このコマンドはグローバルディレクトリにXcodeプロジェクトを作成し、Xcodeでそれを開きます。プロジェクトには、すべてのマニフェストが有効であることを確認するためにビルドできる「`Manifests」ディレクトリ（`
）が含まれています。

::: info GLOB-RESOLVED MANIFESTS
<!-- -->
`tuist edit` は、プロジェクトのルートディレクトリ（`Tuist.swift`
ファイルを含むディレクトリ）から、グロブ`**/{Manifest}.swift`
を使用して、含めるべきマニフェストを解決します。プロジェクトのルートに有効な`Tuist.swift` が存在することを確認してください。
<!-- -->
:::

### マニフェストファイルを無視する{#ignoring-manifest-files}

プロジェクト内に、マニフェストファイルと同じ名前を持つSwiftファイル（例：`Project.swift`
）が、実際のTuistマニフェストではないサブディレクトリにある場合、プロジェクトのルートに`.tuistignore`
ファイルを作成することで、それらを編集対象から除外できます。

` の.tuistignoreファイル（` ）は、無視すべきファイルを指定するためにグロブパターンを使用します：

```gitignore
# Ignore all Project.swift files in the Sources directory
Sources/**/Project.swift

# Ignore specific subdirectories
Tests/Fixtures/**/Workspace.swift
```

これは、テスト用フィクスチャやサンプルコードがTuistマニフェストファイルと同じ命名規則を使用している場合に特に有用です。

## 編集と生成のワークフロー{#edit-and-generate-workflow}

お気づきかもしれませんが、生成されたXcodeプロジェクトからは編集できません。これは意図的な設計であり、生成されたプロジェクトがTuistに依存しないようにすることで、将来Tuistから移行する際の手間を最小限に抑えるためです。

プロジェクトを反復処理する際は、編集用のXcodeプロジェクトを取得するためにターミナルセッションから`tuist edit`
を実行し、別のターミナルセッションで`tuist generate` を実行することを推奨します。
