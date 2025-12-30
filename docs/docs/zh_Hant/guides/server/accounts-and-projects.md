---
{
  "title": "Accounts and projects",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "Learn how to create and manage accounts and projects in Tuist."
}
---
# 帳戶和專案{#accounts-and-projects}

有些 Tuist 功能需要伺服器，伺服器可增加資料的持久性，並可與其他服務互動。要與伺服器互動，您需要一個帳號和一個專案，並連接到您的本機專案。

## 帳戶{#accounts}

要使用伺服器，您需要一個帳戶。有兩種類型的帳戶：

- **個人帳戶：** 當您註冊時會自動建立這些帳號，並透過從身分提供者 (例如 GitHub) 取得的句柄或電子郵件地址的第一部分來識別。
- **組織帳戶：** 這些帳號是手動建立的，由開發人員定義的句柄來識別。組織允許邀請其他成員合作進行專案。

如果您熟悉 [GitHub](https://github.com)，其概念與他們類似，您可以擁有個人和組織帳號，並透過*句柄* 來識別，該句柄會在構建 URL
時使用。

::: info CLI-FIRST
<!-- -->
管理帳戶和專案的大部分作業都是透過 CLI 完成。我們正在開發 Web 介面，讓帳戶和專案管理變得更容易。
<!-- -->
:::

您可以透過 <LocalizedLink href="/cli/organization">`tuist organization`</LocalizedLink> 下的子指令管理組織。若要建立新的組織帳戶，請執行
```bash
tuist organization create {account-handle}
```

## 專案{#projects}

您的專案，無論是 Tuist 的或原始 Xcode 的，都需要透過遠端專案與您的帳戶整合。繼續與 GitHub
作比較，這就像您有一個本機和一個遠端儲存庫，您可以在那裡推送您的變更。您可以使用
<LocalizedLink href="/cli/project">`tuist project`</LocalizedLink> 來建立和管理專案。

專案以完整句柄來識別，完整句柄是組織句柄和專案句柄串連的結果。例如，如果組織的句柄是`tuist` ，專案的句柄是`tuist`
，完整句柄就是`tuist/tuist` 。

本地專案和遠端專案之間的綁定是透過設定檔完成的。如果沒有，請在`Tuist.swift` 建立，並加入下列內容：

```swift
let tuist = Tuist(fullHandle: "{account-handle}/{project-handle}") // e.g. tuist/tuist
```

::: warning TUIST PROJECT-ONLY FEATURES
<!-- -->
請注意，有些功能如
<LocalizedLink href="/guides/features/cache">二進位快取</LocalizedLink>，需要您擁有 Tuist
專案。如果您使用的是原始的 Xcode 專案，則無法使用這些功能。
<!-- -->
:::

您專案的 URL 是使用完整句柄來建立的。例如，Tuist 的儀表板是公開的，可在
[tuist.dev/tuist/tuist](https://tuist.dev/tuist/tuist) 存取，其中`tuist/tuist`
是專案的完整句柄。
