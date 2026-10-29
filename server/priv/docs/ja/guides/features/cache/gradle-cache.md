---
{
  "title": "Gradle cache",
  "titleTemplate": ":title · Cache · Features · Guides · Tuist",
  "description": "Share Gradle build cache artifacts across your team and CI with Tuist."
}
---
# Gradle キャッシュ {#gradle-cache}

Tuist は、[Gradle の組み込みビルドキャッシュ](https://docs.gradle.org/current/userguide/build_cache.html)と統合してビルド成果物をリモートで共有する Gradle プラグインを提供します。タスクの出力がすでにキャッシュされている場合、Gradle は実行をスキップし、Tuist のリモートキャッシュから結果を取得するため、チーム全体および CI 環境でのビルド時間を短縮できます。

<.localized_link href="/guides/install-gradle-plugin">Tuist Gradle プラグイン</.localized_link> をインストールしたら、`gradle.properties` ファイルで Gradle のビルドキャッシュを有効にする必要があります:

```properties
org.gradle.caching=true
```

これを設定しない場合、リモートキャッシュが構成されていても Gradle はビルドキャッシュサブシステムをアクティブにせず、すべてのタスクはキャッシュへのヒットやキャッシュへの登録を行わずに実行されます。有効にすると、Gradle は Tuist をリモートビルドキャッシュとして使用し、キャッシュヒット時にキャッシュされたタスク出力をダウンロードし、タスク実行後にそれらをアップロードします。

## キャッシュアップロードポリシー {#cache-upload-policy}

デフォルトでは、プラグインはリモートキャッシュに対して成果物のダウンロードとアップロードの両方を行います。`buildCache` ブロック内の `push` オプションを使用してアップロードを制御できます:

```kotlin
tuist {
    buildCache {
        push = false // read-only mode
    }
}
```

一般的なパターンは、ビルドが再現可能な CI からのみ成果物をプッシュし、ローカル環境は読み取り専用モードにすることです:

```kotlin
tuist {
    buildCache {
        push = System.getenv("CI") != null
    }
}
```

この設定により、ローカルビルドはアップロードなしでキャッシュされた成果物の恩恵を受けられ、CI ビルドはチームの他のメンバーのためにキャッシュに登録されます。

## 継続的インテグレーション {#continuous-integration}

CI 環境では、<.localized_link href="/guides/server/authentication#continuous-integration">認証ガイド</.localized_link> に記載されている方法のいずれかを使用して認証してください。プロバイダー固有の CI 例については、<.localized_link href="/guides/integrations/continuous-integration">継続的インテグレーションガイド</.localized_link> を参照してください。

### ローカルビルドキャッシュの無効化 {#disabling-the-local-build-cache}

Gradle はローカルビルドキャッシュとリモートビルドキャッシュの両方を管理します。ローカルビルドキャッシュは、`~/.gradle/caches/build-cache-1` 以下のディスク上にタスク出力を保存します。

Tuist がリモートビルドキャッシュとして構成されている場合、CI ではローカルビルドキャッシュを無効にすることをお勧めします。これにより、CI ランナー上に冗長な成果物が保存されるのを防ぎ、ビルドが常にチームの他のメンバーのために新しいエントリでリモートキャッシュに登録されることを保証します。

`settings.gradle.kts` で CI 上の Gradle のローカルビルドキャッシュを無効にします:

```kotlin
buildCache {
    local {
        isEnabled = System.getenv("CI") == null
    }
}
```

これにより、ローカル開発ではローカルビルドキャッシュを利用可能に保ちつつ、Tuist のリモートキャッシュが成果物の共有を処理する CI 上ではそれを無効にします。

## 構成リファレンス {#configuration-reference}

`buildCache` ブロックは以下をサポートします:

| オプション | 型 | デフォルト | 説明 |
| --- | --- | --- | --- |
| `enabled` | `Boolean` | `true` | リモートビルドキャッシュを有効にするかどうか。 |
| `push` | `Boolean` | `true` | タスク出力をリモートキャッシュにアップロードするかどうか。 |
| `allowInsecureProtocol` | `Boolean` | `false` | 安全でない HTTP 接続を許可するかどうか。 |
