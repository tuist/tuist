---
{
  "title": "Amp",
  "titleTemplate": ":title · サンドボックス · 機能 · ガイド · Tuist",
  "description": "Linux または macOS 上の Tuist Sandboxes で Amp ワークスペースの Orb を実行するか、Tuist Mac プラグインを使用して任意の Amp スレッドに Xcode ビルド用の Mac を提供します。"
}
---
# Amp {#amp}

> [!IMPORTANT]
> **招待制**
>
> Tuist Sandboxes（Linux と macOS の両方）は現在、招待制です。アカウントへのアクセスをリクエストするには、[お問い合わせ](mailto:contact@tuist.dev)いただくか、[コミュニティ Slack](https://slack.tuist.dev) までご連絡ください。

[Amp](https://ampcode.com) は各スレッドのツールを、そのスレッドのリポジトリがチェックアウトされたマシンである [orb](https://ampcode.com/docs/orbs) 上で実行します。Tuist を Amp ワークスペースの [セルフホスト型 orb プロバイダー](https://ampcode.com/docs/orbs/self-hosted) として利用できます。これを選択したスレッドはすべて、Linux または macOS 上で独自の Tuist <.localized_link href="/guides/features/sandboxes">sandbox</.localized_link> 内で実行されます。ご自身で何かを実行したりホストしたりする必要はありません。

スレッドを現在の orb で維持し、Mac 上でのみ Apple プラットフォーム向けコードのビルド、テスト、実行を行いたい場合は、代わりに [Tuist Mac プラグイン](#remote-mac) を使用してください。

## Amp を接続する {#connect}

Amp ワークスペースと Tuist アカウントの両方の管理者である必要があります。

1. Amp でワークスペースの **Settings → Orbs** を開き、**Add Orb Provider** をクリックして、例えば `tuist` のような名前を付けます。メンバーはこの名前でプロバイダーを選択します。`aop_live_…` トークンをコピーしてください。Amp はこれを一度だけ表示します。
2. Amp のプロバイダーの **Edit** ダイアログで、提供したい **Orb types** を追加し、デフォルトを選択します。Linux タイプは [Amp 独自の orbs](https://ampcode.com/docs/orbs/sizes-and-costs) のメモリ構成と一致します。それぞれ、メモリ 1 GiB あたり vCPU の 4 分の 1 が保証され、マシンにアイドル状態のコアがある場合は最大 16 vCPU までバーストします（<.localized_link href="/guides/features/sandboxes#guaranteed-cpu">Guaranteed CPU</.localized_link> を参照）。

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

3. Tuist でアカウントのダッシュボードにある **Sandboxes** を開き、Amp カードの **Connect** をクリックしてトークンを貼り付けます。

Tuist がプロバイダーを提供開始すると、カードに **Connected** と表示されます。1 つの Tuist アカウントで 1 つのプロバイダーを提供できます。Amp でそのプロバイダーを使用できるユーザーは、接続された Tuist アカウントに対して orb を実行し、課金されます。停止するには、カードの **Disconnect** をクリックするか、Amp でプロバイダーを無効にしてください。

## スレッドを開始する {#start-a-thread}

Amp の新規スレッド作成画面で、**Orb** をクリックし、**Self-Hosted** の下にある Tuist プロバイダーを選択して、タイプを選びます。たとえば、`linux` より少ないリソースで済むリポジトリには `linux-small` を、より多くのリソースが必要なリポジトリには `linux-large` を選択します。Amp CLI からは次のように実行します。

```bash
amp -ox "Fix the failing snapshot tests" --orb-provider tuist --orb-size macos
```

スレッドはその orb タイプを生涯保持します。タイプを指定しない場合、プロバイダーのデフォルトが適用されます。すべての新規スレッドで同じタイプを使用するには、Amp の **Settings → Orbs** にある **Default Orb** でプロバイダーとそのタイプを選択してください。

### Xcode を選択する {#xcode}

`macos` はデフォルトの <.localized_link href="/guides/features/sandboxes#xcode">Xcode</.localized_link> を実行します。別のバージョンを使用するには、ドットをダッシュに置き換えた名前の orb タイプを追加します。例えば、`macos-xcode-26-1-1` は Xcode 26.1.1 を実行し、`macos-xcode-27-0` は Xcode 27.0 を実行します。リポジトリでピン留めされている各 Xcode に対してタイプを追加し、他のタイプと同様にスレッドごとに選択します。

```bash
amp -ox "Fix the failing snapshot tests" --orb-provider tuist --orb-size macos-xcode-26-1-1
```

Tuist が提供していない Xcode のタイプを指定すると、新しい orb の開始時に失敗します。すでにその Xcode で開始されていた orb は、Tuist がその Xcode の提供を停止した後でも再開を続けます。

Amp はリポジトリをクローンし、すべての orb と同様に `.agents/setup` スクリプトを実行して Git 認証情報を設定します。各 orb は、アカウントの Tuist <.localized_link href="/guides/features/cache">cache</.localized_link> も読み取ることができます。

## 一時停止と保持 {#retention}

スレッドがアイドル状態になると、Amp はその orb を一時停止します。次のメッセージでファイルはそのままで再開されます。

- **Linux:** 実行中のプロセスは一時停止後も維持されます。長時間一時停止された orb はアーカイブストレージに移動され、次のメッセージでプロセスなしで復元されます。Linux orb は、Amp がスレッドの orb を削除するまでファイルを保持します。
- **macOS:** 一時停止中またはエラー状態の orb が 7 日間経過すると削除されます。スレッドの次のメッセージで新しい orb が開始され、Amp が `.agents/setup` を再度実行します。マシン上の最初の macOS orb は Amp CLI をインストールするため、起動に最大 2 分かかることがあります。

Amp による一時停止が発生せずアイドル状態が続いた orb（例えば、一時停止コマンドが届かなかった場合など）は、CPU 使用率がほぼゼロの状態のまま 10 分後に一時停止されます。

## 任意の Amp スレッドから Mac を使用する {#remote-mac}

Tuist Mac プラグインを使用すると、Amp スレッドは実行場所（例えば Amp 独自の Linux orb の上）で動作し続けながら、Xcode、iOS シミュレーター、Homebrew を備えた macOS sandbox を利用できます。作業を Amp に依頼すると、必要に応じて Mac を起動します。

> 設定画面にダークモードのトグルを追加し、iOS シミュレーターでアプリを実行して、スクリーンショットを見せてください。

Amp はコード編集を実行場所で継続します。Mac 上の各コマンドの実行前に、プラグインは `tuist sandbox sync` を実行し、Git で無視されていないファイル（コミット済みかどうかを問わず）をコピーし、以降は変更されたファイルのみをコピーします。Mac が作成したビルド成果物やその他の無視されるファイルはそこに留まるため、ビルドは増分ビルドのまま維持されます。プラグインはこれらのツールと、それらをいつどのように使用するかを Amp に指示する `remote-mac` スキルを追加します。

| ツール | 機能 |
| --- | --- |
| `tuist_mac_start` | スレッド用の Mac を作成または再利用し、同期します |
| `tuist_mac_shell` | 同期してから Mac 上でコマンドを実行します |
| `tuist_mac_screenshot` | スレッド内にシミュレーターまたは画面を表示します |
| `tuist_mac_download` | ビルドされた `.app` などのファイルをコピーして戻します |
| `tuist_mac_stop` | スレッドの Mac を削除します |

Mac には Tuist CLI がインストールされており、mise でバージョンを固定している場合はプロジェクト固有のバージョンを実行します。`tuist_mac_shell` は mise の shim を `PATH` の先頭に配置します。Mac 上の各コマンドは、Tuist 4.218.0 以降を使用する場合、個別に <.localized_link href="/guides/features/sandboxes#tuist-in-sandbox">アカウントのキャッシュにサインイン</.localized_link> します。4.215.0 ～ 4.217.x を使用する場合は、Amp が事前に `tuist auth login` を実行します。

1 つのスレッドは 1 台の Mac を使用します。Amp は `tuist_mac_start` に、リポジトリで固定されている <.localized_link href="/guides/features/sandboxes#xcode">Xcode</.localized_link>（例えば `.xcode-version` など）を渡します。指定しない場合はデフォルトの Xcode が実行されます。Mac はその Xcode を保持するため、切り替えるには停止してもう一台を開始する必要があります。アイドル状態になると Tuist が一時停止し、次のコマンドで再開されます。タスクが完了すると Amp が削除します。放置された Mac は、14 日間一時停止された後に削除されます。Mac は他の sandbox と同様に Tuist アカウントの利用量としてカウントされます。

### セットアップ {#remote-mac-setup}

1. **プラグインをインストールします。** ファイルは 1 つだけで、[`tuist-mac.ts`](https://github.com/tuist/tuist/blob/main/.amp/plugins/tuist-mac.ts) です。Amp ワークスペースの全員が利用できるようにするには、ワークスペース管理者がスレッド内で Amp に以下のように依頼します。

   > Add https://raw.githubusercontent.com/tuist/tuist/main/.amp/plugins/tuist-mac.ts to our workspace plugins.

   Amp はこれをワークスペースの [プラグインリポジトリ](https://ampcode.com/docs/customize/global-plugins-and-skills) にコミットし、プッシュ前に確認を求めます。自分だけが使用するには「my personal plugins」と依頼するか、ファイル名を `.amp/plugins/tuist-mac.ts` としてリポジトリに保存してその場所でのみ使用します。プラグインはコピーであるため、更新するには同じ URL から最新バージョンに置き換えるよう Amp に依頼してください。
2. **Tuist CLI をインストールします**。Amp が実行される場所にインストールします。orb では、リポジトリの [`.agents/setup`](https://ampcode.com/docs/orbs/customizing) スクリプトに追加します。例えば `mise use -g tuist@latest` または `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist` です。
3. **CLI がアカウントの sandboxes を使用できるようにします。** orb では、<.localized_link href="/guides/server/authentication#amp-orbs">Amp orbs</.localized_link> で説明されているように Amp ワークスペースを Tuist アカウントに接続します。これにより、orb は自動的にサインインし、sandboxes にアクセスできるようになります。それ以外の場合（Linux マシン上の Amp CLI など）では、アカウントメンバーとして `tuist auth login` を実行するか、`TUIST_MAC_TOKEN` を `account:sandboxes:write` スコープを持つ <.localized_link href="/guides/server/authentication#account-tokens">アカウントトークン</.localized_link> に設定し、さらに Mac がキャッシュを使用できるように `ci` も追加します。プラグインは `TUIST_TOKEN` の代わりに `TUIST_MAC_TOKEN` を CLI に渡すため、orb にそのスコープを持たない `TUIST_TOKEN` がすでに設定されている場合も、これを設定してください。
4. **使用するアカウントを指定します**。リポジトリに `project = "<account>/<project>"` を含む `tuist.toml` がない場合です。Linux では、CLI は `Tuist.swift` からアカウントを読み取れません。Amp プロジェクトの環境変数で `TUIST_MAC_ACCOUNT` をアカウントハンドルに設定します。設定しない場合、Amp は `Tuist.swift` の `fullHandle` から取得したアカウントを `tuist_mac_start` に渡します。

CLI は `tuist.dev` を介してのみ Mac にアクセスするため、ネットワークアクセスを制限する環境ではそのドメインのみを許可する必要があります。`PATH` にない CLI を使用するには、そのパスを `TUIST_MAC_CLI` に設定します。

Claude Code や Cursor など、Amp プラグインをサポートしないエージェントでも、<.localized_link href="/guides/features/sandboxes#coding-agents">コーディングエージェントから Mac でビルドする</.localized_link> で説明されているように、Tuist MCP サーバーと CLI を介して同様の操作が可能です。

### Amp の macOS Satellites の代わりに Tuist Mac を使用する {#remote-mac-satellites}

Amp には独自のクラウド Mac である [macOS Satellites](https://ampcode.com/docs/orbs/mac) もあり、ウェイトリストに登録したワークスペース向けにベータ版として提供されています。スレッドで両方を開始できる場合、Amp の組み込み指示は macOS の作業をサテライトに送信するため、プラグインが選択されることはまれです。スレッドで Tuist Mac を使用させるには、次のいずれかを行います。

- **自分用に macOS Satellites を無効にします。** 各メンバーは、Amp の [Settings → Experimental Features](https://ampcode.com/settings/experimental-features) にある **Mac Satellites** で無効にします。
- **ワークスペース全体で無効にします。** ワークスペースの orb が [Tuist で実行](#connect) されている場合、ワークスペース管理者は Amp のワークスペース設定にある **Orbs** の下で **Where Orbs Run** を **Self-Hosted Only** に設定できます。これにより、エージェントは Amp ホストのサテライトを開始できなくなりますが、メンバーも Amp の組み込み orb を使用できなくなるため、すべてのスレッドが独自の orb プロバイダーで実行されている場合にのみ行ってください。
- **Tuist Mac をリクエストします。** プロンプト、または Amp のワークスペース設定にあるワークスペースのエージェントガイダンスに「macOS の作業には macOS Satellites ではなく `tuist_mac_*` ツールを使用してください。」を追加し、すべてのスレッドがそれに従うようにします。
