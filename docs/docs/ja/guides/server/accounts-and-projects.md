---
{
  "title": "Accounts and projects",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "Learn how to create and manage accounts and projects in Tuist."
}
---
# アカウントとプロジェクト{#accounts-and-projects}

Tuistの機能の中には、データの永続性を追加し、他のサービスと相互作用できるサーバーを必要とするものがある。サーバーと対話するには、アカウントとローカルプロジェクトに接続するプロジェクトが必要です。

## アカウント{#accounts}

サーバーを利用するにはアカウントが必要です。アカウントには2種類あります：

- **個人アカウント：**
  これらのアカウントはサインアップ時に自動的に作成され、IDプロバイダー（GitHubなど）から取得したハンドルネームか、メールアドレスの最初の部分で識別されます。
- **組織アカウント：**
  これらのアカウントは手動で作成され、開発者によって定義されたハンドルによって識別されます。組織では、他のメンバーをプロジェクトに招待することができます。

もしあなたが[GitHub](https://github.com)をご存知なら、コンセプトは彼らのものと似ていて、個人と組織のアカウントを持つことができ、それらはURLを構築するときに使われる*ハンドル*
によって識別される。

::: info CLI-FIRST
<!-- -->
アカウントやプロジェクトを管理するためのほとんどの操作はCLIを通じて行われます。私たちは、アカウントやプロジェクトの管理をより簡単にするウェブインターフェースの開発に取り組んでいます。
<!-- -->
:::

<LocalizedLink href="/cli/organization">`tuist organization`</LocalizedLink>のサブコマンドで組織を管理できます。新しい組織アカウントを作成するには、以下を実行する：
```bash
tuist organization create {account-handle}
```

## プロジェクト{#projects}

あなたのプロジェクトは、Tuistのものであれ、生のXcodeのものであれ、リモートプロジェクトを通してあなたのアカウントと統合される必要がある。GitHubとの比較を続けると、変更をプッシュするローカルとリモートのリポジトリがあるようなものです。<LocalizedLink href="/cli/project">`tuist project`</LocalizedLink>を使ってプロジェクトを作成・管理できます。

プロジェクトは、組織ハンドルとプロジェクトハンドルを連結したフルハンドルで識別されます。例えば、`tuist` というハンドルの組織と、`tuist`
というハンドルのプロジェクトがある場合、フルハンドルは`tuist/tuist` となります。

ローカルプロジェクトとリモートプロジェクト間のバインディングは、設定ファイルを通して行われます。ない場合は、`Tuist.swift`
に作成し、以下の内容を追加してください：

```swift
let tuist = Tuist(fullHandle: "{account-handle}/{project-handle}") // e.g. tuist/tuist
```

::: warning TUIST PROJECT-ONLY FEATURES
<!-- -->
<LocalizedLink href="/guides/features/cache">バイナリキャッシュ</LocalizedLink>のように、Tuistプロジェクトを持っていることを必要とする機能があることに注意してください。生のXcodeプロジェクトを使用している場合、これらの機能を使用することはできません。
<!-- -->
:::

プロジェクトのURLはフルハンドルで構成されます。例えば、公開されているTuistのダッシュボードは、[tuist.dev/tuist/tuist](https://tuist.dev/tuist/tuist)でアクセスできます。ここで、`tuist/tuist`
はプロジェクトのフルハンドルです。
