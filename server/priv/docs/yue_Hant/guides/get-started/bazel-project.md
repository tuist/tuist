---
{
  "title": "Bazel 專案",
  "titleTemplate": ":title · 入門指南 · 教學指南 · Tuist",
  "description": "將 Bazel 工作區連接至 Tuist，以便在 CI 中享有共享的遠端快取，以及建構與測試洞察，而無需修改任何 BUILD 檔案。"
}
---
# Bazel 專案 {#bazel-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/bazel-project
```

:::

按照此步驟將現有的 Bazel workspace 接入 Tuist。Tuist 提供一個 [Remote Execution API](https://github.com/bazelbuild/remote-apis) 快取，Bazel 可將其連接為遠端快取；同時提供 Build Event Service 串流，將每次建構與測試轉化為儀表板上可見的數據。

以下每個章節會先說明目前缺少的部分，再逐步介紹填補該空缺的功能。

## 前置條件

- 一個 Bazel workspace（根目錄包含 `WORKSPACE` 或 `MODULE.bazel`），以及已加入 `PATH` 的 Bazel。
- <.localized_link href="/guides/install-tuist">Tuist 命令列介面</.localized_link>。

## 連接 workspace

> [!NOTE]
> `tuist init` 內的 Bazel 工作流程需要隨附的 Tuist CLI 版本。在較早的發行版中，`tuist init` 不會列出「Integrate a Bazel workspace」作為選項。請改為從 workspace 根目錄執行 `tuist auth login`，接著執行 `tuist bazel setup`，這兩者會引導你完成以下相同步驟。

從 Bazel workspace 的根目錄執行 `tuist init`。Tuist 會偵測到 `WORKSPACE` / `MODULE.bazel`，並提供 **Integrate a Bazel workspace**。在瀏覽器中完成驗證，並選擇應擁有該專案的帳戶。

```bash
tuist init
```

如果你透過編碼代理程式或腳本來執行，請先執行 `tuist auth login`（瀏覽器流程會等待你按下 Enter），然後使用非互動式形式：

```bash
tuist init --build-system bazel --name <project-handle> --account <account>
```

當 init 完成時，Tuist 會：

1. 在 workspace 根目錄寫入包含專案代號的 `tuist.toml`。
2. 在你的 `.bazelrc` 旁邊寫入 `.bazelrc.tuist`，並連線至最近的 Tuist 快取區域，且透過每個 workspace 專屬的憑證輔助工具進行驗證。
3. 在你的 `.bazelrc` 中加入一行 `try-import %workspace%/.bazelrc.tuist`。

提交 `try-import` 這一行。它在每台機器上都相同。將 `.bazelrc.tuist` 加入你的 `.gitignore`。憑證輔助工具的路徑是每位使用者專屬，快取區域則依位置而定，因此不應共享。

一旦 workspace 連接完成，以下所有功能都會自動啟用。

## 遠端快取

Bazel 自身的本機磁碟快取位於 `~/.cache/bazel`（或 `--disk_cache` 指向的位置）。某位開發者機器上的快取命中不會惠及他人，而 CI 工作容器每次執行都從空快取開始。

Bazel 的 [Remote Execution API](https://github.com/bazelbuild/remote-apis) 是用來將同一個快取延伸至共享端點的通訊協定。Tuist 支援此協定。一旦設定好 `.bazelrc.tuist`，Bazel 會跳過輸出已存在於共享快取中的動作，並改為下載它們。一台機器的成果將惠及所有建構相同修訂版本的其他機器。

針對相同修訂版本執行兩次乾淨建構來驗證（在本機，或一次本機 + 一次 CI）：

```bash
bazel clean
bazel build //...
```

第二次執行的摘要應顯示快取命中。在儀表板開啟 **Cache** 以查看隨時間變化的命中率。

## 建構與測試洞察

Bazel 的建構事件串流及每項測試的 XML 報告會在每次叫用時產生。若要比較一週內目標層級的耗時，或找出在多次 CI 執行中變得不穩定的測試，就需要在某處收集並匯總這些事件。

Bazel 已發出的 Build Event Service 通訊協定正是為此設計。`tuist init` 所寫入的 `.bazelrc.tuist` 會將 BES 串流設定為對接 Tuist，因此在下一次 `bazel build` 和 `bazel test` 時，建構與測試洞察就會開始流入。無需額外設定。在儀表板開啟 **Builds** 和 **Tests** 即可查看數據。

## 邀請團隊成員加入

快取命中與洞察會隨著連接到專案的人數增加而累積效益。從儀表板的帳戶設定邀請隊友加入組織，並設定 <.localized_link href="/guides/integrations/authentication/sso">Single Sign-On</.localized_link>（Google、Okta、Microsoft），讓入職流程只需點擊一下，而非每人執行一次 `tuist auth login`。
