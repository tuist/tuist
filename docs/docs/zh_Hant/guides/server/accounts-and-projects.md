---
{
  "title": "Accounts and projects",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "Learn how to create and manage accounts and projects in Tuist."
}
---
# 帳戶與專案{#accounts-and-projects}

某些 Tuist 功能需要伺服器支援，該伺服器可提供資料持久化並與其他服務互動。欲與伺服器互動，您需擁有帳戶及專案，並將其連結至您的本地專案。

## 帳戶{#accounts}

使用本服務需先註冊帳號。帳號分為兩種類型：

- **個人帳戶：** 這些帳戶於註冊時自動建立，其識別碼取自身分提供者（如 GitHub）或電子郵件地址的前段部分。
- **組織帳戶：** 此類帳戶需手動建立，並由開發者定義的識別碼標記。組織功能可邀請其他成員共同參與專案協作。

若您熟悉[GitHub](https://github.com)，其概念與之類似：您可擁有個人及組織帳戶，這些帳戶透過*使用者名稱*
進行識別，該名稱用於構建網址。

::: info CLI-FIRST
<!-- -->
多數帳戶與專案管理操作皆透過命令列介面執行。我們正開發網頁介面，屆時將更便利地管理帳戶與專案。
<!-- -->
:::

您可透過 <LocalizedLink href="/cli/organization">`tuist
organization`</LocalizedLink> 下的子指令管理組織。建立新組織帳戶請執行：
```bash
tuist organization create {account-handle}
```

## 專案{#projects}

您的專案（無論是 Tuist 專案或原始 Xcode 專案）皆需透過遠端專案與您的帳戶整合。延續與 GitHub
的類比，這如同擁有本地與遠端儲存庫，供您推送變更。您可使用 <LocalizedLink href="/cli/project">`tuist
project`</LocalizedLink> 來建立與管理專案。

專案透過完整識別碼標示，此識別碼由組織識別碼與專案識別碼串接而成。例如：若某組織識別碼為`tuist` ，專案識別碼為`tuist`
，則完整識別碼為`tuist/tuist` 。

本地與遠端專案的綁定是透過設定檔完成的。若尚未建立，請在`Tuist.swift` 位置建立檔案，並加入以下內容：

```swift
let tuist = Tuist(fullHandle: "{account-handle}/{project-handle}") // e.g. tuist/tuist
```

::: warning TUIST PROJECT-ONLY FEATURES
<!-- -->
請注意，某些功能（例如
<LocalizedLink href="/guides/features/cache">二進位快取</LocalizedLink>）需要您擁有 Tuist
專案。若您使用的是原始 Xcode 專案，將無法使用這些功能。
<!-- -->
:::

專案網址採用完整識別碼構建。例如公開的 Tuist 儀表板可透過
[tuist.dev/tuist/tuist](https://tuist.dev/tuist/tuist) 存取，其中`tuist/tuist`
即為專案完整識別碼。
