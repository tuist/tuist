## カスタムメタデータ {#custom-metadata}

環境変数を使用してビルドにメタデータを付与し、フィルタリングを改善できます。

### 環境変数

| 変数 | 形式 | 説明 |
|----------|--------|-------------|
| `TUIST_BUILD_TAGS` | カンマ区切り | 1 つの変数に複数のタグを設定します。 |
| `TUIST_BUILD_VALUE_*` | 単一値 | サフィックスがキーとなるキーと値のペアです。 |

### 例

ビルドを実行する前に、CI またはシェルでこれらの値を設定してください:

```sh
export TUIST_BUILD_TAGS="nightly,ios-team,release-candidate"
```

```sh
export TUIST_BUILD_VALUE_TICKET="PROJ-1234"
export TUIST_BUILD_VALUE_PR_URL="https://github.com/myorg/myrepo/pull/123"
```
