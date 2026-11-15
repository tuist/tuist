---
{
  "title": "Gradle キャッシュ",
  "titleTemplate": ":title · キャッシュ · 機能 · ガイド · Tuist",
  "description": "Tuist を使用して、チームや CI で Gradle のビルドキャッシュアーティファクトを共有します。"
}
---
# Gradle キャッシュ {#gradle-cache}

Tuist は、[Gradle の組み込みビルドキャッシュ](https://docs.gradle.org/current/userguide/build_cache.html)と連携してビルド成果物をリモートで共有する Gradle プラグインを提供します。タスクの出力がすでにキャッシュされている場合、Gradle は実行をスキップし、Tuist のリモートキャッシュから結果を取得するため、チーム全体および CI 環境でのビルド時間を短縮できます。キャッシュによって遅いビルドのどの部分が削減されるか、またプロジェクトで最初に修正すべき箇所を確認するには、[Slow builds](https://tuist.dev/solutions/slow-builds) を参照してください。

<.localized_link href="/guides/install-gradle-plugin">Tuist Gradle プラグイン</.localized_link>をインストールしたら、`gradle.properties` ファイルで Gradle のビルドキャッシュを有効にする必要があります。

```properties
org.gradle.caching=true
```

これを設定しない場合、リモートキャッシュが構成されていても Gradle はビルドキャッシュサブシステムをアクティブ化せず、すべてのタスクはキャッシュヒットもキャッシュへの登録も行わずに実行されます。有効にすると、Gradle は Tuist をリモートビルドキャッシュとして使用し、キャッシュヒット時にキャッシュされたタスク出力をダウンロードし、タスク実行後にアップロードします。

## キャッシュアップロードポリシー {#cache-upload-policy}

デフォルトでは、プラグインはリモートキャッシュへのアーティファクトのダウンロードとアップロードの両方を行います。`buildCache` ブロック内の `push` オプションでアップロードを制御できます。

```kotlin
tuist {
    buildCache {
        push = false // read-only mode
    }
}
```

一般的なパターンは、ビルドが再現可能な CI からのみアーティファクトをプッシュし、ローカル環境は読み取り専用にすることです。

```kotlin
tuist {
    buildCache {
        push = System.getenv("CI") != null
    }
}
```

この設定により、ローカルビルドはアップロードせずにキャッシュされたアーティファクトの恩恵を受け、CI ビルドはチームの他のメンバーのためにキャッシュに登録します。

## 継続的インテグレーション {#continuous-integration}

CI 環境では、<.localized_link href="/guides/server/authentication#continuous-integration">Authentication guide</.localized_link> に記載されているいずれかの方法を使用して認証してください。プロバイダー固有の CI 例については、<.localized_link href="/guides/integrations/continuous-integration">Continuous Integration guide</.localized_link> を参照してください。

### ローカルビルドキャッシュの無効化 {#disabling-the-local-build-cache}

Gradle はローカルビルドキャッシュとリモートビルドキャッシュの両方を管理します。ローカルビルドキャッシュは、`~/.gradle/caches/build-cache-1` の下のディスクにタスク出力を保存します。

Tuist をリモートビルドキャッシュとして構成する場合、CI ではローカルビルドキャッシュを無効にすることを推奨します。これにより、CI ランナー上に冗長なアーティファクトを保存することを避け、ビルドが常にリモートキャッシュに新しいエントリを登録してチームの他のメンバーと共有できるようにします。

`settings.gradle.kts` で CI 上の Gradle のローカルビルドキャッシュを無効にします。

```kotlin
buildCache {
    local {
        isEnabled = System.getenv("CI") == null
    }
}
```

これにより、ローカル開発ではローカルビルドキャッシュを利用可能に保ちつつ、Tuist のリモートキャッシュがアーティファクト共有を担当する CI では無効にします。

## 設定リファレンス {#configuration-reference}

`buildCache` ブロックは以下をサポートします。

| オプション | 型 | デフォルト | 説明 |
| --- | --- | --- | --- |
| `enabled` | `Boolean` | `true` | リモートビルドキャッシュを有効にするかどうか。 |
| `push` | `Boolean` | `true` | タスク出力をリモートキャッシュにアップロードするかどうか。 |
| `allowInsecureProtocol` | `Boolean` | `false` | 安全でない HTTP 接続を許可するかどうか。 |
