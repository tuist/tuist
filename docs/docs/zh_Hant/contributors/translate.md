---
{
  "title": "Translate",
  "titleTemplate": ":title · Contributors · Tuist",
  "description": "This document describes the principles that guide the development of Tuist."
}
---
# 翻譯{#translate}

語言可能是理解的障礙。我們希望確保盡量多的人都能使用 Tuist。如果您使用的語言是 Tuist 不支援的，您可以幫助我們翻譯 Tuist 的各種表面。

由於維護翻譯是一項持續性的工作，因此我們會在看到有貢獻者願意協助我們維護時，才會增加語言。目前支援下列語言：

- 英語
- 韓語
- 日本語
- 俄語
- 中文
- 西班牙語
- 葡萄牙語

::: tip REQUEST A NEW LANGUAGE
<!-- -->
如果您認為 Tuist 可以從支援新語言中獲益，請在社群論壇中建立一個新的
[主題](https://community.tuist.io/c/general/4)，與社群進行討論。
<!-- -->
:::

## 如何翻譯{#how-to-translate}

我們在 [translate.tuist.dev](https://translate.tuist.dev) 有一個
[Weblate](https://weblate.org/en-gb/) 的實例在執行。您可以前往
[專案](https://translate.tuist.dev/engage/tuist/)，建立帳號並開始翻譯。

翻譯會使用 GitHub 的拉取請求同步回原始碼倉庫，維護人員會審查並合併。

::: warning DON'T MODIFY THE RESOURCES IN THE TARGET LANGUAGE
<!-- -->
Weblate 會分割檔案以綁定源語言和目標語言。如果您修改來源語言，就會破壞綁定，而且調和可能會產生意想不到的結果。
<!-- -->
:::

## 指引{#guidelines}

以下是我們在翻譯時遵循的準則。

### 自訂容器和 GitHub 警示{#custom-containers-and-github-alerts}

翻譯 [custom containers](https://vitepress.dev/guide/markdown#custom-containers)
時，只翻譯標題和內容**，但不翻譯警示類型** 。

```markdown
<!-- -->
::: warning 루트 변수
<!-- -->
매니페스트의 루트에 있어야 하는 변수는...
<!-- -->
:::
```

### 標題標題{#heading-titles}

翻譯標題時，只翻譯標題而不翻譯 ID。例如，翻譯以下標題時：

```markdown
# Add dependencies {#add-dependencies}
```

應該翻譯為（注意 id 沒有翻譯）：

```markdown
# 의존성 추가하기 {#add-dependencies}
```
