---
{
  "title": "產生的 Xcode 專案",
  "titleTemplate": ":title · 開始使用 · 指南 · Tuist",
  "description": "將模組化的 Xcode 專案壓縮為宣告式 Swift，並在圖層之上解鎖模組快取、選擇性測試、套件註冊表，以及建置與測試見解。"
}
---
# 產生的 Xcode 專案 {#generated-xcode-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/generated-xcode-project
```

:::

當你希望 Tuist 從 Swift 清單描述並產生你的 Xcode 專案時，請遵循此路徑。產生的專案會將模組化 Xcode 專案的複雜性壓縮為簡潔、宣告式的圖形描述。這也是模組快取與選擇性測試的嚴格必要條件。

以下每個章節都會先說明目前缺少的部分，再帶你了解填補該空缺的功能。

## 必要條件

- 已安裝 Xcode 的 macOS。
- <.localized_link href="/guides/install-tuist">Tuist 命令列介面</.localized_link>。

## 建立專案

最快看到成效的方式是從全新專案開始。在空白目錄中執行 `tuist init`，選擇 **建立產生的專案**，挑選平台、確認名稱，然後進行驗證並選擇應擁有該專案的帳號。

```bash
mkdir MyApp && cd MyApp
tuist init
```

如果你是由程式碼代理或腳本驅動此流程，請先執行 `tuist auth login`（瀏覽器流程會等待你按下 Enter），然後使用非互動式表單：

```bash
tuist init --build-system generated-xcode --name MyApp --platform ios --account <account>
```

當 init 完成後，執行 `tuist generate`。Tuist 會在你的清單旁邊寫入一個 `.xcworkspace`，並在 Xcode 中開啟它。建置並執行目標。你應該會在模擬器中看到範例應用程式啟動。

這就是「已連線 + 正在產生」的狀態。以下內容皆為可選且獨立。

如果你要遷移現有應用程式，請先依照 [Xcode 專案遷移指南](https://tuist.dev/en/docs/guides/features/projects/adoption/migrate/xcode-project) 進行連線，然後回到這裡並繼續適合你問題的章節。

## 專案產生

`.xcodeproj` 將你的應用程式結構打包成 XML：檔案參考、建置階段、目標相依性、方案與建置設定都位於同一棵樹中，缺乏將圖形視為圖形來推理的原語。隨著專案成長，這種結構更難在腦中掌握，而 Xcode 也沒有穩定的控制項供工具對其雜湊並在沒有任何變更時跳過工作。

產生的專案會將圖形壓縮為宣告式 Swift。`Project.swift` 直接描述目標、相依性與資源，而 Tuist 會在背後維持一份穩定的圖形模型。這份模型正是開啟以下章節的關鍵：模組快取會對其進行雜湊以重用二進位檔，選擇性測試也會對其進行雜湊以跳過輸入未變更的測試。

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

每次 `tuist generate` 都會從清單產生確定性的工作區。將 `.xcodeproj` 與 `.xcworkspace` 加入 `.gitignore`。

## 模組快取

從零開始編譯模組化 Xcode 專案是每台機器的成本。每位團隊成員與每個 CI 執行器都會產生相同物件檔案的各自副本。Xcode 編譯快取能縮短內部迴圈，但無法消除每個目標的每機器建置，也無法以預建二進位檔取代整個框架。

模組快取可以做到。它會為圖形中每個可快取的相依性（框架、函式庫、套件）建置一次，將產生的二進位檔依據目標輸入的雜湊值儲存，並在後續產生時以該二進位檔取代目標。未變更的模組將不再編譯：

```bash
tuist cache
```

第一次執行會編譯所有內容並將二進位檔上傳至你的帳號。在下一次 `tuist generate` 時，未變更的相依性會以其快取的二進位檔取代，Xcode 會連結 `.xcframework`，而非從原始碼編譯。

## 選擇性測試

`xcodebuild test` 不知道變更會影響哪些測試，因此 CI 會在每次推送時執行整套測試。隨著測試套件擴大，實際需要執行的項目與真正執行的項目之間的差距，會從幾分鐘拉長到數十分鐘。

選擇性測試只會執行自上次成功測試執行以來因變更而受影響的測試，它使用專案圖形以及模組快取所依賴的相同雜湊演算法：

```bash
tuist test
```

第一次 `tuist test` 會執行所有項目並持久化每個目標的雜湊值。後續執行會跳過輸入未變更的目標。將 `tuist test` 放入 CI 以取代 `xcodebuild test`，回饋將在數秒內到位，而非數分鐘。

## 套件註冊表

Swift Package Manager 會透過深度複製每個套件的 git 歷史記錄來解析相依性，因為套件是以 URL 定址，而非透過註冊表。在擁有數十個傳遞性套件的專案中，乾淨檢出時的解析會耗時數分鐘，且在每個 CI 工作中重複發生。

Tuist 套件註冊表提供與 Swift Package Index 追蹤相同的套件，但以真正的註冊表形式提供，因此 SwiftPM 只會擷取你實際需要的提交。只需在 `Tuist.swift` 中設定 `registryEnabled: true` 即可啟用：

```swift
let tuist = Tuist(
    project: .tuist(
        generationOptions: .options(
            registryEnabled: true
        )
    )
)
```

重新產生。套件解析時間從數分鐘降至數秒。

## 建置洞察

Xcode 會在日誌與建置報告中記錄每個目標的建置持續時間。兩者都不會跨執行或跨機器匯總，因此建置時間回退通常只表現為整體 CI 變慢。

建置洞察會自動記錄每個建置的持續時間與階段計時（針對產生的方案）。無需額外設定。在下一次 `tuist generate` + 建置週期後，開啟儀表板的 **Builds** 分頁。

## 測試洞察

Xcode 每次執行僅回報單一測試的結果。它不會匯總你真正需要的跨執行訊號：不穩定率、週對週持續時間、哪些模擬器變體失敗。

測試洞察會自動記錄每個測試的結果與持續時間（針對產生的方案），並關聯跨執行的結果。不穩定測試、緩慢測試與失敗會顯示在儀表板的 **Tests** 分頁。當不穩定情況累積時，請從儀表板將其隔離，以免阻擋合併。

## 讓團隊一起加入

當所有人都使用相同的共用表面時，模組快取與選擇性測試的效益最大。從儀表板的帳號設定邀請隊友加入組織，並設定 <.localized_link href="/guides/integrations/authentication/sso">單一登入</.localized_link>（Google、Okta、Microsoft），讓入職流程只需點擊一下，而非每人執行一次 `tuist auth login`。
