---
{
  "title": "Amp",
  "titleTemplate": ":title · サンドボックス · 機能 · ガイド · Tuist",
  "description": "Tuist Sandboxes上で、LinuxまたはmacOSを使用してAmpワークスペースのOrbを実行するか、Tuist Macプラグインを使用して任意のAmpスレッドにXcodeビルド用のMacを提供します。"
}
---
# Amp {#amp}

> [!IMPORTANT]
> **招待制**
>
> Tuist Sandboxes（Linux と macOS の両方）は現在、招待制です。アカウントへのアクセスをリクエストするには、[お問い合わせ](mailto:contact@tuist.dev)いただくか、[コミュニティ Slack](https://slack.tuist.dev) でご連絡ください。

[Amp](https://ampcode.com) は各スレッドのツールを、そのスレッドのリポジトリがチェックアウトされたマシンである [orb](https://ampcode.com/docs/orbs) 上で実行します。Tuist を Amp ワークスペースの [セルフホスト型 orb プロバイダー](https://ampcode.com/docs/orbs/self-hosted) として利用できます。これを選択したすべてのスレッドは、Linux または macOS 上で独自の Tuist <.localized_link href="/guides/features/sandboxes">sandbox</.localized_link> 内で実行されます。ご自身で何かを実行したりホストしたりする必要はありません。

スレッドを現在の orb に留め、Mac 上でのみ Apple プラットフォーム向けコードのビルド、テスト、実行を行うには、代わりに [Tuist Mac プラグイン](#remote-mac) を使用してください。

## Amp を接続 {#connect}

Amp ワークスペースと Tuist アカウントの両方の管理者である必要があります。

1. Amp でワークスペースの **Settings → Orbs** を開き、**Add Orb Provider** をクリックして、例えば `tuist` のような名前を付けます。メンバーはこの名前でプロバイダーを選択します。`aop_live_…` トークンをコピーしてください。Amp はこのトークンを一度だけ表示します。
2. Amp のプロバイダーの **Edit** ダイアログで、提供したい **Orb types** を追加し、デフォルトを選択します。Linux タイプは [Amp 自身の orbs](https://ampcode.com/docs/orbs/sizes-and-costs) のサイズと一致します。

   | タイプ | プラットフォーム | シェイプ |
   | --- | --- | --- |
   | `linux` | Linux | 4 vCPU、8 GiB RAM、10 GB ワークスペース |
   | `linux-tiny` | Linux | 1 vCPU、2 GiB RAM、10 GB ワークスペース |
   | `linux-small` | Linux | 2 vCPU、4 GiB RAM、10 GB ワークスペース |
   | `linux-medium` | Linux | 4 vCPU、8 GiB RAM、10 GB ワークスペース（`linux` と同じ） |
   | `linux-large` | Linux | 8 vCPU、16 GiB RAM、10 GB ワークスペース |
   | `linux-xxlarge` | Linux | 16 vCPU、32 GiB RAM、10 GB ワークスペース |
   | `linux-3xlarge` | Linux | 16 vCPU、44 GiB RAM、10 GB ワークスペース |
   | `macos` | Xcode 搭載 macOS | 8 vCPU、8 GiB RAM、10 GB ワークスペース |

3. Tuist でアカウントのダッシュボードにある **Sandboxes** を開き、Amp カードの **Connect** をクリックしてトークンを貼り付けます。

Tuist がプロバイダーを提供し始めると、カードに **Connected** と表示されます。1 つの Tuist アカウントは 1 つのプロバイダーを提供します。Amp でそのプロバイダーを使用できるユーザーは、接続された Tuist アカウントに対して orb を実行し、そのアカウントに課金されます。停止するには、カードの **Disconnect** をクリックするか、Amp でプロバイダーをオフにします。

## スレッドを開始 {#start-a-thread}

Amp の新しいスレッド作成画面で、**Orb** をクリックし、**Self-Hosted** の下にある Tuist プロバイダーを選択して、タイプを選びます。たとえば、`linux` より少ないリソースで済むリポジトリには `linux-small` を、より多くのリソースが必要なリポジトリには `linux-large` を選択します。Amp CLI からは次のように実行します。

```bash
amp -ox "Fix the failing snapshot tests" --orb-provider tuist --orb-size macos
```

スレッドはその orb タイプを生涯保持します。タイプを指定しない場合、プロバイダーのデフォルトが使用されます。すべての新しいスレッドで同じタイプを使用するには、Amp の **Settings → Orbs** で **Default Orb** の下にプロバイダーとそのタイプを選択します。

Amp はリポジトリをクローンし、すべての orb で行うのと同様に `.agents/setup` スクリプトを実行して Git 認証情報を設定します。各 orb は、アカウントの Tuist <.localized_link href="/guides/features/cache">cache</.localized_link> も読み取ることができます。

## 一時停止と保持 {#retention}

スレッドがアイドル状態になると、Amp はその orb を一時停止します。次のメッセージでファイルは無傷のまま再開されます。

- **Linux:** 実行中のプロセスは一時停止後も維持されます。長時間一時停止された orb はアーカイブストレージに移動され、次のメッセージでプロセスなしで復元されます。Linux orb は、Amp がスレッドの orb を削除するまでファイルを保持します。
- **macOS:** 一時停止状態またはエラー状態が 7 日間続いた orb は削除されます。スレッドの次のメッセージで新しい orb が開始され、Amp は `.agents/setup` を再度実行します。マシン上の最初の macOS orb は Amp CLI をインストールするため、起動に最大 2 分かかることがあります。

Amp による一時停止が行われずにアイドル状態が続いた orb（例えば、一時停止コマンドが届かなかった場合など）は、CPU 使用率がほぼゼロの状態のまま 10 分後に一時停止されます。

## 任意の Amp スレッドから Mac を使用 {#remote-mac}

Tuist Mac プラグインは、Amp スレッドに Xcode、iOS シミュレータ、Homebrew を備えた macOS サンドボックスを提供します。スレッドは実行場所（例えば Amp 独自の Linux orb の一つ）で実行を続けます。作業を Amp に依頼すると、必要に応じて Mac を起動します。

> 設定画面にダークモードの切り替えを追加し、iOS シミュレータでアプリを実行して、スクリーンショットを表示してください。

Amp はコードの実行場所で編集を続けます。Mac 上の各コマンドの前に、プラグインは `tuist sandbox sync` を実行し、Git が無視しないファイル（コミット済みかどうかを問わず）をコピーし、その後変更されたファイルのみをコピーします。Mac が作成したビルド成果物やその他の無視されるファイルはその場所に留まるため、ビルドは増分状態を保ちます。プラグインはこれらのツールと、Amp にそれらの使用方法と時期を指示する `remote-mac` スキルを追加します。

| ツール | 機能 |
| --- | --- |
| `tuist_mac_start` | スレッド用の Mac を作成または再利用し、同期します |
| `tuist_mac_shell` | 同期してから Mac 上でコマンドを実行します |
| `tuist_mac_screenshot` | スレッド内でシミュレータまたは画面を表示します |
| `tuist_mac_download` | ビルド済みの `.app` などのファイルをコピーして戻します |
| `tuist_mac_stop` | スレッド用の Mac を削除します |

Mac には独自の Tuist CLI がありません。最初の同期後、Amp はリポジトリのルートで `mise install` を実行してプロジェクトでピン留めされた Tuist をインストールし、`tuist_mac_shell` は mise の shim を `PATH` に追加します。Mac 上の各コマンドは、Tuist 4.218.0 以降を使用して独自に <.localized_link href="/guides/features/sandboxes#tuist-in-sandbox">アカウントのキャッシュにサインイン</.localized_link> します。4.215.0 から 4.217.x では、Amp はまず `tuist auth login` を実行します。

スレッドは 1 台の Mac を使用します。Tuist はアイドル状態になるとそれを一時停止し、次のコマンドで再開します。タスクが完了すると Amp はそれを削除します。放置された Mac は 14 日間一時停止されると削除されます。Mac は他のサンドボックスと同様に Tuist アカウントの利用量としてカウントされます。

### セットアップ {#remote-mac-setup}

1. **プラグインをインストールします。** ファイルは 1 つ、[`tuist-mac.ts`](https://github.com/tuist/tuist/blob/main/.amp/plugins/tuist-mac.ts) です。Amp ワークスペースの全員が利用できるようにするには、ワークスペース管理者がスレッド内で Amp に次のように依頼します。

   > https://raw.githubusercontent.com/tuist/tuist/main/.amp/plugins/tuist-mac.ts をワークスペースのプラグインに追加してください。

   Amp はこれをワークスペースの [プラグインリポジトリ](https://ampcode.com/docs/customize/global-plugins-and-skills) にコミットし、プッシュする前に確認を求めます。自分だけがインストールするには「my personal plugins」と依頼するか、リポジトリ内で `.amp/plugins/tuist-mac.ts` としてファイルを保存してそこだけで使用します。プラグインはコピーであるため、更新するには同じ URL から最新バージョンに置き換えるよう Amp に依頼します。
2. **Tuist CLI をインストールします**。Amp が実行される場所です。orb では、リポジトリの [`.agents/setup`](https://ampcode.com/docs/orbs/customizing) スクリプトに追加します。例えば `mise use -g tuist@latest` または `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist` です。
3. **CLI がアカウントのサンドボックスを使用できるようにします。** orb では、<.localized_link href="/guides/server/authentication#amp-orbs">Amp orbs</.localized_link> で説明されているように、Amp ワークスペースを Tuist アカウントに接続します。orb は自動的にサインインし、サンドボックスにアクセスできます。Linux マシン上の Amp CLI など他の場所では、アカウントメンバーとして `tuist auth login` を実行するか、`TUIST_MAC_TOKEN` を `account:sandboxes:write` スコープを持つ <.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link> に設定し、さらに Mac がキャッシュを使用するために `ci` を追加します。プラグインは `TUIST_TOKEN` の代わりに `TUIST_MAC_TOKEN` を CLI に渡すため、orb がそのスコープを持たない `TUIST_TOKEN` をすでに持っている場合も設定してください。
4. **使用するアカウントを指定します**。リポジトリに `project = "<account>/<project>"` を持つ `tuist.toml` がない場合です。Linux では、CLI は `Tuist.swift` からアカウントを読み取れません。Amp プロジェクトの環境変数で `TUIST_MAC_ACCOUNT` をアカウントハンドルに設定します。これがない場合、Amp は `Tuist.swift` の `fullHandle` から `tuist_mac_start` にアカウントを渡します。

CLI は `tuist.dev` を介してのみ Mac に到達するため、ネットワークアクセスを制限する環境ではそのドメインのみを許可する必要があります。`PATH` にない CLI を使用するには、`TUIST_MAC_CLI` をそのパスに設定します。

Claude Code や Cursor など、Amp プラグインをサポートしないエージェントは、<.localized_link href="/guides/features/sandboxes#coding-agents">コーディングエージェントから Mac でビルド</.localized_link> で説明されているように、Tuist MCP サーバーと CLI を介して同様の操作を行えます。

### Amp の macOS Satellites の代わりに Tuist Mac を使用 {#remote-mac-satellites}

Amp には独自のクラウド Mac、[macOS Satellites](https://ampcode.com/docs/orbs/mac) もあり、ウェイトリストに参加したワークスペース向けにベータ版として提供されています。スレッドが両方を起動できる場合、Amp の組み込み指示は macOS での作業をサテライトに送るため、プラグインが選択されることはまれです。スレッドに Tuist Mac を使用させるには、次のいずれかを行います。

- **自分用に macOS Satellites をオフにします。** 各メンバーは、Amp の [Settings → Experimental Features](https://ampcode.com/settings/experimental-features) の **Mac Satellites** でオフにします。
- **ワークスペース用にオフにします。** ワークスペースの orb が [Tuist で実行](#connect) されている場合、ワークスペース管理者は Amp のワークスペース設定の **Orbs** の下で **Where Orbs Run** を **Self-Hosted Only** に設定できます。エージェントは Amp ホストのサテライトを起動できなくなりますが、メンバーも Amp の組み込み orb を使用できなくなるため、すべてのスレッドが独自の orb プロバイダーで実行されている場合にのみ行ってください。
- **Tuist Mac を要求します。** プロンプト、または Amp のワークスペース設定内のワークスペースのエージェントガイダンスに「macOS での作業には macOS Satellites ではなく `tuist_mac_*` ツールを使用してください。」を追加し、すべてのスレッドがそれに従うようにします。
