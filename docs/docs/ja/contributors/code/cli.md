---
{
  "title": "CLI",
  "titleTemplate": ":title · Code · Contributors · Tuist",
  "description": "Contribute to the Tuist CLI."
}
---
# CLI{#cli}

ソース:
[github.com/tuist/tuist/tree/main/Tuist](https://github.com/tuist/tuist/tree/main/Tuist)
および
[github.com/tuist/tuist/tree/main/cli](https://github.com/tuist/tuist/tree/main/cli)

## 目的{#what-it-is-for}

CLIはTuistの中核です。プロジェクト生成、自動化ワークフロー（テスト、実行、グラフ化、検査）を処理し、認証、キャッシュ、インサイト、プレビュー、レジストリ、選択的テストなどの機能向けにTuistサーバーへのインターフェースを提供します。

## 貢献方法{#how-to-contribute}

### 要件{#requirements}

- macOS 14.0以降
- Xcode 26+

### ローカルに設定する{#set-up-locally}

- リポジトリをクローン:`git clone git@github.com:tuist/tuist.git`
- Miseは[公式インストールスクリプト](https://mise.jdx.dev/getting-started.html)（Homebrewではない）を使用してインストールし、`mise
  installを実行してください`
- Tuistの依存関係をインストール:`tuist install`
- ワークスペースを生成:`tuist generate`

生成されたプロジェクトは自動的に開きます。後で再度開く必要がある場合は、`open Tuist.xcworkspace` を実行してください。

::: info XED .
<!-- -->
`xed .` でプロジェクトを開こうとすると、Tuistが生成したワークスペースではなくパッケージが開きます。`Tuist.xcworkspace`
を使用してください。
<!-- -->
:::

### Tuistを実行{#run-tuist}

#### Xcodeより{#from-xcode}

`tuist` スキームを編集し、`generate --no-open`
のような引数を設定します。作業ディレクトリをプロジェクトルートに設定するか（または`--path` を使用）、

::: warning PROJECTDESCRIPTION COMPILATION
<!-- -->
CLIは`ProjectDescription` のビルドに依存します。実行に失敗した場合は、まず`Tuist-Workspace`
schemeをビルドしてください。
<!-- -->
:::

#### ターミナルから{#from-the-terminal}

まずワークスペースを生成します：

```bash
tuist generate --no-open
```

次に、`tuist` 実行ファイルをXcodeでビルドし、DerivedDataから実行します：

```bash
tuist_build_dir="$(xcodebuild -workspace Tuist.xcworkspace -scheme tuist -configuration Debug -destination 'platform=macOS' -showBuildSettings | awk -F' = ' '/BUILT_PRODUCTS_DIR/{print $2; exit}')"

"$tuist_build_dir/tuist" generate --path /path/to/project --no-open
```

またはSwift Package Manager経由で:

```bash
swift build --product ProjectDescription
swift run tuist generate --path /path/to/project --no-open
```
