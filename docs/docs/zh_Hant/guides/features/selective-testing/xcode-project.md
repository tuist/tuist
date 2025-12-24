---
{
  "title": "Xcode project",
  "titleTemplate": ":title · Selective testing · Features · Guides · Tuist",
  "description": "Learn how to leverage selective testing with `xcodebuild`."
}
---
# Xcode 專案{#xcode-project}

::: warning REQUIREMENTS
<!-- -->
- A<LocalizedLink href="/guides/server/accounts-and-projects">Tuist帳號與專案</LocalizedLink>
<!-- -->
:::

您可以透過命令列選擇性地執行 Xcode 專案的測試。為此，您可以在`xcodebuild` 指令前加上`tuist` - 例如，`tuist
xcodebuild test -scheme App` 。該命令會對您的專案進行切細處理，成功後，它會持久化切細值，以確定在未來的執行中有哪些變更。

在以後的執行中`tuist xcodebuild test` 會透明地使用哈希值來篩選測試，只執行自上次成功執行測試後有變更的測試。

例如，假設下列依賴圖形：

- `FeatureA` 有測試`FeatureATests` ，並依賴於`核心`
- `FeatureB` 有測試`FeatureBTests` ，並依賴於`核心`
- `Core` 有測試`CoreTests`

`tuist xcodebuild test` 將會有這樣的行為：

| 行動                                 | 說明                                                   | 內部狀態                                                       |
| ---------------------------------- | ---------------------------------------------------- | ---------------------------------------------------------- |
| `tuist xcodebuild test` invocation | 執行`CoreTests`,`FeatureATests`, 和`FeatureBTests 中的測試` | `FeatureATests` 、`FeatureBTests` 和`CoreTests` 的散列會被持久化。    |
| `FeatureA` 已更新                     | 開發人員修改目標程式碼                                          | 與之前相同                                                      |
| `tuist xcodebuild test` invocation | 執行`FeatureATests` 中的測試，因為其雜湊值已變更                     | `FeatureATests` 的新切細值會被持久化                                 |
| `核心` 已更新                           | 開發人員修改目標程式碼                                          | 與之前相同                                                      |
| `tuist xcodebuild test` invocation | 執行`CoreTests`,`FeatureATests`, 和`FeatureBTests 中的測試` | `FeatureATests` `FeatureBTests` ，以及`CoreTests` 的新切細值會被持久化。 |

若要在 CI 上使用`tuist xcodebuild test` ，請遵循
<LocalizedLink href="/guides/integrations/continuous-integration">Continuous integration guide</LocalizedLink> 中的指示。

查看以下視訊，瞭解選擇性測試的實際運作：

<iframe title="Run tests selectively in your Xcode projects" width="560" height="315" src="https://videos.tuist.dev/videos/embed/1SjekbWSYJ2HAaVjchwjfQ" frameborder="0" allowfullscreen="" sandbox="allow-same-origin allow-scripts allow-popups allow-forms"></iframe>
