---
{
  "title": "Generated Xcode project",
  "titleTemplate": ":title · Get started · Guides · Tuist",
  "description": "Compress a modular Xcode project into declarative Swift and unlock module caching, selective testing, a package registry, and build and test insights on top of the graph."
}
---
# 生成的 Xcode 專案 {#generated-xcode-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/generated-xcode-project
```

:::

當你想讓 Tuist 從 Swift manifest 描述並生成你的 Xcode 專案時，請遵循此路徑。生成的專案將模組化 Xcode 專案的複雜性壓縮為圖形的簡潔、宣告式描述。這也是模組快取和選擇性測試的嚴格要求。

以下每個章節都會先說明目前缺少的功能，然後引導你了解填補該空缺的功能。

## 必要條件

- 已安裝 Xcode 的 macOS。
- <.localized_link href="/guides/install-tuist">Tuist 命令列介面</.localized_link>。

## 建立專案

看到它運作的最快方式是從一個全新專案開始。在空目錄中執行 `tuist init` 並選擇 **建立生成的專案**，選擇平台，確認名稱，然後進行身份驗證並選擇應擁有該專案的帳戶。

```bash
mkdir MyApp && cd MyApp
tuist init
```

如果你是從編碼代理程式或腳本驅動此過程，請先執行 `tuist auth login`（瀏覽器流程會等待你按下 Enter），然後使用非互動式表單：

```bash
tuist init --build-system generated-xcode --name MyApp --platform ios --account <account>
```

當 init 完成後，執行 `tuist generate`。Tuist 會在你的 manifest 旁邊寫入一個 `.xcworkspace` 並在 Xcode 中開啟它。建置並執行目標。你應該會看到範例應用程式在模擬器中啟動。

這就是「已連線 + 生成」狀態。以下所有内容都是可選且獨立的。

如果你正在遷移現有應用程式，請先使用 [Xcode 專案遷移指南](https://tuist.dev/en/docs/guides/features/projects/adoption/migrate/xcode-project) 將其連接，然後回來繼續處理適合你問題的章節。

## 專案生成

`.xcodeproj` 將你的應用程式結構打包成 XML：檔案參考、建置階段、目標依賴關係、scheme 和建置設定都位於同一棵樹中，沒有用於將圖形作為圖形進行推理的原語。隨著專案增長，這種結構變得越來越難以在腦海中掌握，而且 Xcode 沒有穩定的句柄供工具對其進行雜湊並在沒有任何變更時跳過工作。

生成的專案將圖形壓縮為宣告式 Swift。`Project.swift` 直接描述目標、依賴關係和資源，而 Tuist 在其背後保持圖形的穩定模型。該模型解鎖了以下章節：模組快取對其進行雜湊以重用二進位檔案，選擇性測試對其進行雜湊以跳過輸入未變更的測試。

```swift
import ProjectDescription

let project = Project(
    name: "MyApp",
    targets: [
        .target(
            name: "MyApp",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.MyApp",
            sources: ["MyApp/Sources/**"],
            dependencies: []
        )
    ]
)
```

每次 `tuist generate` 都會從 manifest 產生一個確定性的工作區。將 `.xcodeproj` 和 `.xcworkspace` 加入 `.gitignore`。

## 模組快取

從頭開始編譯模組化 Xcode 專案是一項每台機器的成本。每位隊友和每個 CI 執行器都會產生相同物件檔案的自己的副本。Xcode 編譯快取縮短了內部循環，但並未消除每個目標的每台機器建置，也無法用預建二進位檔案替換整個框架。

模組快取可以做到這一點。它只會建置圖形中每個可快取的依賴項一次（框架、程式庫、bundle），將產生的二進位檔案根據目標輸入的雜湊值儲存，並在後續生成中用其二進位檔案替換目標。未變更的模組將停止編譯：

```bash
tuist cache
```

第一次執行會編譯所有內容並將二進位檔案上傳到你的帳戶。在下一次 `tuist generate` 時，未變更的依賴項會被其快取的二進位檔案替換，Xcode 會連結到 `.xcframework` 而不是從原始碼編譯。

## 選擇性測試

`xcodebuild test` 不知道變更會影響哪些測試，因此 CI 會在每次推送時執行整個套件。隨著套件增長，實際需要執行的內容與實際執行內容之間的差距從幾分鐘延長到幾十分鐘。

選擇性測試僅執行自上次成功測試運行以來受變更影響的測試，使用專案圖形和模組快取所依賴的相同雜湊演算法：

```bash
tuist test
```

第一次 `tuist test` 會執行所有內容並持久化每個目標的雜湊值。後續運行會跳過輸入未變更的目標。將 `tuist test` 移至 CI 中以取代 `xcodebuild test`，反饋將在幾秒鐘內到達，而不是幾分鐘。

## 套件註冊表

Swift Package Manager 透過深度克隆每個套件的 git 歷史記錄來解析依賴關係，因為套件是通過 URL 而非註冊表來定址的。在具有數十個傳遞套件的專案中，解析在乾淨檢出時需要幾分鐘，並且在每個 CI 作業中重複。

Tuist Package Registry 提供與 Swift Package Index 追蹤的相同套件，但作為真正的註冊表，因此 SwiftPM 僅獲取你實際需要的 commit。透過在 `Tuist.swift` 中設定 `registryEnabled: true` 來啟用一次：

```swift
let tuist = Tuist(
    project: .tuist(
        generationOptions: .options(
            registryEnabled: true
        )
    )
)
```

重新生成。套件解析時間從幾分鐘降至幾秒鐘。

## 建置洞察

Xcode 在日誌和建置報告中記錄每個目標的建置持續時間。兩者都沒有跨運行或跨機器聚合，因此建置時間回歸通常只表現為整體 CI 變慢。

建置洞察會自動記錄每個建置的持續時間和生成 scheme 的階段計時。無需額外配置。在下一次 `tuist generate` + 建置循環後，開啟儀表板的 **Builds** 標籤。

## 測試洞察

Xcode 一次報告每次運行的每個測試結果。它不會聚合你實際需要的跨運行信號：不穩定率、週對週持續時間、哪些模擬器變體失敗。

測試洞察會自動記錄每個測試的結果和生成 scheme 的持續時間，並關聯跨運行的結果。不穩定測試、緩慢測試和失敗會顯示在儀表板的 **Tests** 標籤上。當不穩定情況累積時，從儀表板隔離它們，以便它們不再阻止合併。

## 讓團隊一起參與

當每個人都使用相同的共享表面時，模組快取和選擇性測試的收益最大。從儀表板的帳戶設定邀請你的隊友加入組織，並設定 <.localized_link href="/guides/integrations/authentication/sso">Single Sign-On</.localized_link>（Google、Okta、Microsoft），以便入職只需點擊一下，而不是每人執行 `tuist auth login`。
