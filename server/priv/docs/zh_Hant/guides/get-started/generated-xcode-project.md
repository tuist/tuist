---
{
  "title": "產生的 Xcode 專案",
  "titleTemplate": ":title · 開始使用 · 指南 · Tuist",
  "description": "將模組化的 Xcode 專案壓縮為宣告式 Swift，並在圖形基礎上啟用模組快取、選擇性測試、套件註冊表，以及建置與測試洞察。"
}
---
# 產生的 Xcode 專案 {#generated-xcode-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/generated-xcode-project
```

:::

當你希望 Tuist 根據 Swift 清單描述並產生你的 Xcode 專案時，請遵循此路徑。產生的專案會將模組化 Xcode 專案的複雜性壓縮為簡潔、宣告式的圖形描述。這也是模組快取與選擇性測試的嚴格要求。

以下每個章節都會先說明目前缺少的部分，再逐步引導你使用填補該空缺的功能。

## 必要條件

- 已安裝 Xcode 的 macOS。
- <.localized_link href="/guides/install-tuist">Tuist 命令列介面</.localized_link>。

## 建立專案

最快看到運作效果的方式是建立一個全新專案。在空目錄中執行 `tuist init`，選擇 **建立產生的專案**，挑選平台，確認名稱，然後進行驗證並選擇應擁有該專案的帳號。

```bash
mkdir MyApp && cd MyApp
tuist init
```

如果你從程式碼代理或腳本驅動此流程，請先執行 `tuist auth login`（瀏覽器流程會等待你按下 Enter），然後使用非互動式表單：

```bash
tuist init --build-system generated-xcode --name MyApp --platform ios --account <account>
```

當 init 完成後，執行 `tuist generate`。Tuist 會在你的清單旁寫入一個 `.xcworkspace` 並在 Xcode 中開啟它。建置並執行目標。你應該會看到範例應用程式在模擬器中啟動。

這就是「已連線 + 正在產生」的狀態。以下內容皆為可選且獨立。

如果你要遷移現有應用程式，請先依照 [Xcode 專案遷移指南](https://tuist.dev/en/docs/guides/features/projects/adoption/migrate/xcode-project) 進行連線，然後回來繼續處理符合你問題的章節。

## 專案產生

`.xcodeproj` 將你的應用程式結構打包成 XML：檔案參考、建置階段、目標相依性、Scheme 以及建置設定都位於同一棵樹中，沒有用於將圖形作為圖形來推理的原語。隨著專案成長，這種結構會更難在腦海中掌握，而且 Xcode 沒有穩定的控制項供工具對其進行雜湊並在沒有任何變更時跳过工作。

產生的專案會將圖形壓縮為宣告式 Swift。`Project.swift` 直接描述目標、相依性和資源，而 Tuist 會在背後維護該圖形的穩定模型。正是這個模型解鎖了以下章節：模組快取會對其進行雜湊以重用二進位檔，選擇性測試也會對其進行雜湊以跳過輸入未變更的測試。

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

從頭編譯模組化 Xcode 專案是一種每台機器的成本。每位隊友和每個 CI 執行器都會產生相同物件檔案的一份副本。Xcode 編譯快取可以縮短內部迴圈，但無法消除每個目標的每台機器建置，也無法用預建二進位檔取代整個框架。

模組快取可以做到。它會建置圖形中每個可快取的相依性一次（框架、函式庫、套件），將產生的二進位檔依據目標輸入的雜湊值儲存，並在後續產生時將目標替換為其二進位檔。未變更的模組會停止編譯：

```bash
tuist cache
```

第一次執行會編譯所有內容並將二進位檔上傳至你的帳號。在下一次 `tuist generate` 時，未變更的相依性會被替換為其快取的二進位檔，Xcode 會連結 `.xcframework` 而非從原始碼編譯。

## 選擇性測試

`xcodebuild test` 不知道變更會影響哪些測試，因此 CI 會在每次推送時執行整個套件。隨著套件成長，實際需要執行的內容與實際執行內容之間的差距會從幾分鐘拉長到幾十分鐘。

選擇性測試只會執行自上次成功測試執行以來因變更而受影響的測試，使用專案圖形以及模組快取所依賴的相同雜湊演算法：

```bash
tuist test
```

第一次 `tuist test` 會執行所有內容並持久化每個目標的雜湊值。後續執行會跳過輸入未變更的目標。將 `tuist test` 移至 CI 中以取代 `xcodebuild test`，回饋將在幾秒內到達，而非幾分鐘。

## 套件註冊表

Swift Package Manager 透過深度複製每個套件的 git 歷史記錄來解析相依性，因為套件是透過 URL 定址而非註冊表。在擁有數十個傳遞性套件的專案中，解析在乾淨的檢出上會耗時數分鐘，並且在每個 CI 作業中重複執行。

Tuist 套件註冊表提供與 Swift Package Index 追蹤相同的套件，但作為真正的註冊表，因此 SwiftPM 僅抓取你實際需要的提交。只需在 `Tuist.swift` 中設定 `registryEnabled: true` 即可啟用一次：

```swift
let tuist = Tuist(
    project: .tuist(
        generationOptions: .options(
            registryEnabled: true
        )
    )
)
```

重新產生。套件解析時間從幾分鐘降至幾秒。

## 建置洞察

Xcode 會在日誌和建置報告中記錄每個目標的建置持續時間。兩者都不會跨執行或跨機器匯總，因此建置時間回歸通常只表現為整體 CI 變慢。

建置洞察會自動記錄每次建置的持續時間以及產生之 Scheme 的階段計時。無需額外設定。在下一次 `tuist generate` + 建置週期後，開啟儀表板的 **Builds** 分頁。

## 測試洞察

Xcode 一次報告每次執行的每個測試結果。它不會匯總你實際需要的跨執行訊號：不穩定率、週對週持續時間、哪些模擬器變體失敗。

測試洞察會自動記錄每次測試的結果和持續時間（針對產生的 Scheme），並關聯跨執行的結果。不穩定測試、緩慢測試和失敗會顯示在儀表板的 **Tests** 分頁。當不穩定情況累積時，請從儀表板隔離它們，以便它們不再阻擋合併。

## 帶領團隊一起使用

當所有人都使用相同的共享表面時，模組快取和選擇性測試的收益最大。從儀表板的帳號設定邀請你的隊友加入組織，並設定 <.localized_link href="/guides/integrations/authentication/sso">單一登入</.localized_link>（Google、Okta、Microsoft），讓入職成為一次點擊，而非每人執行一次 `tuist auth login`。
