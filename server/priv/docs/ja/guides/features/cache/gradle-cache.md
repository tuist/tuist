---
{
  "title": "Gradleキャッシュ",
  "titleTemplate": ":title · キャッシュ · 機能 · ガイド · Tuist",
  "description": "Tuistを使用して、チームやCI間でGradleビルドキャッシュの成果物を共有します。"
}
---
# Gradleキャッシュ {#gradle-cache}

Tuistは、[Gradleの組み込みビルドキャッシュ](https://docs.gradle.org/current/userguide/build_cache.html)と連携してビルド成果物をリモートで共有するGradleプラグインを提供します。タスクの出力がすでにキャッシュされている場合、Gradleは実行をスキップし、Tuistのリモートキャッシュから結果を取得するため、チーム全体やCI環境でのビルド時間を短縮できます。

<.localized_link href="/guides/install-gradle-plugin">Tuist Gradleプラグイン</.localized_link>をインストールしたら、`gradle.properties`ファイルでGradleのビルドキャッシュを有効にする必要があります。

```properties
org.gradle.caching=true
```

これを設定しないと、リモートキャッシュを設定していてもGradleはビルドキャッシュサブシステムを活性化せず、すべてのタスクがキャッシュのヒットや登録なしに実行されます。有効にすると、GradleはTuistをリモートビルドキャッシュとして使用し、キャッシュヒット時にキャッシュされたタスク出力をダウンロードし、タスク実行後にアップロードします。

## キャッシュアップロードポリシー {#cache-upload-policy}

デフォルトでは、このプラグインはリモートキャッシュへのアーティファクトのダウンロードとアップロードの両方を行います。`buildCache`ブロック内の`push`オプションでアップロードを制御できます。

```kotlin
tuist {
    buildCache {
        push = false // read-only mode
    }
}
```

一般的なパターンは、ビルドが再現可能なCIからのみアーティファクトをプッシュし、ローカル環境は読み取り専用のままにすることです。

```kotlin
tuist {
    buildCache {
        push = System.getenv("CI") != null
    }
}
```

この設定により、ローカルビルドはアップロードなしでキャッシュされたアーティファクトの恩恵を受け、CIビルドはチームの他のメンバーのためにキャッシュに登録します。

## 継続的インテグレーション {#continuous-integration}

CI環境では、<.localized_link href="/guides/server/authentication#continuous-integration">認証ガイド</.localized_link>に記載された方法のいずれかを使用して認証してください。プロバイダー固有のCI例については、<.localized_link href="/guides/integrations/continuous-integration">継続的インテグレーションガイド</.localized_link>を参照してください。

### ローカルビルドキャッシュの無効化 {#disabling-the-local-build-cache}

Gradleはローカルビルドキャッシュとリモートビルドキャッシュの両方を維持します。ローカルビルドキャッシュは、`~/.gradle/caches/build-cache-1`以下のディスクにタスク出力を保存します。

Tuistをリモートビルドキャッシュとして構成する場合、CIではローカルビルドキャッシュを無効にすることを推奨します。これにより、CIランナーに冗長なアーティファクトを保存することを避け、ビルドが常にチームの他のメンバーのために新しいエントリでリモートキャッシュに登録されることを保証します。

`settings.gradle.kts`でCI上のGradleローカルビルドキャッシュを無効にします。

```kotlin
buildCache {
    local {
        isEnabled = System.getenv("CI") == null
    }
}
```

これにより、ローカル開発ではローカルビルドキャッシュを利用可能にしつつ、Tuistのリモートキャッシュがアーティファクト共有を処理するCI上ではこれを無効にします。

## 設定リファレンス {#configuration-reference}

`buildCache`ブロックは以下をサポートします。

| オプション | 型 | デフォルト | 説明 |
| --- | --- | --- | --- |
| `enabled` | `Boolean` | `true` | リモートビルドキャッシュを有効にするかどうか。 |
| `push` | `Boolean` | `true` | タスク出力をリモートキャッシュにアップロードするかどうか。 |
| `allowInsecureProtocol` | `Boolean` | `false` | 安全でないHTTP接続を許可するかどうか。 |
