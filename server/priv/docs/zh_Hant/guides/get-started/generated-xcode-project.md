---
{
  "title": "生成的 Xcode 專案",
  "titleTemplate": ":title · 入門指南 · 指南 · Tuist",
  "description": "將模組化的 Xcode 專案壓縮為宣告式 Swift，並在圖形之上解鎖模組快取、選擇性測試、套件註冊表，以及建置與測試洞察。"
}
---
# 生成的 Xcode 專案 {#generated-xcode-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/generated-xcode-project
```

:::

當你希望 Tuist 從 Swift 清單描述並生成你的 Xcode 專案時，請遵循此路徑。生成的專案將模組化 Xcode 專案的複雜性壓縮為圖形的簡潔、宣告式描述。這也是模組快取和選擇性測試的嚴格要求。

以下每個章節都先說明目前缺少的部分，然後逐步引導你了解填補該空缺的功能。

## 必要條件

- 已安裝 Xcode 的 macOS。
- <.localized_link href="/guides/install-tuist">Tuist 命令列介面</.localized_link>。

## 建立專案

查看其運作的最快方式是建立一個全新專案。在空目錄中執行 `tuist init` 並選擇 **建立生成的專案**，挑選平台、確認名稱，然後進行驗證並選擇應擁有該專案的帳戶。

```bash
mkdir MyApp && cd MyApp
tuist init
```

如果你透過編碼代理程式或腳本驅動此流程，請先執行 `tuist auth login`（瀏覽器流程會等待你按下 Enter），然後使用非互動式表單：

```bash
tuist init --build-system generated-xcode --name MyApp --platform ios --account <account>
```

當 init 完成後，執行 `tuist generate`。Tuist 會在你的清單旁邊寫入一個 `.xcworkspace` 並在 Xcode 中開啟它。建置並執行目標。你應該會看到範例應用程式在模擬器中啟動。

這就是「已連線 + 生成中」的狀態。以下所有内容皆為可選且獨立。

如果你要遷移現有應用程式，請先依照 [Xcode 專案遷移指南](https://tuist.dev/en/docs/guides/features/projects/adoption/migrate/xcode-project) 進行連線，然後回來繼續處理符合你問題的章節。

## 專案生成

`.xcodeproj` 將你的應用程式結構打包成 XML：檔案參考、建置階段、目標相依性、方案以及建置設定都位於同一棵樹中，沒有用於將圖形作為圖形進行推理的原語。隨著專案增長，這種結構更難以在腦海中掌握，而且 Xcode 沒有穩定的控制項供工具對其進行雜湊並在沒有任何變更時跳過工作。

生成的專案將圖形壓縮為宣告式 Swift。`Project.swift` 直接描述目標、相依性和資源，而 Tuist 在其背後維護圖形的穩定模型。該模型正是解鎖以下章節的關鍵：模組快取會對其進行雜湊以重複使用二進位檔，而選擇性測試會對其進行雜湊以跳過輸入未變更的測試。

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

每次 `tuist generate` 都會從清單產生確定性的工作區。將 `.xcodeproj` 和 `.xcworkspace` 加入 `.gitignore`。

## 模組快取

從頭開始編譯模組化 Xcode 專案是每台機器的成本。每位團隊成員和每個 CI 執行器都會產生相同物件檔案的各自副本。Xcode 編譯快取縮短了內部迴圈，但並未移除每個目標的每台機器建置，也無法用預建二進位檔取代整個框架。

模組快取可以做到這一點。它會建置圖形中每個可快取的相依性一次（框架、函式庫、套件），將產生的二進位檔依據目標輸入的雜湊值儲存，並在後續生成時將目標替換為其二進位檔。未變更的模組將停止編譯：

```bash
tuist cache
```

第一次執行會編譯所有內容並將二進位檔上傳至你的帳戶。在下一次 `tuist generate` 時，未變更的相依性會被其快取的二進位檔取代，Xcode 會連結 `.xcframework` 而非從原始碼編譯。

## 選擇性測試

`xcodebuild test` 不知道變更影響了哪些測試，因此 CI 會在每次推送時執行整個套件。隨著套件增長，實際需要執行的內容與實際執行內容之間的差距從幾分鐘拉長到數十分鐘。

選擇性測試僅執行自上次成功測試執行以來因變更而受影響的測試，使用專案圖形以及模組快取所依賴的相同雜湊演算法：

```bash
tuist test
```

第一次 `tuist test` 會執行所有內容並持久保存每個目標的雜湊值。後續執行會跳過輸入未變更的目標。將 `tuist test` 移至 CI 中以取代 `xcodebuild test`，回饋將在幾秒內到達，而非數分鐘。

## 套件註冊表

Swift Package Manager 透過深度克隆每個套件的 git 歷史記錄來解析相依性，因為套件是透過 URL 而非註冊表定址。在擁有數十個傳遞性套件的專案中，解析在乾淨檢出時會耗時數分鐘，並且在每個 CI 作業中重複發生。

Tuist 套件註冊表提供與 Swift Package Index 追蹤相同的套件，但作為真正的註冊表，因此 SwiftPM 僅提取你實際需要的提交。透過在 `Tuist.swift` 中設定 `registryEnabled: true` 來啟用一次：

```swift
let tuist = Tuist(
    project: .tuist(
        generationOptions: .options(
            registryEnabled: true
        )
    )
)
```

重新生成。套件解析時間從數分鐘降至數秒。

## 建置洞察

Xcode 在日誌和建置報告中記錄每個目標的建置持續時間。兩者均未跨執行或跨機器聚合，因此建置時間回歸通常僅表現為整體 CI 變慢。

建置洞察會自動記錄每個建置的持續時間和生成方案的階段計時。無需額外設定。在下一次 `tuist generate` + 建置週期後，開啟儀表板的 **建置** 標籤。

## 測試洞察

Xcode 每次執行報告每個測試的結果。它不會聚合你實際需要的跨執行訊號：不穩定率、週對週持續時間、哪些模擬器變體失敗。

測試洞察會自動記錄每個測試的結果和生成方案的持續時間，並關聯跨執行的結果。不穩定測試、緩慢測試和失敗會顯示在儀表板的 **測試** 標籤上。當不穩定情況累積時，請從儀表板將其隔離，使其不再阻擋合併。

## 讓團隊一起參與

當每個人都使用相同的共用表面時，模組快取和選擇性測試的收益最大。從儀表板的帳戶設定邀請你的隊友加入組織，並設定 <.localized_link href="/guides/integrations/authentication/sso">單一登入</.localized_link>（Google、Okta、Microsoft），這樣入職只需點擊一下，而非每人執行一次 `tuist auth login`。
