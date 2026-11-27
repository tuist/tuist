---
{
  "title": "Gradle",
  "titleTemplate": ":title · Snapshots · 功能 · 指南 · Tuist",
  "description": "使用 Tuist Gradle 外掛程式，為每個 Compose 預覽建立快照，或上傳 Paparazzi 與 Roborazzi 的記錄結果。"
}
---
# Gradle 快照 {#gradle-snapshots}

> [!IMPORTANT]
> **必要條件**
>
> - 你的帳號已啟用快照功能。目前僅限邀請使用：[聯絡我們](mailto:contact@tuist.dev)或在[社群 Slack](https://slack.tuist.dev)中聯繫我們以申請存取權限。
> - <.localized_link href="/guides/install-gradle-plugin">Tuist Gradle 外掛程式</.localized_link>。
> - 在你進行快照的模組中使用 [Paparazzi](https://github.com/cashapp/paparazzi) 或 [Roborazzi](https://github.com/takahirom/roborazzi)。

Tuist Gradle 外掛程式會上傳 Paparazzi 與 Roborazzi 錄製的圖片，而 Tuist 會將這些圖片與<.localized_link href="/guides/features/snapshots#how-it-works">基準線</.localized_link>進行比對。在套用 Paparazzi 的模組中，此外掛程式也會產生一個測試，用於渲染每個 Compose `@Preview`，因此你無需手動撰寫快照測試。

## 設定 {#set-up}

在你的 `settings.gradle.kts` 中啟用快照：

```kotlin
tuist {
    snapshots {
        enabled = true
        set = "android-phone" // Defaults to the Gradle project's path.
    }
}
```

## 執行 {#run}

在 CI 中，`./gradlew test` 會渲染預覽並上傳；若預覽發生變更且未經任何人核准，建置將會失敗。本機執行不會上傳任何內容，因為這會導致上傳未提交的變更。請傳遞 `-Ptuist.snapshots=false` 以在 CI 中關閉上傳功能。

Paparazzi 與 Roborazzi 的錄製任務（例如 `recordPaparazziDebug`）在啟用快照時一律會上傳。

## 選項 {#options}

`snapshots` 區塊接受以下選項：

- `enabled`：是否上傳快照。預設為 `false`。
- `set`：用以比較建置的集合。預設為 Gradle 專案的路徑。
- `directory`：包含待上傳圖片的目錄，相對於 Gradle 專案。預設為產生的預覽測試或快照程式庫寫入的位置。
- `failOnChanges`：當出現未經核准的變更時，是否讓建置失敗。預設為 `true`。
- `diffThreshold`：允許差異的像素比例（範圍從 0 到 1），超過此比例圖片才會被視為已變更。預設為 `0`。
- `previews { generateTests }`：是否產生 Compose 預覽測試。預設為 `true`。
- `previews { packageTrees }`：掃描預覽所在的套件。預設為 Android 命名空間。
- `previews { includePrivatePreviews }`：是否也渲染私有的 `@Preview` 函式。預設為 `false`。
- `previews { theme }`：渲染預覽時使用的 Android 主題。預設為 Paparazzi 的主題。
