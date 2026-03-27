---
{
  "title": "Continuous integration",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in continuous integration."
}
---
# 継続的インテグレーション（CI）{#continuous-integration-ci}

CIでレジストリを使用するには、ワークフローの一環として`tuist registry login`
を実行して、レジストリにログインしていることを確認する必要がある。

::: info ONLY XCODE INTEGRATION
<!-- -->
新しいプレアンロックキーチェーンの作成は、パッケージのXcode統合を使用している場合にのみ必要です。
<!-- -->
:::

レジストリの認証情報はキーチェーンに保存されるので、CI環境でキーチェーンにアクセスできるようにする必要がある。Fastlane](https://fastlane.tools/)のようなCIプロバイダや自動化ツールは、既に一時的なキーチェーンを作成しているか、作成方法をビルトインしている。しかし、以下のコードでカスタムステップを作成することで作成することもできます：
```bash
TMP_DIRECTORY=$(mktemp -d)
KEYCHAIN_PATH=$TMP_DIRECTORY/keychain.keychain
KEYCHAIN_PASSWORD=$(uuidgen)
security create-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
security set-keychain-settings -lut 21600 $KEYCHAIN_PATH
security default-keychain -s $KEYCHAIN_PATH
security unlock-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
```

`tuist registry login` を実行すると、認証情報がデフォルトのキーチェーンに保存されます。__ `tuist registry login`
を実行する前に、デフォルトのキーチェーンが作成され、ロックが解除されていることを確認してください。

さらに、`TUIST_TOKEN`
環境変数が設定されていることを確認する必要があります。こちらのドキュメント<LocalizedLink href="/guides/server/authentication#as-a-project"></LocalizedLink>に従って作成してください。

GitHub Actions のワークフローの例は次のようになります：
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

### 環境を超えたインクリメンタルな解決{#incremental-resolution-across-environments}

レジストリを使用することで、クリーン/コールドの解決がわずかに速くなり、解決した依存関係をCIビルド間で永続化すると、さらに大きな改善を体験できます。レジストリのおかげで、保存してリストアする必要があるディレクトリのサイズは、レジストリを使用しない場合よりもはるかに小さく、大幅に時間がかからないことに注意してください。デフォルトの
Xcode パッケージ統合を使用するときに依存関係をキャッシュするために、最良の方法は、`xcodebuild`
を介して依存関係を解決するときに、カスタム`clonedSourcePackagesDirPath` を指定することです。これは、`Config.swift`
ファイルに以下を追加することで実行できます：

```swift
import ProjectDescription

let config = Config(
    generationOptions: .options(
        additionalPackageResolutionArguments: ["-clonedSourcePackagesDirPath", ".build"]
    )
)
```

さらに、`Package.resolved` のパスを見つける必要がある。`ls **/Package.resolved`
を実行することでパスを取得できます。パスは`App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
のようになるはずです。

Swift パッケージと XcodeProj ベースの統合のために、プロジェクトのルートか`Tuist` ディレクトリにあるデフォルトの`.build`
ディレクトリを使用することができます。パイプラインをセットアップする際に、パスが正しいことを確認してください。

以下は、デフォルトの Xcode パッケージ統合を使用するときに、依存関係を解決してキャッシュするための GitHub Actions のワークフロー例です：
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
