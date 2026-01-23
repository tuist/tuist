---
{
  "title": "Accounts and projects",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "Learn how to create and manage accounts and projects in Tuist."
}
---
# アカウントとプロジェクト{#accounts-and-projects}

一部のTuist機能では、データの永続化機能を提供し他のサービスと連携可能なサーバーが必要です。サーバーと連携するには、アカウントとローカルプロジェクトに接続するプロジェクトが必要です。

## アカウント{#accounts}

サーバーを利用するにはアカウントが必要です。アカウントには2種類あります：

- **個人アカウント:** これらのアカウントは登録時に自動生成され、IDプロバイダー（例:
  GitHub）から取得したハンドル、またはメールアドレスの先頭部分で識別されます。
- **組織アカウント:**
  これらのアカウントは手動で作成され、開発者が定義したハンドルで識別されます。組織では、プロジェクトへの共同作業のために他のメンバーを招待できます。

[GitHub](https://github.com)をご存知であれば、その概念と類似しています。個人アカウントと組織アカウントが存在し、URL構築時に使用される*ハンドル（例:*
）によって識別されます。

::: info CLI-FIRST
<!-- -->
アカウントやプロジェクトの管理操作のほとんどはCLIを通じて行われます。アカウントやプロジェクトの管理をより容易にするウェブインターフェースの開発を進めています。
<!-- -->
:::

組織の管理は、<LocalizedLink href="/cli/organization">`tuist
organization`</LocalizedLink> のサブコマンドで行えます。新しい組織アカウントを作成するには、以下を実行してください：
```bash
tuist organization create {account-handle}
```

## プロジェクト{#projects}

Tuistプロジェクトまたは生のXcodeプロジェクトは、リモートプロジェクトを通じてアカウントと連携させる必要があります。GitHubとの比較で言えば、変更をプッシュするローカルリポジトリとリモートリポジトリを持つようなものです。プロジェクトの作成と管理には、<LocalizedLink href="/cli/project">`tuist
project`</LocalizedLink> を使用できます。

プロジェクトは完全ハンドルで識別されます。これは組織ハンドルとプロジェクトハンドルを連結したものです。例えば、組織ハンドルが`tuist`
、プロジェクトハンドルが`tuist` の場合、完全ハンドルは`tuist/tuist` となります。

ローカルプロジェクトとリモートプロジェクトの紐付けは設定ファイルを通じて行われます。設定ファイルが存在しない場合は、`Tuist.swift`
に以下の内容を追加してください：

```swift
let tuist = Tuist(fullHandle: "{account-handle}/{project-handle}") // e.g. tuist/tuist
```

::: warning TUIST PROJECT-ONLY FEATURES
<!-- -->
<LocalizedLink href="/guides/features/cache">バイナリキャッシュ</LocalizedLink>などの機能は、Tuistプロジェクト環境が必要です。生のXcodeプロジェクトを使用している場合、これらの機能は利用できません。
<!-- -->
:::

プロジェクトのURLはフルハンドルを使用して構築されます。例えば、公開されているTuistのダッシュボードは[tuist.dev/tuist/tuist](https://tuist.dev/tuist/tuist)でアクセス可能です。ここで、`tuist/tuist`
がプロジェクトのフルハンドルです。
