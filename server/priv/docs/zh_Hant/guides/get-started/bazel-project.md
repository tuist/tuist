---
{
  "title": "Bazel project",
  "titleTemplate": ":title · Get started · Guides · Tuist",
  "description": "Connect a Bazel workspace to Tuist for a shared remote cache and build and test insights across CI, without changing any BUILD file."
}
---
# Bazel 專案 {#bazel-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/bazel-project
```

:::

依照此路徑將現有的 Bazel 工作區整合至 Tuist。Tuist 提供一個 [Remote Execution API](https://github.com/bazelbuild/remote-apis) 快取，Bazel 可將其作為遠端快取連接，並提供 Build Event Service 串流，將每次建構與測試轉化為儀表板上可見的資料。

以下每個章節都會先說明目前缺少的部分，再逐步引導你使用能填補該空缺的功能。

## 必要條件

- 一個 Bazel 工作區（根目錄包含 `WORKSPACE` 或 `MODULE.bazel`），且 Bazel 已加入你的 `PATH`。
- <.localized_link href="/guides/install-tuist">Tuist 命令列介面</.localized_link>。

## 連接工作區

> [!NOTE]
> `tuist init` 內的 Bazel 工作流程需要隨附的 Tuist CLI 版本。在較早的發行版中，`tuist init` 不會列出「Integrate a Bazel workspace」作為選項。請改為從工作區根目錄執行 `tuist auth login`，接著執行 `tuist bazel setup`，這會引導你完成以下相同步驟。

從 Bazel 工作區的根目錄執行 `tuist init`。Tuist 會偵測到 `WORKSPACE` / `MODULE.bazel` 並提供 **Integrate a Bazel workspace**。在瀏覽器中進行驗證，並選擇應擁有該專案的帳號。

```bash
tuist init
```

如果你是由程式碼代理程式或腳本驅動此流程，請先執行 `tuist auth login`（瀏覽器流程會等待你按下 Enter），然後使用非互動式形式：

```bash
tuist init --build-system bazel --name <project-handle> --account <account>
```

當 init 完成時，Tuist 會：

1. 在工作區根目錄寫入一個包含專案代號的 `tuist.toml`。
2. 在你的 `.bazelrc` 旁邊寫入一個 `.bazelrc.tuist`，連線至最近的 Tuist 快取區域，並透過每個工作區的憑證輔助工具進行驗證。
3. 在你的 `.bazelrc` 中加入一行 `try-import %workspace%/.bazelrc.tuist`。

提交 `try-import` 這一行。它在每台機器上都相同。將 `.bazelrc.tuist` 加入你的 `.gitignore`。憑證輔助工具的路徑是每位使用者專屬，快取區域則依位置而定，因此不應共用。

一旦工作區連接完成，以下所有功能都會自動啟用。

## 遠端快取

Bazel 自身的本機磁碟快取位於 `~/.cache/bazel`（或 `--disk_cache` 指向的位置）。在一位開發者的機器上命中快取並不會讓其他人受益，且 CI 工作容器每次執行都從空快取開始。

Bazel 的 [Remote Execution API](https://github.com/bazelbuild/remote-apis) 是用來將同一個快取延伸至共用端點的協定。Tuist 支援此協定。一旦 `.bazelrc.tuist` 就緒，Bazel 會跳過輸出已存在於共用快取中的動作，並改為下載它們。一台機器的成果將惠及所有建構相同修訂版本的其他機器。

針對相同修訂版本執行兩次乾淨建構以進行驗證（在本機，或一次本機 + 一次 CI）：

```bash
bazel clean
bazel build //...
```

第二次執行的摘要應報告快取命中。在儀表板上開啟 **Cache** 以查看隨時間變化的命中率。

## 建構與測試洞察

Bazel 的建構事件串流與每項測試的 XML 報告會在每次叫用時產生。若要比較一週內目標層級的持續時間，或找出在多次 CI 執行中變得不穩定的測試，就需要在某處收集並彙總這些事件。

Bazel 已發出的 Build Event Service 協定正是為此設計。`tuist init` 所寫入的 `.bazelrc.tuist` 會將 BES 串流設定為對接 Tuist，因此在下一次 `bazel build` 和 `bazel test` 時，建構與測試洞察就會開始流入。無需額外設定。在儀表板上開啟 **Builds** 和 **Tests** 即可查看資料。

## 邀請團隊成員加入

快取命中與洞察會隨著連接至專案的人數增加而累積效益。從儀表板的帳號設定邀請隊友加入組織，並設定 <.localized_link href="/guides/integrations/authentication/sso">Single Sign-On</.localized_link>（Google、Okta、Microsoft），讓新人加入只需點擊一下，而非每人執行一次 `tuist auth login`。
