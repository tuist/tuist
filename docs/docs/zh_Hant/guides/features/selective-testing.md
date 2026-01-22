---
{
  "title": "Selective testing",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Use selective testing to run only the tests that have changed since the last successful test run."
}
---
# 選擇性測試{#selective-testing}

隨著專案的成長，測試的數量也在增加。長久以來，在每個 PR 或推送到`主網站` 時執行所有測試需要數十秒的時間。但此解決方案無法擴充至團隊可能擁有的數千個測試。

每次在 CI 上執行測試時，您很可能會重新執行所有的測試，而不考慮變更的情況。Tuist 的選擇性測試會根據我們的
<LocalizedLink href="/guides/features/projects/hashing">hashing
演算法</LocalizedLink>，只執行上次成功執行測試之後有變更的測試，幫助您大幅加快執行測試的速度。

To run tests selectively with your
<LocalizedLink href="/guides/features/projects">generated
project</LocalizedLink>, use the `tuist test` command. The command
<LocalizedLink href="/guides/features/projects/hashing">hashes</LocalizedLink>
your Xcode project the same way it does for the
<LocalizedLink href="/guides/features/cache/module-cache">module
cache</LocalizedLink>, and on success, it persists the hashes to determine what
has changed in future runs. In future runs, `tuist test` transparently uses the
hashes to filter down the tests and run only the ones that have changed since
the last successful test run.

`tuist test` integrates directly with the
<LocalizedLink href="/guides/features/cache/module-cache">module
cache</LocalizedLink> to use as many binaries from your local or remote storage
to improve the build time when running your test suite. The combination of
selective testing with module caching can dramatically reduce the time it takes
to run tests on your CI.

::: warning MODULE VS FILE-LEVEL GRANULARITY
<!-- -->
由於無法偵測測試與來源之間的程式碼內依賴關係，選擇性測試的最大粒度是在目標層級。因此，我們建議將您的目標保持在較小且集中的層級，以發揮選擇性測試的最大效益。
<!-- -->
:::

::: warning TEST COVERAGE
<!-- -->
測試覆蓋率工具假設整個測試套件一次執行，這使得它們與選擇性測試執行不相容 -
這表示使用測試選擇時，覆蓋率資料可能無法反映現實。這是已知的限制，但這並不表示您做錯了什麼。我們鼓勵團隊反思在此情境下，覆蓋率是否仍能帶來有意義的洞察力，如果是的話，請放心，我們已經在思考未來如何讓覆蓋率與選擇性執行正常運作。
<!-- -->
:::


## 拉取/合併請求註解{#pullmerge-request-comments}

::: warning INTEGRATION WITH GIT PLATFORM REQUIRED
<!-- -->
若要取得自動的 pull/merge 請求註解，請將您的
<LocalizedLink href="/guides/server/accounts-and-projects">Tuist
專案</LocalizedLink>與 <LocalizedLink href="/guides/server/authentication">Git
平台</LocalizedLink>整合。
<!-- -->
:::

Once your Tuist project is connected with your Git platform such as
[GitHub](https://github.com), and you start using `tuist test` as part of your
CI workflow, Tuist will post a comment directly in your pull/merge requests,
including which tests were run and which skipped: ![GitHub app comment with a
Tuist Preview
link](/images/guides/features/selective-testing/github-app-comment.png)
