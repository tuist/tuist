---
{
  "title": "継続的インテグレーション",
  "titleTemplate": ":title · Swift · パッケージレジストリ · 機能 · ガイド · Tuist",
  "description": "Tuist Registry を継続的インテグレーションで活用する方法を学びます。"
}
---
# 継続的インテグレーション (CI) {#continuous-integration-ci}

レジストリは追加の認証設定なしで CI 上でそのまま動作します。デフォルトでは、未認証のリクエストは IP アドレスごとに **毎分 1,000 リクエスト** にレート制限されます。

**毎分 20,000 リクエスト** のより高いレート制限が必要な場合は、`tuist registry login` を実行して認証できます。これには `TUIST_TOKEN` 環境変数の設定が必要です。プロジェクトトークンは、ドキュメント <.localized_link href="/guides/server/authentication#as-a-project">こちら</.localized_link> の手順に従って作成できます。

> [!NOTE]
> 以下のキーチェーン設定は、`tuist registry login` を使用してより高いレート制限を取得する場合にのみ必要です。ほとんどの場合、デフォルトの未認証レート制限で十分であり、この手順は完全に省略できます。
>
> さらに、事前にロック解除された新しいキーチェーンの作成は、パッケージの Xcode 統合を使用する場合にのみ必要です。


`tuist registry login` は認証情報をキーチェーンに保存するため、CI 環境でキーチェーンにアクセスできるようにする必要があります。一部の CI プロバイダーや [Fastlane](https://fastlane.tools/) のような自動化ツールは、一時的なキーチェーンをすでに作成するか、作成するための組み込み方法を提供している点に注意してください。ただし、以下のコードを使用してカスタムステップを作成することで、キーチェーンを手動で作成することもできます。
```bash
TMP_DIRECTORY=$(mktemp -d)
KEYCHAIN_PATH=$TMP_DIRECTORY/keychain.keychain
KEYCHAIN_PASSWORD=$(uuidgen)
security create-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
security set-keychain-settings -lut 21600 $KEYCHAIN_PATH
security default-keychain -s $KEYCHAIN_PATH
security unlock-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
```

`tuist registry login` を実行する _前に_ 、デフォルトのキーチェーンが作成され、ロック解除されていることを確認してください。

### 環境をまたいだ増分解決 {#incremental-resolution-across-environments}

当社のレジストリを使用すると、クリーン/コールドな解決がわずかに高速化され、CI ビルド間で解決済みの依存関係を永続化すれば、さらに大きな改善が見込めます。レジストリのおかげで、保存および復元する必要のあるディレクトリのサイズは、レジストリを使用しない場合よりもはるかに小さくなり、所要時間も大幅に短縮されます。デフォルトの Xcode パッケージ統合を使用する際に依存関係をキャッシュする最適な方法は、`xcodebuild` で依存関係を解決するときにカスタムの `clonedSourcePackagesDirPath` を指定することです。これは、`Config.swift` ファイルに以下を追加することで実現できます。

```swift
import ProjectDescription

let config = Config(
    generationOptions: .options(
        additionalPackageResolutionArguments: ["-clonedSourcePackagesDirPath", ".build"]
    )
)
```

さらに、`Package.resolved` のパスを見つける必要があります。`ls **/Package.resolved` を実行してパスを取得できます。パスは `App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` のような形式になります。

Swift パッケージおよび XcodeProj ベースの統合の場合、プロジェクトのルートまたは `Tuist` ディレクトリにあるデフォルトの `.build` ディレクトリを使用できます。パイプラインを設定する際に、パスが正しいことを確認してください。

デフォルトの Xcode パッケージ統合を使用する際に依存関係を解決およびキャッシュするための GitHub Actions ワークフローの例を次に示します。
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
