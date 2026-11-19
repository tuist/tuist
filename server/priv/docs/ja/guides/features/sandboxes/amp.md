---
{
  "title": "Amp",
  "titleTemplate": ":title · サンドボックス · 機能 · ガイド · Tuist",
  "description": "Tuist Sandboxes で Linux または macOS 上で Amp ワークスペースの Orb を実行するか、Tuist Mac プラグインを使用して任意の Amp スレッドに Xcode ビルド用の Mac を提供します。"
}
---
# Amp {#amp}

> [!IMPORTANT]
> **招待制**
>
> Tuist Sandboxes（Linux と macOS の両方）は現在、招待制です。アカウントへのアクセスをリクエストするには、[お問い合わせ](mailto:contact@tuist.dev)するか、[コミュニティ Slack](https://slack.tuist.dev) でご連絡ください。

[Amp](https://ampcode.com) は、各スレッドのツールを、そのスレッドのリポジトリがチェックアウトされたマシンである [orb](https://ampcode.com/docs/orbs) 上で実行します。Tuist は、Amp ワークスペースの [セルフホスト型 orb プロバイダー](https://ampcode.com/docs/orbs/self-hosted) として機能できます。これを選択したすべてのスレッドは、Linux または macOS 上の独自の Tuist <.localized_link href="/guides/features/sandboxes">sandbox</.localized_link> で実行されます。ご自身で何かを実行したりホストしたりする必要はありません。

スレッドを現在の orb 上で維持し、Mac 上でのみ Apple プラットフォーム向けコードのビルド、テスト、実行を行うには、代わりに [Tuist Mac プラグイン](#remote-mac) を使用してください。

## Amp を接続 {#connect}

Amp ワークスペースと Tuist アカウントの両方の管理者である必要があります。

1. Amp で、ワークスペースの **Settings → Orbs** を開き、**Add Orb Provider** をクリックして、例えば `tuist` のような名前を付けます。メンバーはこの名前でプロバイダーを選択します。`aop_live_…` トークンをコピーしてください。Amp はこのトークンを一度だけ表示します。
2. Amp のプロバイダーの **Edit** ダイアログで、提供したい **Orb types** を追加し、デフォルトを選択します。Linux タイプは [Amp 自身の orbs](https://ampcode.com/docs/orbs/sizes-and-costs) のメモリ構成と一致します。それぞれ、メモリ 1 GiB あたり vCPU の 4 分の 1 が保証され、マシンのコアに空きがある場合は最大 16 vCPU までバーストします（<.localized_link href="/guides/features/sandboxes#guaranteed-cpu">Guaranteed CPU</.localized_link> を参照）。

   | タイプ | 形状 |
   | --- | --- |
   | `linux` | Linux、8 GiB RAM、2 vCPU 保証 |
   | `linux-tiny` | Linux、2 GiB RAM、0.5 vCPU 保証 |
   | `linux-small` | Linux、4 GiB RAM、1 vCPU 保証 |
   | `linux-medium` | `linux` と同じ |
   | `linux-large` | Linux、16 GiB RAM、4 vCPU 保証 |
   | `linux-xxlarge` | Linux、32 GiB RAM、8 vCPU 保証 |
   | `linux-3xlarge` | Linux、44 GiB RAM、11 vCPU 保証 |
   | `macos` | macOS（デフォルトの Xcode）、8 vCPU、8 GiB RAM |
   | `macos-xcode-<version>` | macOS（その [Xcode](#xcode)）、8 vCPU、8 GiB RAM |

   Linux タイプのワークスペースは 10 GB、macOS タイプは 30 GB です。

3. Tuist で、アカウントのダッシュボードにある **Sandboxes** を開き、Amp カードの **Connect** をクリックして、トークンを貼り付けます。

Tuist がプロバイダーを提供し始めると、カードに **Connected** と表示されます。1 つの Tuist アカウントは 1 つのプロバイダーを提供します。Amp でそのプロバイダーを使用できる人は誰でも、接続された Tuist アカウント上で orb を実行し、そのアカウントに課金されます。停止するには、カードの **Disconnect** をクリックするか、Amp でプロバイダーをオフにします。

## スレッドを開始 {#start-a-thread}

Amp の新規スレッド作成画面で、**Orb** をクリックし、**Self-Hosted** の下から Tuist プロバイダーを選択して、タイプを選びます。例えば、`linux-small` より少ないリソースで済むリポジトリには `linux` を、より多くのリソースが必要なリポジトリには `linux-large` を選択します。Amp CLI から実行する場合：

```bash
amp -ox "Fix the failing snapshot tests" --orb-provider tuist --orb-size macos
```

スレッドはその orb タイプを生涯保持します。タイプを指定しない場合、プロバイダーのデフォルトが適用されます。すべての新規スレッドで同じタイプを使用するには、Amp の **Settings → Orbs** にある **Default Orb** でプロバイダーとそのタイプを選択します。

### Xcode を選択 {#xcode}

`macos` はデフォルトの <.localized_link href="/guides/features/sandboxes#xcode">Xcode</.localized_link> を実行します。別のバージョンを使用するには、その名前に基づいた orb タイプを追加します（ドットをダッシュに置き換えます）。例えば、`macos-xcode-26-1-1` は Xcode 26.1.1 を、`macos-xcode-27-0` は Xcode 27.0 を実行します。リポジトリでピン留めされている各 Xcode に対してタイプを追加し、他のタイプと同様にスレッドごとに選択します。

```bash
amp -ox "Fix the failing snapshot tests" --orb-provider tuist --orb-size macos-xcode-26-1-1
```

Tuist が提供していない Xcode のタイプを指定すると、新しい orb の起動時に失敗します。すでにその Xcode で起動済みの orb は、Tuist がその Xcode の提供を停止した後でも再開を続けます。

Amp はリポジトリをクローンし、すべての orb と同様に `.agents/setup` スクリプトを実行して Git 認証情報を設定します。各 orb は、アカウントの Tuist <.localized_link href="/guides/features/cache">cache</.localized_link> も読み取ることができます。

## 一時停止と保持 {#retention}

スレッドがアイドル状態になると、Amp はその orb を一時停止します。次のメッセージで、ファイルはそのままの状態で再開されます。

- **Linux：** 実行中のプロセスは一時停止後も維持されます。長時間一時停止された orb はアーカイブストレージに移動され、次のメッセージでプロセスなしで復元されます。Linux orb は、Amp がスレッドの orb を削除するまでファイルを保持します。
- **macOS：** 一時停止中またはエラー状態の orb が 7 日間経過すると削除されます。スレッドの次のメッセージで新しい orb が開始され、Amp は `.agents/setup` を再度実行します。マシン上の最初の macOS orb は Amp CLI をインストールするため、起動に最大 2 分かかることがあります。

Amp による一時停止が行われずアイドル状態が続いた orb（例えば、一時停止コマンドが届かなかった場合など）は、CPU 使用率がほぼゼロの状態のまま 10 分後に一時停止されます。

## 任意の Amp スレッドから Mac を使用 {#remote-mac}

Tuist Mac プラグインは、Amp スレッドに Xcode、iOS シミュレーター、Homebrew を備えた macOS sandbox を提供します。スレッドは実行場所（例えば Amp 自身の Linux orb の 1 つ）で実行を継続します。作業を Amp に依頼すると、必要に応じて Mac を起動します。

> 設定画面にダークモードのトグルを追加し、iOS シミュレーターでアプリを実行して、スクリーンショットを見せてください。

Amp はコード編集を実行場所で継続します。Mac 上の各コマンドの実行前に、プラグインは `tuist sandbox sync` を実行し、Git で無視されていないファイル（コミット済みかどうかを問わず）をコピーします。その後、変更されたファイルのみを同期します。Mac が作成したビルド成果物やその他の無視されるファイルはそこに残るため、ビルドは増分ビルドのまま維持されます。プラグインはこれらのツールと、Amp にそれらの使用方法とタイミングを指示する `remote-mac` スキルを追加します。

| ツール | 機能 |
| --- | --- |
| `tuist_mac_start` | スレッドの Mac を作成または再利用し、同期します |
| `tuist_mac_shell` | 同期してから Mac 上でコマンドを実行します |
| `tuist_mac_screenshot` | スレッド内にシミュレーターまたは画面を表示します |
| `tuist_mac_download` | ビルドされた `.app` などのファイルをコピーして戻します |
| `tuist_mac_stop` | スレッドの Mac を削除します |

Mac には独自の Tuist CLI がありません。初回同期後、Amp はリポジトリのルートで `mise install` を実行してプロジェクトでピン留めされた Tuist をインストールし、`tuist_mac_shell` は mise の shim を `PATH` に追加します。Mac 上の各コマンドは、Tuist 4.218.0 以降を使用して独自に <.localized_link href="/guides/features/sandboxes#tuist-in-sandbox">アカウントのキャッシュにサインイン</.localized_link> します。4.215.0 から 4.217.x では、Amp はまず `tuist auth login` を実行します。

1 つのスレッドは 1 台の Mac を使用します。Amp は `tuist_mac_start` に、リポジトリがピン留めしている <.localized_link href="/guides/features/sandboxes#xcode">Xcode</.localized_link>（例えば `.xcode-version` など）を渡します。指定しない場合はデフォルトの Xcode が実行されます。Mac はその Xcode を保持するため、切り替えるには停止してもう 1 台を開始する必要があります。Tuist はアイドル状態になるとそれを一時停止し、次のコマンドで再開します。タスクが完了すると Amp はそれを削除します。放置された Mac は、14 日間一時停止された後に削除されます。Mac は他の sandbox と同様に Tuist アカウントの利用枠としてカウントされます。

### 設定 {#remote-mac-setup}

1. **プラグインをインストールします。** ファイルは 1 つだけです。[`tuist-mac.ts`](https://github.com/tuist/tuist/blob/main/.amp/plugins/tuist-mac.ts)。Amp ワークスペースの全員が利用できるようにするには、ワークスペース管理者がスレッドで Amp に次のように依頼します。

   > https://raw.githubusercontent.com/tuist/tuist/main/.amp/plugins/tuist-mac.ts をワークスペースのプラグインに追加してください。

   Amp はそれをワークスペースの [プラグインリポジトリ](https://ampcode.com/docs/customize/global-plugins-and-skills) にコミットし、プッシュする前に確認を求めます。自分だけが使用するためにインストールする場合は代わりに「my personal plugins」と依頼するか、ファイル名を `.amp/plugins/tuist-mac.ts` としてリポジトリに保存してそこだけで使用します。プラグインはコピーであるため、更新するには同じ URL から最新バージョンに置き換えるよう Amp に依頼してください。
2. **Tuist CLI をインストールします**。Amp が実行される場所で行います。orb 上では、リポジトリの [`.agents/setup`](https://ampcode.com/docs/orbs/customizing) スクリプトに追加します。例えば `mise use -g tuist@latest` または `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist` です。
3. **CLI がアカウントの sandboxes を使用できるようにします。** orb 上では、<.localized_link href="/guides/server/authentication#amp-orbs">Amp orbs</.localized_link> で説明されているように Amp ワークスペースを Tuist アカウントに接続します。orb はその後自動的にサインインし、sandboxes にアクセスできます。それ以外の場所（Linux マシン上の Amp CLI など）では、アカウントメンバーとして `tuist auth login` を実行するか、`TUIST_MAC_TOKEN` を <.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link> に設定します。このトークンには `account:sandboxes:write` スコープと、Mac がキャッシュを使用するための `ci` が必要です。プラグインは `TUIST_TOKEN` の代わりに `TUIST_MAC_TOKEN` を CLI に渡すため、orb がすでにそのスコープを持たない `TUIST_TOKEN` を持っている場合も設定してください。
4. **使用するアカウントを指定します**。リポジトリに `project = "<account>/<project>"` を含む `tuist.toml` がない場合です。Linux では、CLI は `Tuist.swift` からアカウントを読み取れません。Amp プロジェクトの環境変数で `TUIST_MAC_ACCOUNT` をアカウントハンドルに設定します。設定しない場合、Amp は `Tuist.swift` の `fullHandle` から取得したアカウントを `tuist_mac_start` に渡します。

CLI は `tuist.dev` を介してのみ Mac に到達するため、ネットワークアクセスを制限する環境ではそのドメインのみを許可する必要があります。`PATH` にない CLI を使用するには、`TUIST_MAC_CLI` をそのパスに設定します。

Claude Code や Cursor など、Amp プラグインをサポートしていないエージェントは、<.localized_link href="/guides/features/sandboxes#coding-agents">コーディングエージェントから Mac でビルド</.localized_link> で説明されているように、Tuist MCP サーバーと CLI を介して同様のことを行えます。

### Amp の macOS Satellites ではなく Tuist Mac を使用 {#remote-mac-satellites}

Amp には独自のクラウド Mac である [macOS Satellites](https://ampcode.com/docs/orbs/mac) もあり、待機リストに参加したワークスペース向けにベータ版として提供されています。スレッドが両方を開始できる場合、Amp の組み込み指示は macOS の作業をそのサテライトに送信するため、プラグインが選択されることはまれです。スレッドに Tuist Mac を使用させるには、次のいずれかを行います。

- **自分用の macOS Satellites を無効にします。** 各メンバーは、Amp の [Settings → Experimental Features](https://ampcode.com/settings/experimental-features) の **Mac Satellites** で無効にします。
- **ワークスペース全体で無効にします。** ワークスペースの orb が [Tuist で実行](#connect) されている場合、ワークスペース管理者は Amp のワークスペース設定の **Orbs** 配下にある **Where Orbs Run** を **Self-Hosted Only** に設定できます。これにより、エージェントは Amp ホストのサテライトを開始できなくなりますが、メンバーも Amp の組み込み orb を使用できなくなるため、すべてのスレッドが独自の orb プロバイダーで実行されている場合にのみ行ってください。
- **Tuist Mac を要求します。** プロンプト、または Amp のワークスペース設定にあるワークスペースのエージェントガイドラインに、「macOS の作業には macOS Satellites ではなく `tuist_mac_*` ツールを使用してください。」を追加し、すべてのスレッドがそれに従うようにします。
