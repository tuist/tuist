---
{
  "title": "編集",
  "titleTemplate": ":title · プロジェクト · 機能 · ガイド · Tuist",
  "description": "Xcodeのオートコンプリートとビルド検証を活用して、Tuistプロジェクトのマニフェストを編集します。"
}
---
# 編集 {#editing}

従来の Xcode プロジェクトや Swift Package では Xcode の UI を通じて変更を行いますが、Tuist で管理するプロジェクトは **マニフェストファイル** に含まれる Swift コードで定義します。Swift Package と `Package.swift` ファイルに慣れている方であれば、このアプローチは非常に似ていると感じるでしょう。

これらのファイルは任意のテキストエディタで編集できますが、Tuist が提供する `tuist edit` ワークフローの利用を推奨します。このワークフローはすべてのマニフェストファイルを含む Xcode プロジェクトを作成し、編集とコンパイルを可能にします。Xcode を使用することで、**コード補完、シンタックスハイライト、エラーチェック** の恩恵をすべて受けられます。

## プロジェクトを編集する {#edit-the-project}

プロジェクトを編集するには、Tuist プロジェクトのディレクトリまたはそのサブディレクトリで次のコマンドを実行します。

```bash
tuist edit
```

このコマンドはグローバルディレクトリに Xcode プロジェクトを作成し、Xcode で開きます。プロジェクトには `Manifests` ディレクトリが含まれており、これをビルドしてすべてのマニフェストが有効であることを確認できます。

> [!NOTE]
> **Glob で解決されるマニフェスト**
>
> `tuist edit` は、プロジェクトのルートディレクトリ（`Tuist.swift` ファイルを含むディレクトリ）から `**/{Manifest}.swift` という glob パターンを使用して、含めるべきマニフェストを解決します。プロジェクトのルートに有効な `Tuist.swift` があることを確認してください。


### マニフェストファイルを無視する {#ignoring-manifest-files}

プロジェクト内に、実際の Tuist マニフェストではないサブディレクトリにマニフェストファイルと同じ名前の Swift ファイル（例：`Project.swift`）が含まれている場合、プロジェクトのルートに `.tuistignore` ファイルを作成して、それらを編集用プロジェクトから除外できます。

`.tuistignore` ファイルは glob パターンを使用して、無視すべきファイルを指定します。

```gitignore
# Ignore all Project.swift files in the Sources directory
Sources/**/Project.swift

# Ignore specific subdirectories
Tests/Fixtures/**/Workspace.swift
```

これは、テストフィクスチャやサンプルコードが Tuist マニフェストファイルと同じ命名規則を使用している場合に特に便利です。

## 編集と生成のワークフロー {#edit-and-generate-workflow}

お気づきかもしれませんが、編集は生成された Xcode プロジェクトからは行えません。これは、生成されたプロジェクトが Tuist に依存しないようにするための設計であり、将来的に Tuist から移行する際の手間を最小限に抑えるためです。

プロジェクトの開発を繰り返す際は、ターミナルセッションで `tuist edit` を実行して編集用の Xcode プロジェクトを取得し、別のターミナルセッションで `tuist generate` を実行することを推奨します。
