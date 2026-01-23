---
{
  "title": "Translate",
  "titleTemplate": ":title · Contributors · Tuist",
  "description": "This document describes the principles that guide the development of Tuist."
}
---
# 翻譯{#translate}

語言可能成為理解的障礙。我們致力讓 Tuist 能觸及盡可能多的人群。若您使用的語言尚未獲 Tuist 支援，歡迎協助翻譯 Tuist 的各類介面元素。

由於翻譯維護屬持續性工作，我們將視貢獻者意願協助維護的情況逐步新增語言。目前支援以下語言：

- 英文
- 韓文
- 日文
- 俄文
- 中文
- 西班牙文
- 葡萄牙語

::: tip REQUEST A NEW LANGUAGE
<!-- -->
若您認為 Tuist 支援新增語言將有所助益，請至社群論壇建立新主題(https://community.tuist.io/c/general/4)
與社群成員共同討論。
<!-- -->
:::

## 翻譯指南{#how-to-translate}

我們在 [translate.tuist.dev](https://translate.tuist.dev) 運行著
[Weblate](https://weblate.org/en-gb/) 實例。您可前往
[該專案](https://translate.tuist.dev/engage/tuist/)，建立帳號後即可開始翻譯。

翻譯內容將透過 GitHub 拉取請求同步回原始儲存庫，維護者將進行審查與合併。

::: warning DON'T MODIFY THE RESOURCES IN THE TARGET LANGUAGE
<!-- -->
Weblate 會將檔案分割成區段以綁定源語言與目標語言。若修改源語言內容，將破壞語言綁定關係，後續對照可能產生意外結果。
<!-- -->
:::

## 指南{#guidelines}

以下為我們進行翻譯時遵循的準則：

### 自訂容器與 GitHub 警示{#custom-containers-and-github-alerts}

翻譯[自訂容器](https://vitepress.dev/guide/markdown#custom-containers)時，僅翻譯標題與內容欄位**，勿翻譯警示類型欄位**
。

```markdown
<!-- -->
::: warning 루트 변수
<!-- -->
매니페스트의 루트에 있어야 하는 변수는...
<!-- -->
:::
```

### 標題名稱{#heading-titles}

翻譯標題時，僅翻譯標題文字而不翻譯標識符。例如翻譯以下標題時：

```markdown
# Add dependencies {#add-dependencies}
```

應翻譯為（請注意ID字段不作翻譯）：

```markdown
# 의존성 추가하기 {#add-dependencies}
```
