---
{
  "title": "アカウントとプロジェクト",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "Tuist でアカウントとプロジェクトを作成・管理する方法を学びます。"
}
---
# アカウントとプロジェクト {#accounts-and-projects}

Tuist の一部の機能では、データの永続化を提供し他のサービスと連携できるサーバーが必要です。サーバーと連携するには、アカウントと、ローカルプロジェクトに接続するプロジェクトが必要です。

## アカウント {#accounts}

サーバーを利用するにはアカウントが必要です。アカウントには次の 2 種類があります。

- **個人アカウント:** サインアップ時に自動で作成され、ID プロバイダー（GitHub など）から取得したハンドルまたはメールアドレスの先頭部分で識別されます。
- **組織アカウント:** 手動で作成され、開発者が定義したハンドルで識別されます。組織では、他のメンバーを招待してプロジェクトで共同作業できます。

[GitHub](https://github.com) に慣れている方なら、その概念は似ています。個人アカウントと組織アカウントを持ち、URL を構築する際に使われる*ハンドル*で識別されます。

組織は <.localized_link href="/cli/organization">`tuist organization`</.localized_link> のサブコマンドで管理できます。新しい組織アカウントを作成するには、次を実行してください。
```bash
tuist organization create {account-handle}
```

### 組織メンバーシップ {#organization-membership}

ユーザーは、招待、自動的なシングルサインオン登録、または<.localized_link href="/guides/integrations/authentication/scim">System for Cross-domain Identity Management provisioning</.localized_link>を通じて組織メンバーになれます。

組織の ID プロバイダーで認証しても、それだけではメンバーシップは付与されません。組織の<.localized_link href="/guides/integrations/authentication/sso#choose-an-enrollment-policy">シングルサインオン登録ポリシー</.localized_link>により、信頼済みドメインのユーザーが招待を必要とするか、自動で参加できるかが決まります。

管理者はダッシュボードまたは<.localized_link href="/cli/organization/invite">`tuist organization invite`</.localized_link>でメンバーを招待できます。招待を受けたユーザーが承認した際に`user`以外のロールを付与するには、`--role admin`または`--role viewer`を指定してください。

### ロール {#roles}

すべての組織メンバーは、次の 3 つのロールのいずれかを保持します。

| ロール | 権限 |
| --- | --- |
| **Admin** | ユーザーができるすべてに加え、組織の管理（メンバーと招待、プロジェクト、請求、トークン、Webhook、設定）が可能です。 |
| **User** | 組織の作業を読み取り、操作できます。ビルドとテストの実行、キャッシュへの書き込み、プレビューの作成と削除、テストケースの状態変更などです。 |
| **Viewer** | 組織の作業を読み取れますが、変更はできません。ダッシュボード、ビルド、テスト実行、flaky および隔離されたテスト、プレビュー、バンドル、ランナーのアクティビティはすべて参照可能です。対話型シェルや VNC セッションをランナーにアタッチすることはできません。マシン上でコマンドを実行するためです。 |

誰かを招待する際にロールを選択し、後でダッシュボードの**Members**から変更できます。このように設定されたロールは、後のサインインで上書きされることはありません。

## プロジェクト {#projects}

プロジェクトはリモートプロジェクトを通じてアカウントと統合する必要があります。GitHub との比較を続けると、変更をプッシュするローカルリポジトリとリモートリポジトリを持つようなものです。<.localized_link href="/cli/project">`tuist project`</.localized_link>を使ってプロジェクトを作成・管理できます。

プロジェクトは完全なハンドルで識別され、これは組織ハンドルとプロジェクトハンドルを連結したものです。たとえば、ハンドルが`tuist`の組織と、ハンドルが`tuist`のプロジェクトがある場合、完全なハンドルは`tuist/tuist`になります。

ローカルプロジェクトとリモートプロジェクトの紐付けは設定ファイルで行います。存在しない場合は`Tuist.swift`に作成し、以下の内容を追加してください。

```swift
let tuist = Tuist(fullHandle: "{account-handle}/{project-handle}") // e.g. tuist/tuist
```

> [!WARNING]
> **Tuist プロジェクト限定の機能**
>
> <.localized_link href="/guides/features/cache/module-cache">module caching</.localized_link>などの一部の機能では、Tuist で管理されたプロジェクトが必要です。Tuist でプロジェクトを管理していない場合、これらの機能は利用できません。


プロジェクトの URL は完全なハンドルを使って構築されます。たとえば、公開されている Tuist のダッシュボードは[tuist.dev/tuist/tuist](https://tuist.dev/tuist/tuist)でアクセスでき、ここで`tuist/tuist`はプロジェクトの完全なハンドルです。
