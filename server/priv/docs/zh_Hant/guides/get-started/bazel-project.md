---
{
  "title": "Bazel 專案",
  "titleTemplate": ":title · 開始使用 · 指南 · Tuist",
  "description": "將 Bazel 工作區連接至 Tuist，即可在 CI 中享有共用的遠端快取，並獲得建置與測試洞察，且無需變更任何 BUILD 檔案。"
}
---
# Bazel 專案 {#bazel-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/bazel-project
```

:::

按照此流程將現有的 Bazel 工作區接入 Tuist。Tuist 提供一個 [Remote Execution API](https://github.com/bazelbuild/remote-apis) 快取，Bazel 可將其作為遠端快取連接；同時提供 Build Event Service 串流，將每次建置與測試轉化為儀表板上可見的資料。

以下每個章節都會先說明目前缺少的部分，再逐步帶你使用填補該缺口的功能。

## 必要條件

- 一個 Bazel 工作區（根目錄包含 `WORKSPACE` 或 `MODULE.bazel`），且 Bazel 已加入你的 `PATH`。
- <.localized_link href="/guides/install-tuist">Tuist 命令列介面</.localized_link>。

## 連接工作區

> [!NOTE]
> `tuist init` 內的 Bazel 工作流程需要隨附的 Tuist CLI 版本。在較早的發行版中，`tuist init` 不會列出「Integrate a Bazel workspace」作為選項。請改為從工作區根目錄執行 `tuist auth login`，接著執行 `tuist bazel setup`，即可依照下方相同的步驟進行。

在 Bazel 工作區的根目錄執行 `tuist init`。Tuist 會偵測到 `WORKSPACE` / `MODULE.bazel`，並提供 **Integrate a Bazel workspace**。在瀏覽器中完成驗證，並選擇應擁有此專案的帳號。

```bash
tuist init
```

若由編碼代理程式或腳本驅動此流程，請先執行 `tuist auth login`（瀏覽器流程會等待你按下 Enter），然後使用非互動式形式：

```bash
tuist init --build-system bazel --name <project-handle> --account <account>
```

init 完成後，Tuist 會：

1. 在工作區根目錄寫入包含專案代號的 `tuist.toml`。
2. 在你的 `.bazelrc` 旁寫入 `.bazelrc.tuist`，連線至最近的 Tuist 快取區域，並透過每個工作區專屬的憑證輔助程式進行驗證。
3. 在你的 `.bazelrc` 中加入一行 `try-import %workspace%/.bazelrc.tuist`。

提交 `try-import` 這一行。它在每台機器上都相同。將 `.bazelrc.tuist` 加入你的 `.gitignore`。憑證輔助程式的路徑因使用者而異，快取區域則依位置而定，因此不應共享。

一旦工作區連接完成，以下所有功能都會自動啟用。

## 遠端快取

Bazel 自身的本機磁碟快取位於 `~/.cache/bazel`（或 `--disk_cache` 指向的位置）。某位開發者機器上的快取命中無法惠及他人，而 CI 工作容器每次執行都從空快取開始。

Bazel 的 [Remote Execution API](https://github.com/bazelbuild/remote-apis) 是用來將同一個快取延伸至共享端點的通訊協定。Tuist 支援此協定。一旦 `.bazelrc.tuist` 就緒，Bazel 會跳過輸出已存在於共享快取中的動作，改為直接下載。一台機器的成果能惠及所有建置相同修訂版本的其他機器。

針對相同修訂版本執行兩次乾淨建置以驗證（本機兩次，或一次本機加一次 CI）：

```bash
bazel clean
bazel build //...
```

第二次執行的摘要應顯示快取命中。在儀表板開啟 **Cache** 即可查看隨時間變化的命中率。

## 建置與測試洞察

Bazel 的建置事件串流與每項測試的 XML 報告會在每次叫用時產生。若要比較一週內目標層級的耗時，或找出在多次 CI 執行中變得間歇性失敗的測試，就需要在某處收集並彙整這些事件。

Bazel 已發出的 Build Event Service 通訊協定正是為此設計。`tuist init` 所寫入的 `.bazelrc.tuist` 會將 BES 串流設定為對接 Tuist，因此在下一次 `bazel build` 與 `bazel test` 時，建置與測試洞察就會開始流入。無需額外設定。在儀表板開啟 **Builds** 與 **Tests** 即可查看資料。

## 邀請團隊成員加入

快取命中與洞察會隨著連接到專案的人數增加而累積效益。從儀表板的帳號設定邀請隊友加入組織，並設定 <.localized_link href="/guides/integrations/authentication/sso">Single Sign-On</.localized_link>（Google、Okta、Microsoft），讓新人加入只需點擊即可完成，而非每人都要執行 `tuist auth login`。
