---
{
  "title": "アカウントとプロジェクト",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "Tuist でアカウントとプロジェクトを作成・管理する方法を学びます。"
}
---
# アカウントとプロジェクト {#accounts-and-projects}

Tuist の一部の機能では、データの永続化を提供し他のサービスと連携できるサーバーが必要です。サーバーを利用するには、アカウントと、ローカルプロジェクトに接続するプロジェクトを用意する必要があります。

## アカウント {#accounts}

サーバーを利用するにはアカウントが必要です。アカウントには次の 2 種類があります。

- **個人アカウント:** サインアップ時に自動で作成され、ID プロバイダー（例: GitHub）から取得したハンドルまたはメールアドレスの先頭部分で識別されます。
- **組織アカウント:** 手動で作成され、開発者が定義したハンドルで識別されます。組織では他のメンバーを招待してプロジェクトで協業できます。

[GitHub](https://github.com) に慣れている方なら、その概念は似ています。個人アカウントと組織アカウントを持ち、URL を構築する際に使われる*ハンドル*で識別されます。

> [!NOTE]
> **Cli-first**
>
> アカウントやプロジェクトを管理する操作の大半は CLI で行います。アカウントとプロジェクトの管理をより簡単にするウェブインターフェースの開発を進めています。


組織は <.localized_link href="/cli/organization">`tuist organization`</.localized_link> のサブコマンドで管理できます。新しい組織アカウントを作成するには、次を実行してください。
```bash
tuist organization create {account-handle}
```

### 組織のメンバーシップ {#organization-membership}

ユーザーは、招待、自動的なシングルサインオン登録、あるいは <.localized_link href="/guides/integrations/authentication/scim">System for Cross-domain Identity Management provisioning</.localized_link> を介して組織のメンバーになれます。

組織の ID プロバイダーで認証しても、それだけでメンバーシップが付与されるわけではありません。組織の <.localized_link href="/guides/integrations/authentication/sso#choose-an-enrollment-policy">single sign-on enrollment policy</.localized_link> によって、信頼済みドメインのユーザーが招待を必要とするか、自動的に参加できるかが決まります。

管理者はダッシュボードから、または <.localized_link href="/cli/organization/invite">`tuist organization invite`</.localized_link> を使ってメンバーを招待できます。承認時に `user` 以外のロールを付与するには、`--role admin` または `--role viewer` を指定してください。

### ロール {#roles}

組織のメンバーは次の 3 つのロールのいずれかを保持します。

| ロール | 権限 |
| --- | --- |
| **Admin** | ユーザーが行えるすべての操作に加え、組織の管理（メンバーと招待、プロジェクト、請求、トークン、Webhook、設定）が可能です。 |
| **User** | 組織の作業を読み取り、実行します。ビルドやテストの実行、キャッシュへの書き込み、プレビューの作成と削除、テストケースの状態変更などが含まれます。 |
| **Viewer** | 組織の作業を読み取れますが、変更はできません。ダッシュボード、ビルド、テスト実行、flaky テストおよび quarantined テスト、プレビュー、バンドル、ランナーのアクティビティはすべて参照可能です。ただし、マシン上でコマンドを実行するため、ランナーへのインタラクティブシェルや VNC セッションのアタッチはできません。 |

誰かを招待する際にロールを選択し、後からダッシュボードの **Members** で変更できます。この方法で設定されたロールは、以降のサインインで上書きされることはありません。

## プロジェクト {#projects}

プロジェクトはリモートプロジェクトを介してアカウントと統合する必要があります。GitHub との比較を続けると、ローカルリポジトリとリモートリポジトリを持ち、変更をプッシュするのと似ています。プロジェクトの作成と管理には <.localized_link href="/cli/project">`tuist project`</.localized_link> を利用できます。

プロジェクトはフルハンドルで識別され、これは組織ハンドルとプロジェクトハンドルを連結したものです。例えば、ハンドルが `tuist` の組織と、ハンドルが `tuist` のプロジェクトがある場合、フルハンドルは `tuist/tuist` になります。

ローカルプロジェクトとリモートプロジェクトの紐付けは設定ファイルで行います。存在しない場合は `Tuist.swift` に作成し、以下の内容を追加してください。

```swift
let tuist = Tuist(fullHandle: "{account-handle}/{project-handle}") // e.g. tuist/tuist
```

> [!WARNING]
> **Tuist Project-only Features**
>
> <.localized_link href="/guides/features/cache/module-cache">module caching</.localized_link> などの一部の機能では Tuist で管理されたプロジェクトが必要です。プロジェクトの管理に Tuist を使用していない場合、これらの機能は利用できません。


プロジェクトの URL はフルハンドルを使って構築されます。例えば、公開されている Tuist のダッシュボードは [tuist.dev/tuist/tuist](https://tuist.dev/tuist/tuist) でアクセスでき、ここで `tuist/tuist` がプロジェクトのフルハンドルです。
