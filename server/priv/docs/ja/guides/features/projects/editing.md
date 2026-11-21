---
{
  "title": "編集",
  "titleTemplate": ":title · プロジェクト · 機能 · ガイド · Tuist",
  "description": "Xcodeのオートコンプリートとビルド検証を活用して、Tuistプロジェクトのマニフェストを編集します。"
}
---
# 編集 {#editing}

従来のXcodeプロジェクトやSwift PackageではXcodeのUIを通じて変更を行いますが、Tuistで管理されるプロジェクトは**マニフェストファイル**に含まれるSwiftコードで定義されます。Swift Packageと`Package.swift`ファイルに慣れている方なら、このアプローチは非常に似ていると感じるでしょう。

これらのファイルは任意のテキストエディタで編集できますが、Tuistが提供する`tuist edit`ワークフローの使用を推奨します。このワークフローはすべてのマニフェストファイルを含むXcodeプロジェクトを作成し、それらの編集とコンパイルを可能にします。Xcodeを使用することで、**コード補完、シンタックスハイライト、エラーチェック**の恩恵をすべて受けられます。

## プロジェクトを編集する {#edit-the-project}

プロジェクトを編集するには、Tuistプロジェクトのディレクトリまたはそのサブディレクトリで次のコマンドを実行します。

```bash
tuist edit
```

このコマンドはグローバルディレクトリにXcodeプロジェクトを作成し、Xcodeで開きます。プロジェクトには`Manifests`ディレクトリが含まれており、これをビルドしてすべてのマニフェストが有効であることを確認できます。

> [!NOTE]
> **Globで解決されるマニフェスト**
>
> `tuist edit`は、プロジェクトのルートディレクトリ（`Tuist.swift`ファイルを含むディレクトリ）から`**/{Manifest}.swift`グロブパターンを使用して、含めるマニフェストを解決します。プロジェクトのルートに有効な`Tuist.swift`があることを確認してください。


### マニフェストファイルを無視する {#ignoring-manifest-files}

プロジェクトに、実際のTuistマニフェストではないサブディレクトリ内のマニフェストファイルと同じ名前のSwiftファイル（例：`Project.swift`）が含まれている場合、プロジェクトのルートに`.tuistignore`ファイルを作成して、それらを編集用プロジェクトから除外できます。

`.tuistignore`ファイルはグロブパターンを使用して、無視すべきファイルを指定します。

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
