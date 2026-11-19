---
{
  "title": "生成的 Xcode 專案",
  "titleTemplate": ":title · 開始使用 · 指南 · Tuist",
  "description": "將模組化的 Xcode 專案壓縮為宣告式 Swift，並解鎖模組快取、選擇性測試、套件註冊表，以及在圖譜之上提供的構建與測試洞察。"
}
---
# 已生成嘅 Xcode 專案 {#generated-xcode-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/generated-xcode-project
```

:::

當你想讓 Tuist 透過 Swift manifest 描述並生成你嘅 Xcode 專案時，請跟隨此路徑。已生成嘅專案將模組化 Xcode 專案嘅複雜性壓縮為圖形嘅簡潔、聲明式描述。這亦係模組快取同選擇性測試嘅嚴格要求。

以下每個章節都會先指出目前欠缺咩，然後帶你了解填補該空缺嘅功能。

## 先決條件

- 已安裝 Xcode 嘅 macOS。
- <.localized_link href="/guides/install-tuist">Tuist 命令列介面</.localized_link>。

## 建立專案

最快見到成效嘅方法係從一個全新專案開始。喺空目錄中執行 `tuist init` 並選擇 **建立已生成嘅專案**，揀選平台，確認名稱，然後進行身份驗證並揀選應該擁有該專案嘅帳戶。

```bash
mkdir MyApp && cd MyApp
tuist init
```

如果你係透過編碼代理或腳本驅動此過程，請先執行 `tuist auth login`（瀏覽器流程會等你按 Enter），然後使用非互動式形式：

```bash
tuist init --build-system generated-xcode --name MyApp --platform ios --account <account>
```

當 init 完成後，執行 `tuist generate`。Tuist 會喺你嘅 manifest 旁邊寫入一個 `.xcworkspace` 並喺 Xcode 中打開它。建置並執行目標。你應該會看到範例應用程式喺模擬器中啟動。

這就是「已連接 + 正在生成」狀態。以下所有內容均為可選且獨立。

如果你要遷移現有應用程式，請先使用 [Xcode 專案遷移指南](https://tuist.dev/en/docs/guides/features/projects/adoption/migrate/xcode-project) 將其連接，然後返回並繼續處理適合你問題嘅章節。

## 專案生成

`.xcodeproj` 將你應用程式嘅結構打包成 XML：檔案參考、建置階段、目標依賴項、scheme 同建置設定都位於同一棵樹中，沒有用於將圖形作為圖形進行推理嘅原語。隨著專案增長，這種結構越來越難以喺腦海中掌握，而且 Xcode 沒有穩定嘅句柄供工具對其進行哈希處理並喺沒有任何更改時跳過工作。

已生成嘅專案將圖形壓縮為聲明式 Swift。`Project.swift` 直接描述目標、依賴項同資源，而 Tuist 喺背後保持圖形嘅穩定模型。該模型解鎖咗以下章節：模組快取對其進行哈希以重用二進制文件，而選擇性測試對其進行哈希以跳過輸入未更改嘅測試。

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

每次 `tuist generate` 都會從 manifest 產生一個確定性工作區。將 `.xcodeproj` 同 `.xcworkspace` 加入 `.gitignore`。

## 模組快取

從頭開始編譯模組化 Xcode 專案係每台機器嘅成本。每位隊友同每個 CI runner 都會產生自己嘅相同物件檔案副本。Xcode 編譯快取縮短咗內部循環，但並未消除每個目標嘅每台機器建置，而且無法用預建二進制文件替換整個框架。

模組快取可以做到。它只建置一次圖形中每個可快取嘅依賴項（框架、庫、bundle），將結果二進制文件根據目標輸入嘅哈希值存儲，並喺後續生成中用其二進制文件替換目標。未更改嘅模組停止編譯：

```bash
tuist cache
```

第一次運行會編譯所有內容並將二進制文件上傳到你嘅帳戶。喺下一次 `tuist generate` 時，未更改嘅依賴項會被其快取二進制文件替換，Xcode 會連結 `.xcframework` 而不是從源代碼編譯。

## 選擇性測試

`xcodebuild test` 不知道更改影響咗哪些測試，所以 CI 每次推送都會運行整個套件。隨著套件增長，實際需要運行嘅內容同實際運行內容之間嘅差距從幾分鐘延長到幾十分鐘。

選擇性測試只運行自上次成功測試執行以來受更改影響嘅測試，使用專案圖形同模組快取所依賴嘅相同哈希算法：

```bash
tuist test
```

第一次 `tuist test` 會運行所有內容並持久保存每個目標嘅哈希值。後續運行會跳過輸入未更改嘅目標。將 `tuist test` 移入 CI 以取代 `xcodebuild test`，反饋會喺幾秒鐘內到達而不是幾分鐘。

## 套件註冊表

Swift Package Manager 透過深度克隆每個套件嘅 git 歷史來解析依賴項，因為套件係通過 URL 而不是註冊表尋址。喺具有數十個傳遞性套件嘅專案中，解析喺乾淨簽出時需要幾分鐘，並且喺每個 CI 作業中重複。

Tuist Package Registry 提供與 Swift Package Index 追蹤嘅相同套件，但作為真實註冊表，因此 SwiftPM 只獲取你實際需要嘅提交。透過喺你嘅 `Tuist.swift` 中設置 `registryEnabled: true` 來啟用一次：

```swift
let tuist = Tuist(
    project: .tuist(
        generationOptions: .options(
            registryEnabled: true
        )
    )
)
```

重新生成。套件解析時間從幾分鐘降至幾秒。

## 建置洞察

Xcode 喺日誌同建置報告中記錄每個目標嘅建置持續時間。兩者都沒有跨運行或跨機器聚合，因此建置時間回歸通常只表現為整體 CI 變慢。

Build insights 自動記錄每次建置嘅持續時間同生成 scheme 嘅階段計時。無需額外配置。喺你下次 `tuist generate` + 建置循環後，打開儀表板嘅 **Builds** 標籤。

## 測試洞察

Xcode 每次運行報告一次每個測試嘅結果。它沒有聚合你實際需要嘅跨運行信號：不穩定率、週同比持續時間、哪些模擬器變體失敗。

Test insights 自動記錄每次測試嘅結果同持續時間以生成 scheme，並關聯跨運行嘅結果。不穩定測試、慢速測試同失敗會顯示喺儀表板嘅 **Tests** 標籤上。當不穩定情況累積時，從儀表板隔離它們，以便它們停止阻止合併。

## 帶領團隊一起

當每個人都在訪問相同嘅共享表面時，模組快取同選擇性測試嘅回報最大。從儀表板上嘅帳戶設置邀請你嘅隊友加入組織，並設置 <.localized_link href="/guides/integrations/authentication/sso">單一登入</.localized_link>（Google、Okta、Microsoft），以便入職只需點擊一下，而不是每人執行一次 `tuist auth login`。
