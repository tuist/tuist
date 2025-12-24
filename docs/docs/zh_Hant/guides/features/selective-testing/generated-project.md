---
{
  "title": "Generated project",
  "titleTemplate": ":title · Selective testing · Features · Guides · Tuist",
  "description": "Learn how to leverage selective testing with a generated project."
}
---
# 產生專案{#generated-project}

::: warning REQUIREMENTS
<!-- -->
- 一個 <LocalizedLink href="/guides/features/projects"> 產生的專案</LocalizedLink>
- A<LocalizedLink href="/guides/server/accounts-and-projects">Tuist帳號與專案</LocalizedLink>
<!-- -->
:::

若要有選擇性地使用已產生的專案執行測試，請使用`tuist test` 指令。該命令
<LocalizedLink href="/guides/features/projects/hashing">散列</LocalizedLink>您的
Xcode 專案，方式與
<LocalizedLink href="/guides/features/cache#cache-warming">暖化快取記憶體</LocalizedLink>相同，成功後會持續散列，以判斷未來執行時有哪些改變。

在未來執行`tuist test` 時，會透明地使用哈希值來篩選測試，只執行自上次成功執行測試以來有變更的測試。

例如，假設下列依賴圖形：

- `FeatureA` 有測試`FeatureATests` ，並依賴於`核心`
- `FeatureB` 有測試`FeatureBTests` ，並依賴於`核心`
- `Core` 有測試`CoreTests`

`tuist 測試` 將會有這樣的行為：

| 行動             | 說明                                                   | 內部狀態                                                       |
| -------------- | ---------------------------------------------------- | ---------------------------------------------------------- |
| `tuist 測試` 援用  | 執行`CoreTests`,`FeatureATests`, 和`FeatureBTests 中的測試` | `FeatureATests` 、`FeatureBTests` 和`CoreTests` 的散列會被持久化。    |
| `FeatureA` 已更新 | 開發人員修改目標程式碼                                          | 與之前相同                                                      |
| `tuist 測試` 援用  | 執行`FeatureATests` 中的測試，因為其雜湊值已變更                     | `FeatureATests` 的新切細值會被持久化                                 |
| `核心` 已更新       | 開發人員修改目標程式碼                                          | 與之前相同                                                      |
| `tuist 測試` 援用  | 執行`CoreTests`,`FeatureATests`, 和`FeatureBTests 中的測試` | `FeatureATests` `FeatureBTests` ，以及`CoreTests` 的新切細值會被持久化。 |

`tuist test`
直接與二進位快取整合，可從您的本機或遠端儲存中使用盡可能多的二進位檔案，以改善執行測試套件時的建立時間。選擇性測試與二進位快取的結合，可以大幅縮短在 CI
上執行測試的時間。

## UI 測試{#ui-tests}

Tuist 支援 UI 測試的選擇性測試。但是，Tuist 需要事先知道目的地。只有指定`目的地` 參數，Tuist 才會有選擇性地執行 UI 測試，例如：
```sh
tuist test --device 'iPhone 14 Pro'
# or
tuist test -- -destination 'name=iPhone 14 Pro'
# or
tuist test -- -destination 'id=SIMULATOR_ID'
```
