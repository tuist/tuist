---
{
  "title": "編集",
  "titleTemplate": ":title · プロジェクト · 機能 · ガイド · Tuist",
  "description": "Xcode のオートコンプリートとビルド検証を活用して、Tuist プロジェクトのマニフェストを編集します。"
}
---
# 編集 {#editing}

XcodeのUIを通じて変更を行う従来のXcodeプロジェクトやSwift Packageとは異なり、Tuistで管理されるプロジェクトは**マニフェストファイル**に含まれるSwiftコードで定義されます。Swift Packageと`Package.swift`ファイルに慣れている場合、このアプローチは非常に似ています。

これらのファイルは任意のテキストエディタで編集できますが、Tuistが提供するワークフローである`tuist edit`を使用することを推奨します。このワークフローはすべてのマニフェストファイルを含むXcodeプロジェクトを作成し、それらの編集とコンパイルを可能にします。Xcodeを使用することで、**コード補完、シンタックスハイライト、エラーチェック**のすべての恩恵を受けられます。

## プロジェクトの編集 {#edit-the-project}

プロジェクトを編集するには、Tuistプロジェクトのディレクトリまたはサブディレクトリで次のコマンドを実行します。

```bash
tuist edit
```

このコマンドはグローバルディレクトリにXcodeプロジェクトを作成し、Xcodeで開きます。プロジェクトには`Manifests`ディレクトリが含まれており、これをビルドしてすべてのマニフェストが有効であることを確認できます。

> [!NOTE]
> **Globで解決されたマニフェスト**
>
> `tuist edit`は、プロジェクトのルートディレクトリ（`Tuist.swift`ファイルを含むディレクトリ）から`**/{Manifest}.swift`というglobパターンを使用して、含めるべきマニフェストを解決します。プロジェクトのルートに有効な`Tuist.swift`があることを確認してください。


### マニフェストファイルの除外 {#ignoring-manifest-files}

プロジェクトに、実際のTuistマニフェストではないサブディレクトリ内にマニフェストファイルと同じ名前（例：`Project.swift`）のSwiftファイルが含まれている場合、プロジェクトのルートに`.tuistignore`ファイルを作成して、それらを編集用プロジェクトから除外できます。

`.tuistignore`ファイルは、どのファイルを無視するかを指定するためにglobパターンを使用します。

```gitignore
# Ignore all Project.swift files in the Sources directory
Sources/**/Project.swift

# Ignore specific subdirectories
Tests/Fixtures/**/Workspace.swift
```

これは、テストフィクスチャやサンプルコードがTuistマニフェストファイルと同じ命名規則を使用している場合に特に便利です。

## 編集と生成のワークフロー {#edit-and-generate-workflow}

お気づきかもしれませんが、編集は生成されたXcodeプロジェクトからは行えません。これは、生成されたプロジェクトがTuistに依存しないようにするための設計であり、将来的にTuistからの移行を容易にするためです。

プロジェクトを反復開発する際は、ターミナルセッションで`tuist edit`を実行してプロジェクトを編集するためのXcodeプロジェクトを取得し、別のターミナルセッションで`tuist generate`を実行することを推奨します。
