## 自訂元數據 {#custom-metadata}

你可以透過環境變數將元數據附加到構建，以改善篩選功能。

### 環境變數

| 變數 | 格式 | 描述 |
|----------|--------|-------------|
| `TUIST_BUILD_TAGS` | 逗號分隔 | 單一變數中包含多個標籤。 |
| `TUIST_BUILD_VALUE_*` | 單一值 | 鍵值對，其中後綴為鍵。 |

### 範例

在調用構建之前，於 CI 或你的 shell 中設定這些值：

```sh
export TUIST_BUILD_TAGS="nightly,ios-team,release-candidate"
```

```sh
export TUIST_BUILD_VALUE_TICKET="PROJ-1234"
export TUIST_BUILD_VALUE_PR_URL="https://github.com/myorg/myrepo/pull/123"
```
