---
{
  "title": "Bazel 專案",
  "titleTemplate": ":title · 開始使用 · 指南 · Tuist",
  "description": "將 Bazel 工作區連接至 Tuist，以便在 CI 中享有共享的遠端快取，以及建構與測試洞察，而無需更改任何 BUILD 檔案。"
}
---
# Bazel 專案 {#bazel-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/bazel-project
```

:::

按照以下步驟將現有的 Bazel workspace 接入 Tuist。Tuist 提供一個 [Remote Execution API](https://github.com/bazelbuild/remote-apis) 快取，讓 Bazel 以遠端快取方式連接；同時提供 Build Event Service 串流，將每次建構和測試轉化為儀表板上可見的數據。

以下每個章節都會先說明目前缺少的部分，再逐步介紹填補空缺的功能。

## 必要條件

- 一個 Bazel workspace（根目錄包含 `WORKSPACE` 或 `MODULE.bazel`），且 Bazel 已加入你的 `PATH`。
- <.localized_link href="/guides/install-tuist">Tuist 命令列介面</.localized_link>。

## 連接 workspace

在 Bazel workspace 的根目錄執行 `tuist init`。Tuist 會偵測到 `WORKSPACE` / `MODULE.bazel`，並提供 **整合 Bazel workspace** 選項。在瀏覽器中完成驗證，並選擇應擁有該專案的帳號。

```bash
tuist init
```

如果你透過編碼代理程式或腳本來執行，請先執行 `tuist auth login`（瀏覽器流程會等待你按下 Enter），然後使用非互動式形式：

```bash
tuist init --build-system bazel --name <project-handle> --account <account>
```

當 init 完成後，Tuist 會：

1. 在 workspace 根目錄寫入包含專案代號的 `tuist.toml`。
2. 在你的 `.bazelrc` 旁邊寫入 `.bazelrc.tuist`，連線至最近的 Tuist 快取區域，並透過每個 workspace 專屬的憑證輔助程式進行驗證。
3. 在你的 `.bazelrc` 中加入一行 `try-import %workspace%/.bazelrc.tuist`。

提交 `try-import` 這一行。它在每台機器上都相同。將 `.bazelrc.tuist` 加入你的 `.gitignore`。憑證輔助程式的路徑因使用者而異，快取區域則因位置而異，因此不應共用。

一旦 workspace 連接完成，以下所有功能都會自動啟用。

## 遠端快取

Bazel 本身的本機磁碟快取位於 `~/.cache/bazel`（或 `--disk_cache` 指向的位置）。某位開發者機器上的快取命中不會影響其他人，而且 CI 工作容器每次執行都從空快取開始。

Bazel 的 [Remote Execution API](https://github.com/bazelbuild/remote-apis) 是用來將同一個快取延伸至共用端點的協定。Tuist 支援此協定。一旦 `.bazelrc.tuist` 設定完成，Bazel 會略過輸出已存在於共用快取中的動作，改為直接下載。一台機器的工作成果會讓其他建構相同版本的機器受益。

針對相同版本執行兩次乾淨建構來驗證（在本機執行，或一次本機 + 一次 CI）：

```bash
bazel clean
bazel build //...
```

第二次執行的摘要應顯示快取命中。在儀表板上開啟 **快取** 以查看隨時間變化的命中率。

## 建構與測試洞察

Bazel 的建構事件串流和每個測試的 XML 報告會在每次叫用時產生。要比較一週內目標層級的持續時間，或找出在多次 CI 執行中變得閃爍不穩定的測試，就必須在某處收集並匯總這些事件。

Bazel 已經發出的 Build Event Service 協定正是為此設計。`tuist init` 所寫入的 `.bazelrc.tuist` 會將 BES 串流設定為對接 Tuist，因此在下一次 `bazel build` 和 `bazel test` 時，建構與測試洞察就會開始流入。無需額外設定。在儀表板上開啟 **建構** 和 **測試** 即可查看數據。

## 邀請團隊加入

快取命中和洞察會隨著連接專案的人數增加而累積效應。從儀表板的帳號設定邀請隊友加入組織，並設定 <.localized_link href="/guides/integrations/authentication/sso">單一登入</.localized_link>（Google、Okta、Microsoft），讓新人加入只需點擊一下，而不需要每人執行 `tuist auth login`。
