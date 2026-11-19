---
{
  "title": "Bazel 專案",
  "titleTemplate": ":title · 快速入門 · 指南 · Tuist",
  "description": "將 Bazel 工作區與 Tuist 連接，以取得共享的遠端快取，並在 CI 中獲得建置與測試洞察，無需變更任何 BUILD 檔案。"
}
---
# Bazel 專案 {#bazel-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/bazel-project
```

:::

依照此路徑將現有的 Bazel 工作區接入 Tuist。Tuist 提供一個 [Remote Execution API](https://github.com/bazelbuild/remote-apis) 快取，Bazel 可將其作為遠端快取連線；同時提供 Build Event Service 串流，將每次建置與測試轉化為儀表板上可見的資料。若要了解 Tuist 為 Bazel 帶來哪些增強，請參閱 [Bazel with Tuist](https://tuist.dev/build-systems/bazel)。如果你正從其他 Bazel 供應商遷移，[BuildBuddy](https://tuist.dev/compare/buildbuddy) 與 [EngFlow](https://tuist.dev/compare/engflow) 的比較文章會說明變更內容。

以下各節先說明目前缺少的部分，再逐步引導你使用填補該空缺的功能。

## 必要條件

- 一個 Bazel 工作區（根目錄包含 `WORKSPACE` 或 `MODULE.bazel`），且 Bazel 已加入你的 `PATH`。
- <.localized_link href="/guides/install-tuist">Tuist 命令列介面</.localized_link>。

## 連接工作區

在 Bazel 工作區的根目錄執行 `tuist init`。Tuist 會偵測到 `WORKSPACE` / `MODULE.bazel`，並提供 **Integrate a Bazel workspace** 選項。在瀏覽器中完成驗證，並選擇應擁有該專案的帳號。

```bash
tuist init
```

若由編碼代理程式或腳本驅動此流程，請先執行 `tuist auth login`（瀏覽器流程會等待你按下 Enter），然後使用非互動式形式：

```bash
tuist init --build-system bazel --name <project-handle> --account <account>
```

當 init 完成時，Tuist 會：

1. 在工作區根目錄寫入包含專案代號的 `tuist.toml`。
2. 在你的 `.bazelrc` 旁寫入 `.bazelrc.tuist`，並連線至最近的 Tuist 快取區域，透過每個工作區專屬的憑證輔助工具進行驗證。
3. 在你的 `.bazelrc` 中加入一行 `try-import %workspace%/.bazelrc.tuist`。

提交 `try-import` 這一行。它在每台機器上都相同。將 `.bazelrc.tuist` 加入你的 `.gitignore`。憑證輔助工具的路徑依使用者而異，快取區域依位置而異，因此不應共享。

一旦工作區連接完成，以下功能會自動啟用。

## 遠端快取

Bazel 本身的本地磁碟快取位於 `~/.cache/bazel`（或 `--disk_cache` 指向的位置）。某位開發者機器上的快取命中不會影響其他人，且 CI 工作容器每次執行都從空快取開始。

Bazel 的 [Remote Execution API](https://github.com/bazelbuild/remote-apis) 是用來將該快取擴展至共享端點的協定。Tuist 支援此協定。一旦 `.bazelrc.tuist` 就緒，Bazel 會略過輸出已存在於共享快取中的動作，並改為下載它們。一台機器的成果將惠及所有建置相同修訂版本的其他機器。

針對相同修訂版本執行兩次乾淨建置以驗證（本地兩次，或一次本地 + 一次 CI）：

```bash
bazel clean
bazel build //...
```

第二次執行的摘要應回報快取命中。在儀表板上開啟 **Cache** 以查看隨時間變化的命中率。

## 建置與測試洞察

Bazel 的建置事件串流與每項測試的 XML 報告會在每次叫用時產生。若要比較一週內目標層級的持續時間，或找出在多次 CI 執行中變得間歇性失敗的測試，就必須在某處收集並彙整這些事件。

Bazel 已發出的 Build Event Service 協定正是為此設計。`tuist init` 所寫入的 `.bazelrc.tuist` 會將 BES 串流設定為對接 Tuist，因此在下一次 `bazel build` 與 `bazel test` 時，建置與測試洞察就會開始流入。無需額外設定。在儀表板上開啟 **Builds** 與 **Tests** 即可查看資料。

## 邀請團隊成員加入

快取命中與洞察會隨著連接到專案的人數增加而累積效益。從儀表板的帳號設定邀請隊友加入組織，並設定 <.localized_link href="/guides/integrations/authentication/sso">Single Sign-On</.localized_link>（Google、Okta、Microsoft），讓新人加入只需點擊即可完成，而非每人都要執行 `tuist auth login`。
