---
{
  "title": "Amp",
  "titleTemplate": ":title · サンドボックス · 機能 · ガイド · Tuist",
  "description": "Tuist Sandboxes で Linux または macOS 上で Amp ワークスペースの Orbs を実行するか、Tuist Mac プラグインを使用して任意の Amp スレッドに Xcode ビルド用の Mac を提供します。"
}
---
# Amp {#amp}

> [!IMPORTANT]
> **招待制**
>
> Tuist Sandboxes（Linux と macOS の両方）は現在、招待制です。アカウントへのアクセスをリクエストするには、[お問い合わせ](mailto:contact@tuist.dev)いただくか、[コミュニティ Slack](https://slack.tuist.dev) までご連絡ください。

[Amp](https://ampcode.com) は、各スレッドのツールを、そのスレッドのリポジトリがチェックアウトされたマシンである [orb](https://ampcode.com/docs/orbs) 上で実行します。Tuist を Amp ワークスペースの [セルフホスト型 orb プロバイダー](https://ampcode.com/docs/orbs/self-hosted) として利用できます。これを選択したすべてのスレッドは、Linux または macOS 上で独自の Tuist <.localized_link href="/guides/features/sandboxes">sandbox</.localized_link> 内で実行されます。ご自身で何かを実行したりホストしたりする必要はありません。

スレッドを現在の orb で維持し、Mac 上でのみ Apple プラットフォーム向けのコードのビルド、テスト、実行を行いたい場合は、代わりに [Tuist Mac プラグイン](#remote-mac) を使用してください。

## Amp を接続 {#connect}

Amp ワークスペースと Tuist アカウントの両方の管理者である必要があります。

1. Amp で、ワークスペースの **Settings → Orbs** を開き、**Add Orb Provider** をクリックして、例えば `tuist` のような名前を付けます。メンバーはこの名前でプロバイダーを選択します。`aop_live_…` トークンをコピーしてください。Amp はこれを一度だけ表示します。
2. Amp のプロバイダーの **Edit** ダイアログで、提供したい **Orb types** を追加し、デフォルトを選択します。Linux タイプは [Amp 独自の orbs](https://ampcode.com/docs/orbs/sizes-and-costs) のサイズと一致します。

   | タイプ | プラットフォーム | シェイプ |
   | --- | --- | --- |
   | `linux` | Linux | 4 vCPU、8 GiB RAM、10 GB ワークスペース |
   | `linux-tiny` | Linux | 1 vCPU、2 GiB RAM、10 GB ワークスペース |
   | `linux-small` | Linux | 2 vCPU、4 GiB RAM、10 GB ワークスペース |
   | `linux-medium` | Linux | 4 vCPU、8 GiB RAM、10 GB ワークスペース（`linux` と同じ） |
   | `linux-large` | Linux | 8 vCPU、16 GiB RAM、10 GB ワークスペース |
   | `linux-xxlarge` | Linux | 16 vCPU、32 GiB RAM、10 GB ワークスペース |
   | `linux-3xlarge` | Linux | 16 vCPU、44 GiB RAM、10 GB ワークスペース |
   | `macos` | デフォルトの Xcode を搭載した macOS | 8 vCPU、8 GiB RAM、30 GB ワークスペース |
   | `macos-xcode-<version>` | 指定した Xcode を搭載した macOS（例: Xcode 26.1.1 の場合は `macos-xcode-26-1-1`） | 8 vCPU、8 GiB RAM、30 GB ワークスペース |

3. Tuist で、アカウントのダッシュボードにある **Sandboxes** を開き、Amp カードの **Connect** をクリックして、トークンを貼り付けます。

Tuist がプロバイダーを提供開始すると、カードに **Connected** と表示されます。1 つの Tuist アカウントで 1 つのプロバイダーを提供します。Amp でそのプロバイダーを使用できるユーザーはすべて、接続された Tuist アカウントに対して課金されながら orbs を実行します。停止するには、カードの **Disconnect** をクリックするか、Amp でプロバイダーを無効にしてください。

## スレッドを開始 {#start-a-thread}

Amp の新規スレッド作成画面で **Orb** をクリックし、**Self-Hosted** から Tuist プロバイダーを選択して、タイプを選びます。たとえば、`linux` より少ないリソースで済むリポジトリには `linux-small` を、より多くのリソースが必要なリポジトリには `linux-large` を選択します。Amp CLI からは次のように実行します。

```bash
amp -ox "Fix the failing snapshot tests" --orb-provider tuist --orb-size macos
```

スレッドは生涯を通じてその orb タイプを維持します。タイプを指定しない場合、プロバイダーのデフォルトが適用されます。すべての新規スレッドで同じタイプを使用するには、Amp の **Settings → Orbs** にある **Default Orb** でプロバイダーとそのタイプを選択してください。

### Xcode を選択 {#xcode}

`macos` はデフォルトの <.localized_link href="/guides/features/sandboxes#xcode">Xcode</.localized_link> を実行します。別のバージョンを使用するには、ドットをダッシュに置き換えた名前の orb タイプを追加します。`macos-xcode-26-1-1` は Xcode 26.1.1 を実行し、`macos-xcode-27-0` は Xcode 27.0 を実行します。リポジトリでピン留めされている各 Xcode に対してタイプを追加し、他のタイプと同様にスレッドごとに選択してください。

```bash
amp -ox "Fix the failing snapshot tests" --orb-provider tuist --orb-size macos-xcode-26-1-1
```

Tuist が提供していない Xcode のタイプを指定すると、新しい orb の起動時に失敗します。すでにその Xcode で起動済みの orb は、Tuist がその Xcode の提供を停止した後でも再開を続けます。

Amp はリポジトリをクローンし、すべての orb と同様に `.agents/setup` スクリプトを実行して Git 認証情報を設定します。各 orb は、アカウントの Tuist <.localized_link href="/guides/features/cache">cache</.localized_link> も読み取ることができます。

## 一時停止と保持 {#retention}

スレッドがアイドル状態になると、Amp はその orb を一時停止します。次のメッセージでファイルはそのままの状態で再開されます。

- **Linux:** 実行中のプロセスは一時停止後も維持されます。長時間一時停止された orb はアーカイブストレージに移動され、次のメッセージでプロセスなしで復元されます。Linux orbs は、Amp がスレッドの orb を削除するまでファイルを保持します。
- **macOS:** 7日間一時停止された状態、またはエラー状態の orb は削除されます。スレッドの次のメッセージで新しい orb が開始され、Amp は `.agents/setup` を再度実行します。マシン上の最初の macOS orb は Amp CLI をインストールするため、起動に最大2分かかることがあります。

Amp による一時停止が発生せずアイドル状態が続いた orb（例えば、一時停止指示が届かなかった場合）は、CPU使用率がほぼゼロの状態のまま10分後に一時停止されます。

## 任意の Amp スレッドから Mac を使用する {#remote-mac}

Tuist Mac プラグインは、Amp スレッドに Xcode、iOS シミュレーター、Homebrew を備えた macOS サンドボックスを提供します。スレッドは元の場所（例えば Amp の Linux orb の1つ）で実行を続けます。作業を Amp に依頼すると、必要に応じて Mac を起動します。

> 設定画面にダークモードのトグルを追加し、iOS シミュレーターでアプリを実行して、スクリーンショットを見せてください。

Amp はコード編集を実行場所で行います。Mac 上の各コマンドの実行前に、プラグインは `tuist sandbox sync` を実行し、Git で無視されていないファイル（コミット済みかどうかに関わらず）をコピーし、以降は変更されたファイルのみをコピーします。Mac が作成したビルド成果物やその他の無視ファイルはその場所に留まるため、ビルドは増分ビルドのまま維持されます。プラグインはこれらのツールと、Amp にそれらの使用方法と時期を指示する `remote-mac` スキルを追加します。

| ツール | 機能 |
| --- | --- |
| `tuist_mac_start` | スレッド用の Mac を作成または再利用し、同期します |
| `tuist_mac_shell` | 同期してから Mac 上でコマンドを実行します |
| `tuist_mac_screenshot` | スレッド内にシミュレーターまたは画面を表示します |
| `tuist_mac_download` | ビルド済みの `.app` などのファイルをコピーし戻します |
| `tuist_mac_stop` | スレッド用の Mac を削除します |

Mac には独自の Tuist CLI がありません。初回同期後、Amp はリポジトリのルートで `mise install` を実行してプロジェクトでピン留めされた Tuist をインストールし、`tuist_mac_shell` は mise の shim を `PATH` に追加します。Mac 上の各コマンドは、Tuist 4.218.0 以降を使用して独自に <.localized_link href="/guides/features/sandboxes#tuist-in-sandbox">アカウントのキャッシュにサインイン</.localized_link> します。4.215.0 から 4.217.x では、Amp は事前に `tuist auth login` を実行します。

1つのスレッドは1つの Mac を使用します。Amp は `tuist_mac_start` に、リポジトリがピン留めしている <.localized_link href="/guides/features/sandboxes#xcode">Xcode</.localized_link>（例えば `.xcode-version` など）を渡します。指定しない場合はデフォルトの Xcode が実行されます。Mac はその Xcode を保持するため、切り替えるには停止してもう1つ起動する必要があります。Tuist はアイドル状態の Mac を一時停止し、次のコマンドで再開します。タスク完了時に Amp が Mac を削除します。放置された Mac は14日間一時停止された後に削除されます。Mac は他のサンドボックスと同様に Tuist アカウントの利用量としてカウントされます。

### セットアップ {#remote-mac-setup}

1. **プラグインをインストールします。** ファイルは1つだけで、[`tuist-mac.ts`](https://github.com/tuist/tuist/blob/main/.amp/plugins/tuist-mac.ts) です。Amp ワークスペースの全員が利用できるようにするには、ワークスペース管理者がスレッド内で Amp に次のように依頼します。

   > https://raw.githubusercontent.com/tuist/tuist/main/.amp/plugins/tuist-mac.ts をワークスペースプラグインに追加してください。

   Amp はそれをワークスペースの [プラグインリポジトリ](https://ampcode.com/docs/customize/global-plugins-and-skills) にコミットし、プッシュ前に確認を求めます。個人用にのみインストールするには「my personal plugins」と依頼するか、特定の場所でのみ使用するためにファイルをリポジトリ内の `.amp/plugins/tuist-mac.ts` として保存します。プラグインはコピーであるため、更新するには同じ URL から最新バージョンに置き換えるよう Amp に依頼してください。
2. **Tuist CLI をインストールします**。Amp が実行される場所です。orb 上では、リポジトリの [`.agents/setup`](https://ampcode.com/docs/orbs/customizing) スクリプトに追加します。例えば `mise use -g tuist@latest` または `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist` です。
3. **CLI がアカウントのサンドボックスを使用できるようにします。** orb 上では、<.localized_link href="/guides/server/authentication#amp-orbs">Amp orbs</.localized_link> で説明されているように、Amp ワークスペースを Tuist アカウントに接続します。これにより、orb は自動的にサインインし、サンドボックスにアクセスできるようになります。それ以外の場所（Linux マシン上の Amp CLI など）では、アカウントメンバーとして `tuist auth login` を実行するか、`TUIST_MAC_TOKEN` を `account:sandboxes:write` スコープを持つ <.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link> に設定し、さらに Mac がキャッシュを使用できるように `ci` も追加します。プラグインは `TUIST_TOKEN` の代わりに `TUIST_MAC_TOKEN` を CLI に渡すため、orb にそのスコープを持たない `TUIST_TOKEN` がすでに設定されている場合も、これを設定してください。
4. **使用するアカウントを指定します**。リポジトリに `project = "<account>/<project>"` を含む `tuist.toml` がない場合です。Linux では、CLI は `Tuist.swift` からアカウントを読み取れません。Amp プロジェクトの環境変数で `TUIST_MAC_ACCOUNT` をアカウントハンドルに設定します。設定しない場合、Amp は `Tuist.swift` の `fullHandle` から `tuist_mac_start` へアカウントを渡します。

CLI は `tuist.dev` を介してのみ Mac に到達するため、ネットワークアクセスを制限する環境ではそのドメインのみを許可する必要があります。`PATH` にない CLI を使用するには、`TUIST_MAC_CLI` をそのパスに設定してください。

Claude Code や Cursor など、Amp プラグインをサポートしないエージェントも、<.localized_link href="/guides/features/sandboxes#coding-agents">コーディングエージェントから Mac でビルド</.localized_link> で説明されているように、Tuist MCP サーバーと CLI を介して同様の操作を行えます。

### Amp の macOS Satellites の代わりに Tuist Mac を使用する {#remote-mac-satellites}

Amp には独自のクラウド Mac である [macOS Satellites](https://ampcode.com/docs/orbs/mac) もあり、待機リストに参加したワークスペース向けにベータ版として提供されています。スレッドが両方を起動できる場合、Amp の組み込み指示は macOS での作業をサテライトに送るため、プラグインが選択されることはまれです。スレッドで Tuist Mac を使用させるには、次のいずれかを行います。

- **個人用に macOS Satellites を無効にします。** 各メンバーは、Amp の [Settings → Experimental Features](https://ampcode.com/settings/experimental-features) にある **Mac Satellites** で無効にします。
- **ワークスペース用に無効にします。** ワークスペースの orb が [Tuist で実行](#connect) されている場合、ワークスペース管理者は Amp のワークスペース設定にある **Orbs** の下で **Where Orbs Run** を **Self-Hosted Only** に設定できます。これにより、エージェントは Amp ホストのサテライトを起動できなくなりますが、メンバーも Amp の組み込み orb を使用できなくなるため、すべてのスレッドが独自の orb プロバイダーで実行されている場合にのみ行ってください。
- **Tuist Mac を要求します。** プロンプト、または Amp のワークスペース設定にあるワークスペースのエージェントガイドラインに、「macOS での作業には macOS Satellites ではなく `tuist_mac_*` ツールを使用してください。」を追加し、すべてのスレッドがそれに従うようにします。
