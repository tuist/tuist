---
{
  "title": "Cache",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Optimize build times with Tuist Cache, including module cache, Xcode cache, Gradle cache, and Bazel cache."
}
---
# 快取 {#cache}

建構產物無法在不同環境之間共用，導致你必須不斷重新建構相同的程式碼。Tuist 的快取功能可遠端共用產物，讓你的團隊和 CI 無需重複建構已建構的內容，從而加快建構速度。

了解符合你專案或部署模型的快取工作流程：

\<.home\_cards\>
\<.home\_card
title="模組快取"
details="將個別模組快取為二進位檔，適用於使用 Tuist 產生之專案的項目。需要 Tuist 專案產生功能。"
link="/guides/features/cache/module-cache"
/\>
\<.home\_card
title="Xcode 快取"
details="在不同環境之間共用 Xcode 編譯產物。適用於任何 Xcode 專案，無需專案產生功能。"
link="/guides/features/cache/xcode-cache"
/\>
\<.home\_card
title="Gradle 快取"
details="遠端共用 Gradle 建構快取產物。包含建構洞察功能，以提升效能可見度。"
link="/guides/features/cache/gradle-cache"
/\>
\<.home\_card
title="Bazel 快取"
details="將 Bazel 指向 Tuist 的 Remote Execution API 快取，以便在團隊和 CI 之間共用動作輸出。"
link="/guides/features/cache/bazel-cache"
/\>
\<.home\_card
title="自行託管"
details="在靠近 CI、辦公室或區域運算資源的位置執行快取節點，並將它們連接至託管或自行託管的 Tuist。"
link="/guides/features/cache/self-hosting"
/\>
\</.home\_cards\>

> \[\!TIP\]
> **在 Tuist Runners 上速度最快**
> 
> 在 \<.localized\_link href="/guides/features/runners"\>Tuist Runners\</.localized\_link\> 上，快取位於執行器的私人網路中，並與開發人員機器使用的相同快取共用，因此 CI 工作預設即可獲得熱命中，無需額外預熱獨立的 CI 快取。

## 限制僅限 CI 上傳 {#restrict-uploads-to-ci}

帳戶管理員可以將開發人員設定為唯讀，同時允許 CI 上傳快取產物。在 Tuist 中開啟帳戶的 **Cache** 設定，並將 **Cache upload access** 設定為 **CI and account tokens only**。完成後，透過登入工作階段驗證的成員仍然可以從快取下載，但上傳需要 CI OIDC 驗證或具有快取寫入範圍（例如 `project:cache:write` 或 `ci`）的帳戶權杖。

當 CI 是受信任的快取生產者，而本機機器僅應消費快取時，請使用此設定。此設定僅影響快取上傳授權。