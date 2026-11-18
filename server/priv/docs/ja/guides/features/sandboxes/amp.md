---
{
  "title": "Amp",
  "titleTemplate": ":title · サンドボックス · 機能 · ガイド · Tuist",
  "description": "Tuist Sandboxes（Linux または macOS）で Amp ワークスペースの Orb を実行します。"
}
---
# Amp {#amp}

> [!IMPORTANT]
> **招待制**
>
> Tuist Sandboxes（Linux と macOS の両方）は現在、招待制です。アカウントへのアクセスをリクエストするには、[お問い合わせ](mailto:contact@tuist.dev)いただくか、[コミュニティ Slack](https://slack.tuist.dev) でご連絡ください。

[Amp](https://ampcode.com) は、各スレッドのツールを[orb](https://ampcode.com/docs/orbs)（そのスレッドのリポジトリがチェックアウトされたマシン）上で実行します。Tuist を Amp ワークスペースの[セルフホスト型 orb プロバイダー](https://ampcode.com/docs/orbs/self-hosted)として利用できます。これを選択したすべてのスレッドは、Linux または macOS 上で独自の Tuist <.localized_link href="/guides/features/sandboxes">sandbox</.localized_link> 内で実行されます。ご自身で何かを実行したりホストしたりする必要はありません。

## Amp を接続する {#connect}

Amp ワークスペースと Tuist アカウントの両方の管理者である必要があります。

1. Amp で、ワークスペースの**Settings → Orbs**を開き、**Add Orb Provider**をクリックして、例えば `tuist` のような名前を付けます。メンバーはこの名前でプロバイダーを選択します。`aop_live_…` トークンをコピーしてください。Amp はこれを一度だけ表示します。
2. Amp のプロバイダーの**Edit**ダイアログで、以下の**Orb types**を追加し、デフォルトを選択してください。

   | タイプ | プラットフォーム | シェイプ |
   | --- | --- | --- |
   | `linux` | Linux | 2 vCPU、4 GiB RAM、10 GB ワークスペース |
   | `macos` | Xcode 搭載の macOS | 8 vCPU、8 GiB RAM、10 GB ワークスペース |

3. Tuist で、アカウントのダッシュボード内の**Sandboxes**を開き、Amp カードの**Connect**をクリックして、トークンを貼り付けてください。

Tuist がプロバイダーを提供開始すると、カードに**Connected**と表示されます。1 つの Tuist アカウントは 1 つのプロバイダーを提供します。Amp でそのプロバイダーを利用できるユーザーは誰でも、接続された Tuist アカウント上で orb を実行し、そのアカウントに課金されます。停止するには、カードの**Disconnect**をクリックするか、Amp でプロバイダーをオフにしてください。

## スレッドを開始する {#start-a-thread}

Amp の新規スレッド作成画面で、**Orb**をクリックし、**Self-Hosted**の下にある Tuist プロバイダーを選択して、`linux` または `macos` を選びます。Amp CLI から実行する場合:

```bash
amp -ox "Fix the failing snapshot tests" --orb-provider tuist --orb-size macos
```

スレッドは生涯を通じてその orb タイプを維持します。タイプを指定しない場合、プロバイダーのデフォルトが使用されます。すべての新しいスレッドで同じプラットフォームを使用するには、Amp の**Settings → Orbs**にある**Default Orb**でプロバイダーとそのタイプを選択してください。

Amp はリポジトリをクローンし、すべての orb と同様に `.agents/setup` スクリプトを実行して Git 認証情報を設定します。各 orb は、あなたのアカウントの Tuist <.localized_link href="/guides/features/cache">cache</.localized_link> も読み取ることができます。

## 一時停止と保持 {#retention}

スレッドがアイドル状態になると、Amp はその orb を一時停止します。次のメッセージで、ファイルはそのままで再開されます。

- **Linux:** 実行中のプロセスは一時停止後も維持されます。長時間一時停止された orb はアーカイブストレージに移動され、次のメッセージでプロセスなしで復元されます。Linux orb は、Amp がスレッドの orb を削除するまでファイルを保持します。
- **macOS:** 7 日間一時停止された状態、またはエラー状態の orb は削除されます。スレッドの次のメッセージで新しい orb が開始され、Amp は `.agents/setup` を再度実行します。マシン上の最初の macOS orb は Amp CLI をインストールするため、起動に最大 2 分かかることがあります。

Amp による一時停止が行われず（例えば、一時停止指令が届かなかった場合など）、アイドル状態が続いた orb は、CPU 使用率がほぼゼロのまま 10 分後に一時停止されます。
