---
{
  "title": "CLI",
  "titleTemplate": ":title · コード · 貢献者 · Tuist",
  "description": "Tuist CLIに貢献する。"
}
---
# CLI {#cli}

ソース: [github.com/tuist/tuist/tree/main/Tuist](https://github.com/tuist/tuist/tree/main/Tuist) および [github.com/tuist/tuist/tree/main/cli](https://github.com/tuist/tuist/tree/main/cli)

## 用途 {#what-it-is-for}

CLI は Tuist の中心です。プロジェクトの生成、自動化ワークフロー（テスト、実行、グラフ、検査）を処理し、認証、キャッシュ、インサイト、プレビュー、レジストリ、選択的テストなどの機能のために Tuist サーバーへのインターフェースを提供します。

## 貢献方法 {#how-to-contribute}

### 要件 {#requirements}

- macOS 14.0+
- Xcode 26+

### ローカル環境のセットアップ {#set-up-locally}

- リポジトリのクローン: `git clone git@github.com:tuist/tuist.git`
- [Mise の公式インストールスクリプト](https://mise.jdx.dev/getting-started.html)（Homebrew ではなく）を使用して Mise をインストールし、`mise install` を実行
- Tuist の依存関係をインストール: `tuist install`
- ワークスペースを生成: `tuist generate`

生成されたプロジェクトは自動的に開きます。後で再度開く必要がある場合は、`open Tuist.xcworkspace` を実行してください。

> [!NOTE]
> **Xed .**
>
> `xed .` を使用してプロジェクトを開こうとすると、Tuist が生成したワークスペースではなくパッケージが開きます。`Tuist.xcworkspace` を使用してください。


### Tuist の実行 {#run-tuist}

#### Xcode から {#from-xcode}

`tuist` スキームを編集し、`generate --no-open` などの引数を設定します。作業ディレクトリをプロジェクトルートに設定するか（または `--path` を使用）、

> [!WARNING]
> **ProjectDescription のコンパイル**
>
> CLI は `ProjectDescription` のビルドに依存しています。実行に失敗する場合は、まず `Tuist-Workspace` スキームをビルドしてください。


#### ターミナルから {#from-the-terminal}

まずワークスペースを生成します:

```bash
tuist generate --no-open
```

次に Xcode で `tuist` 実行可能ファイルをビルドし、DerivedData から実行します:

```bash
tuist_build_dir="$(xcodebuild -workspace Tuist.xcworkspace -scheme tuist -configuration Debug -destination 'platform=macOS' -showBuildSettings | awk -F' = ' '/BUILT_PRODUCTS_DIR/{print $2; exit}')"

"$tuist_build_dir/tuist" generate --path /path/to/project --no-open
```

または Swift Package Manager を使用:

```bash
swift build --product ProjectDescription
swift run tuist generate --path /path/to/project --no-open
```
