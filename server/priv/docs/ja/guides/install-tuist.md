---
{
  "title": "Install Tuist",
  "titleTemplate": ":title · Guides · Tuist",
  "description": "Install the Tuist command-line interface on macOS or Linux with mise or Homebrew, and pin a version for teams and continuous integration."
}
---
# Tuist {#install-tuist}をインストール

Tuist コマンドラインインターフェースは **macOS** および **Linux** で動作し、Xcode、生成されたプロジェクト、Gradle、Bazel プロジェクトを Tuist のキャッシュ、インサイト、ランナーインフラストラクチャに接続します。Tuist は [ソース](https://github.com/tuist/tuist)からビルドできますが、有効で検証可能なインストールを保証するために、以下のインストール方法のいずれかを使用することをお勧めします。

### <a href="https://github.com/jdx/mise">Mise</a> {#recommended-mise}

> \[\!NOTE\]
> Miseがインストールされていない場合は、 [はじめにガイド](https://mise.jdx.dev/getting-started.html) まず、Miseは推奨される代替手段です。 [Homebrew](https://brew.sh) 異なる環境間でツールのバージョンを確実に決定論的に管理する必要があるチームや組織の場合。

Homebrewのようなツールとは異なり、単一のバージョンをグローバルにインストールしてアクティブ化するのではなく、 **Miseはバージョンを固定します** 。グローバルまたはプロジェクトスコープで設定できます。Tuistをインストールしてアクティブ化するには、 `mise use` を実行してください:

```bash
mise use tuist@x.y.z          # Install and pin tuist-x.y.z in the current project
mise use tuist@latest          # Install and pin the latest tuist in the current project
mise use -g tuist@x.y.z       # Install and pin tuist-x.y.z as the global default
mise use -g tuist@system       # Use the system's tuist as the global default
```

Tuistのバージョンがすでに固定されているプロジェクトをクローンした場合、 `mise.toml`を実行してください `mise install` インストールするには、

> \[\!TIP\]
> `tuist@latest` 最新の **安定版** リリースに解決されます。Tuistはプレリリースのカナリアビルドやリリース候補ビルドも公開していますが、これらはオプトインのみで、 `latest`によって自動的に解決されることはありません。信頼できる安定版ラインを固定する方法や、プレリリースをオプトインする方法については、\<.localized\_link href="/cli/release-channels"\>リリースチャンネル\</.localized\_link\>をご覧ください。

<details>
<summary>Linux support</summary>

Linuxでは、TuistはMise経由でのみ利用可能です。Xcodeに依存するコマンド（ `tuist generate`など）はLinuxでは利用できませんが、プラットフォームに依存しないコマンド（ `tuist inspect bundle` など）は期待通りに動作します。

</details>

### <a href="https://brew.sh">Homebrew</a> （macOSのみ）{#recommended-homebrew}

Tuistは、 [Homebrew](https://brew.sh) と [当社のレシピ](https://github.com/tuist/homebrew-tuist):

```bash
brew tap tuist/tuist
brew install --formula tuist
brew install --formula tuist@x.y.z
```

> \[\!TIP\]
> **バイナリの真正性の検証**
> 
> 次のコマンドを実行して、インストールされたバイナリが当社によってビルドされたことを確認できます。これにより、証明書のチームが以下であるかを確認します。 `U6LC622NKF`:
> 
> ```bash
> curl -fsSL "https://docs.tuist.dev/verify.sh" | bash
> ```

## HTTP プロキシ {#http-proxy}

ネットワークの送信トラフィックが HTTP プロキシを経由する場合は、\<.localized\_link href="/guides/integrations/http-proxy"\>HTTP プロキシガイド\</.localized\_link\>をご覧ください。