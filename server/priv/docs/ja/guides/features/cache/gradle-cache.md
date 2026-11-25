---
{
  "title": "Gradle ビルドキャッシュ: CI とチーム向けにリモートキャッシュを設定する",
  "titleTemplate": ":title · Tuist",
  "description": "Tuist プラグインと org.gradle.caching=true を使用して Gradle のリモートビルドキャッシュを設定し、CI と開発者がタスクを再実行する代わりにタスクの出力を再利用できるようにします。"
}
---
# Gradle ビルドキャッシュ {#gradle-cache}

Tuist は Gradle のリモートビルドキャッシュです。その Gradle プラグインは [Gradle 組み込みのビルドキャッシュ](https://docs.gradle.org/current/userguide/build_cache.html) を共有サーバーに接続し、CI や各開発者マシンがタスクを再実行する代わりにタスク出力を再利用できるようにします。タスクの出力がすでにキャッシュされている場合、Gradle は実行をスキップして Tuist から結果を取得するため、チーム全体および CI 環境でのビルド時間を短縮できます。Tuist が Gradle ビルドに追加するその他の機能（ビルドインサイトやテストインサイトなど）については、[Tuist で Gradle を使う](https://tuist.dev/build-systems/gradle) を参照してください。Develocity と比較している場合は、[Develocity vs Tuist](https://tuist.dev/compare/develocity) を参照してください。Gradle のローカルおよびリモートビルドキャッシュが up-to-date チェックや構成キャッシュとどのように異なるかについては、<.localized_link href="/references/concepts/build-cache#gradle">ビルドキャッシュとは？</.localized_link> を参照してください。遅いビルドのどの部分をキャッシュが削減するのか、またプロジェクトで最初に修正すべき点を確認するには、[低速なビルド](https://tuist.dev/solutions/slow-builds) を参照してください。

<.localized_link href="/guides/install-gradle-plugin">Tuist Gradle プラグイン</.localized_link> をインストールしたら、`gradle.properties` ファイルで Gradle のビルドキャッシュを有効にする必要があります。

```properties
org.gradle.caching=true
```

これを設定しない場合、リモートキャッシュが構成されていても Gradle はビルドキャッシュサブシステムを活性化せず、すべてのタスクはキャッシュヒットもキャッシュへの登録も行わずに実行されます。有効にすると、Gradle は Tuist をリモートビルドキャッシュとして使用し、キャッシュヒット時にキャッシュされたタスク出力をダウンロードし、タスク実行後にそれらをアップロードします。

## キャッシュアップロードポリシー {#cache-upload-policy}

デフォルトでは、プラグインはリモートキャッシュに対してアーティファクトのダウンロードとアップロードの両方を行います。`buildCache` ブロック内の `push` オプションでアップロードを制御できます。

```kotlin
tuist {
    buildCache {
        push = false // read-only mode
    }
}
```

一般的なパターンは、ビルドが再現可能な CI からのみアーティファクトをプッシュし、ローカル環境は読み取り専用に保つことです。

```kotlin
tuist {
    buildCache {
        push = System.getenv("CI") != null
    }
}
```

この設定により、ローカルビルドはアップロードなしでキャッシュされたアーティファクトの恩恵を受け、CI ビルドはチームの他のメンバーのためにキャッシュに登録を行います。

## 継続的インテグレーション {#continuous-integration}

CI 環境では、<.localized_link href="/guides/server/authentication#continuous-integration">認証ガイド</.localized_link> に記載されている方法のいずれかを使用して認証してください。プロバイダー固有の CI 例については、<.localized_link href="/guides/integrations/continuous-integration">継続的インテグレーションガイド</.localized_link> を参照してください。

### ローカルビルドキャッシュの無効化 {#disabling-the-local-build-cache}

Gradle はローカルビルドキャッシュとリモートビルドキャッシュの両方を管理します。ローカルビルドキャッシュは、`~/.gradle/caches/build-cache-1` 以下のディスク上にタスク出力を保存します。

Tuist をリモートビルドキャッシュとして構成する場合、CI ではローカルビルドキャッシュを無効にすることをお勧めします。これにより、CI ランナー上に冗長なアーティファクトが保存されるのを防ぎ、ビルドが常にチームの他のメンバーのために新しいエントリでリモートキャッシュに登録されることを保証します。

`settings.gradle.kts` で CI 上の Gradle ローカルビルドキャッシュを無効にします。

```kotlin
buildCache {
    local {
        isEnabled = System.getenv("CI") == null
    }
}
```

これにより、ローカル開発ではローカルビルドキャッシュを利用可能に保ちつつ、Tuist のリモートキャッシュがアーティファクト共有を担当する CI ではそれを無効にします。

## 構成リファレンス {#configuration-reference}

`buildCache` ブロックは以下をサポートします。

| オプション | 型 | デフォルト | 説明 |
| --- | --- | --- | --- |
| `enabled` | `Boolean` | `true` | リモートビルドキャッシュを有効にするかどうか。 |
| `push` | `Boolean` | `true` | タスク出力をリモートキャッシュにアップロードするかどうか。 |
| `allowInsecureProtocol` | `Boolean` | `false` | 安全でない HTTP 接続を許可するかどうか。 |
