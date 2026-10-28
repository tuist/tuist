---
{
  "title": "Install Tuist",
  "titleTemplate": ":title · Guides · Tuist",
  "description": "Install the Tuist command-line interface on macOS or Linux with mise or Homebrew, and pin a version for teams and continuous integration."
}
---
# Tuist をインストールする {#install-tuist}

Tuist コマンドラインインターフェースは **macOS** および **Linux** で動作し、Xcode、生成されたプロジェクト、Gradle、Bazel の各プロジェクトを Tuist のキャッシュ、インサイト、ランナーインフラストラクチャに接続します。[ソース](https://github.com/tuist/tuist) から Tuist をビルドすることもできますが、有効で検証可能なインストールを保証するために、以下のインストール方法のいずれかを使用することをお勧めします。

### <a href="https://github.com/jdx/mise">Mise</a> {#recommended-mise}

> [!NOTE]
> Mise がインストールされていない場合は、まず [はじめにガイド](https://mise.jdx.dev/getting-started.html) に従ってください。異なる環境間でツールの決定論的なバージョンを保証する必要があるチームや組織の場合、Mise は [Homebrew](https://brew.sh) の推奨される代替手段です。


グローバルに単一バージョンのツールをインストールしてアクティブ化する Homebrew などのツールとは異なり、**Mise はバージョンを固定** します（グローバルまたはプロジェクト単位）。Tuist をインストールしてアクティブ化するには、`mise use` を実行してください：

```bash
mise use tuist@x.y.z          # Install and pin tuist-x.y.z in the current project
mise use tuist@latest          # Install and pin the latest tuist in the current project
mise use -g tuist@x.y.z       # Install and pin tuist-x.y.z as the global default
mise use -g tuist@system       # Use the system's tuist as the global default
```

すでに `mise.toml` で Tuist のバージョンが固定されているプロジェクトをクローンした場合は、`mise install` を実行してインストールしてください。

> [!TIP]
> `tuist@latest` は最新の **安定版** リリースに解決されます。Tuist はプレリリースのカナリービルドおよびリリース候補ビルドも公開していますが、これらはオプトインのみであり、`latest` によって解決されることはありません。信頼できる安定版ラインを固定する方法やプレリリースにオプトインする方法については、<.localized_link href="/cli/release-channels">リリースチャンネル</.localized_link> を参照してください。

<details>
<summary>Linux サポート</summary>

Linux では、Tuist は Mise 経由でのみ利用可能です。Xcode に依存するコマンド（`tuist generate` など）は Linux では利用できませんが、`tuist inspect bundle` のようなプラットフォームに依存しないコマンドは期待どおりに動作します。

</details>


### <a href="https://brew.sh">Homebrew</a> （macOS のみ） {#recommended-homebrew}

[Homebrew](https://brew.sh) と [私たちの Formula](https://github.com/tuist/homebrew-tuist) を使用して Tuist をインストールできます：

```bash
brew tap tuist/tuist
brew install --formula tuist
brew install --formula tuist@x.y.z
```

> [!TIP]
> **バイナリの真正性を検証する**
>
> 次のコマンドを実行することで、インストールされたバイナリが私たちによってビルドされたものであることを検証できます。このコマンドは、証明書のチームが `U6LC622NKF` であるかどうかを確認します：
>
> ```bash
> curl -fsSL "https://docs.tuist.dev/verify.sh" | bash
> ```

## HTTP プロキシ {#http-proxy}

ネットワークの送信トラフィックが HTTP プロキシを経由する場合は、<.localized_link href="/guides/integrations/http-proxy">HTTP プロキシガイド</.localized_link> を参照してください。
