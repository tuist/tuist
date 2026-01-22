---
{
  "title": "Continuous integration",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in continuous integration."
}
---
# 継続的インテグレーション (CI){#continuous-integration-ci}

CIでレジストリを使用するには、ワークフローの一環として`tuist registry login`
を実行し、レジストリにログインしていることを確認する必要があります。

::: info ONLY XCODE INTEGRATION
<!-- -->
パッケージのXcode統合を使用している場合のみ、新しい事前アンロック済みキーチェーンの作成が必要です。
<!-- -->
:::

レジストリ認証情報はキーチェーンに保存されるため、CI環境でキーチェーンにアクセスできることを確認する必要があります。一部のCIプロバイダーや[Fastlane](https://fastlane.tools/)などの自動化ツールは、一時的なキーチェーンを作成するか、キーチェーン作成の組み込み方法を提供しています。ただし、以下のコードでカスタムステップを作成することで、キーチェーンを独自に作成することも可能です：
```bash
TMP_DIRECTORY=$(mktemp -d)
KEYCHAIN_PATH=$TMP_DIRECTORY/keychain.keychain
KEYCHAIN_PASSWORD=$(uuidgen)
security create-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
security set-keychain-settings -lut 21600 $KEYCHAIN_PATH
security default-keychain -s $KEYCHAIN_PATH
security unlock-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
```

`_ `tuist registry login` を実行すると、認証情報がデフォルトのキーチェーンに保存されます。tuist registry login`
を実行する前に、デフォルトのキーチェーンが作成されロック解除されていることを確認してください。_

さらに、`TUIST_TOKEN`
の環境変数が設定されていることを確認する必要があります。設定方法については、<LocalizedLink href="/guides/server/authentication#as-a-project">こちらの</LocalizedLink>ドキュメントを参照してください。

GitHub Actionsのワークフロー例は以下のようになります：
```yaml
name: Build

jobs:
  build:
    steps:
      - # Your set up steps...
      - name: Create keychain
        run: |
        TMP_DIRECTORY=$(mktemp -d)
        KEYCHAIN_PATH=$TMP_DIRECTORY/keychain.keychain
        KEYCHAIN_PASSWORD=$(uuidgen)
        security create-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
        security set-keychain-settings -lut 21600 $KEYCHAIN_PATH
        security default-keychain -s $KEYCHAIN_PATH
        security unlock-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
      - name: Log in to the Tuist Registry
        env:
          TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}
        run: tuist registry login
      - # Your build steps
```

### 環境をまたいだ段階的な解決{#incremental-resolution-across-environments}

クリーン/コールド解決は当社のレジストリ使用時により高速化され、CIビルド間で解決済み依存関係を永続化すればさらなる改善が期待できます。レジストリ利用により、保存・復元が必要なディレクトリサイズが大幅に縮小され、処理時間が大幅に短縮される点にご留意ください。
デフォルトのXcodeパッケージ統合で依存関係をキャッシュする最良の方法は、`xcodebuild`
経由で依存関係を解決する際、カスタム`clonedSourcePackagesDirPath` を指定することです。これは`Config.swift`
ファイルに以下を追加することで実現できます：

```swift
import ProjectDescription

let config = Config(
    generationOptions: .options(
        additionalPackageResolutionArguments: ["-clonedSourcePackagesDirPath", ".build"]
    )
)
```

さらに、`パッケージのresolvedファイルのパスを見つける必要があります。` 。パスは`ls **/Package.resolved`
を実行して取得できます。パスは`App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
のような形式になります。

SwiftパッケージおよびXcodeProjベースの統合では、プロジェクトルートまたは`Tuist` ディレクトリ内のデフォルトの`.build`
ディレクトリを使用できます。パイプライン設定時にはパスが正しいことを確認してください。

デフォルトのXcodeパッケージ統合を使用する場合の依存関係解決とキャッシュ処理のためのGitHub Actionsワークフロー例：
```yaml
- name: Restore cache
  id: cache-restore
  uses: actions/cache/restore@v4
  with:
    path: .build
    key: ${{ runner.os }}-${{ hashFiles('App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved') }}
- name: Resolve dependencies
  if: steps.cache-restore.outputs.cache-hit != 'true'
  run: xcodebuild -resolvePackageDependencies -clonedSourcePackagesDirPath .build
- name: Save cache
  id: cache-save
  uses: actions/cache/save@v4
  with:
    path: .build
    key: ${{ steps.cache-restore.outputs.cache-primary-key }}
```
