## 自訂中繼資料 {#custom-metadata}

你可以透過環境變數將中繼資料附加到建置，以改善篩選效果。

### 環境變數

| 變數 | 格式 | 說明 |
|----------|--------|-------------|
| `TUIST_BUILD_TAGS` | 逗號分隔 | 在單一變數中包含多個標籤。 |
| `TUIST_BUILD_VALUE_*` | 單一值 | 鍵值組，其中後綴為鍵。 |

### 範例

在叫用建置前，於 CI 或你的 Shell 中設定這些值：

```sh
export TUIST_BUILD_TAGS="nightly,ios-team,release-candidate"
```

```sh
export TUIST_BUILD_VALUE_TICKET="PROJ-1234"
export TUIST_BUILD_VALUE_PR_URL="https://github.com/myorg/myrepo/pull/123"
```
