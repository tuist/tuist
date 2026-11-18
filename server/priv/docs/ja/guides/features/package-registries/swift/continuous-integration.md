---
{
  "title": "継続的インテグレーション",
  "titleTemplate": ":title · Swift · Package Registries · Features · Guides · Tuist",
  "description": "継続的インテグレーションでTuist Registryを使用する方法を学びます。"
}
---
# 継続的インテグレーション (CI) {#continuous-integration-ci}

レジストリは、追加の認証設定なしで CI 上でそのまま動作します。デフォルトでは、認証されていないリクエストは IP アドレスあたり **1 分間に 1,000 リクエスト** にレート制限されます。

**1 分間に 20,000 リクエスト** のより高いレート制限が必要な場合は、`tuist registry login` を実行して認証できます。これには、`TUIST_TOKEN` 環境変数を設定する必要があります。アカウントトークンは、<.localized_link href="/guides/server/authentication#account-tokens">認証ガイド</.localized_link> に従って作成できます。

> [!NOTE]
> 以下のキーチェーン設定は、より高いレート制限を得るために `tuist registry login` を使用する場合にのみ必要です。ほとんどの場合、デフォルトの認証なしのレート制限で十分であり、この手順を完全に省略できます。
>
> さらに、事前にロック解除された新しいキーチェーンを作成するのは、パッケージの Xcode 統合を使用する場合にのみ必要です。


`tuist registry login`はキーチェーンに認証情報を保存するため、CI環境でキーチェーンにアクセスできることを確認する必要があります。なお、[Fastlane](https://fastlane.tools/)などの一部のCIプロバイダーや自動化ツールは、すでに一時キーチェーンを作成するか、作成するための組み込み方法を提供しています。ただし、以下のコードを使用してカスタムステップを作成することで、キーチェーンを自分で作成することもできます。
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

## 環境をまたいだ増分的な依存関係解決 {#incremental-resolution-across-environments}

当社のレジストリを使用すると、クリーン/コールドな依存関係解決がわずかに高速化され、CI ビルド間で解決済みの依存関係を保持すれば、さらに大きな改善が見込めます。レジストリのおかげで、保存および復元が必要なディレクトリのサイズは、レジストリなしの場合よりもはるかに小さくなり、所要時間も大幅に短縮されます。デフォルトの Xcode パッケージ統合を使用する際に依存関係をキャッシュするには、`xcodebuild` で依存関係を解決するときにカスタムの `clonedSourcePackagesDirPath` を指定するのが最適です。これは、`Tuist.swift` ファイルに以下を追加することで実現できます。

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(
        generationOptions: .options(
            additionalPackageResolutionArguments: ["-clonedSourcePackagesDirPath", ".build"]
        )
    )
)
```

さらに、`Package.resolved` のパスを見つける必要があります。`ls **/Package.resolved` を実行してパスを取得できます。パスは `App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` のようになります。

Swift パッケージと XcodeProj ベースの統合の場合、プロジェクトのルートまたは `Tuist` ディレクトリにあるデフォルトの `.build` ディレクトリを使用できます。パイプラインを設定する際に、パスが正しいことを確認してください。

デフォルトの Xcode パッケージ統合を使用する際に、依存関係を解決してキャッシュするための GitHub Actions ワークフローの例を以下に示します。
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
