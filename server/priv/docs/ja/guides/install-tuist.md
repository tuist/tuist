---
{
  "title": "Tuist のインストール",
  "titleTemplate": ":title · ガイド · Tuist",
  "description": "mise または Homebrew を使用して、macOS または Linux に Tuist コマンドラインインターフェースをインストールし、チームや継続的インテグレーション向けにバージョンを固定します。"
}
---
# Tuist をインストールする {#install-tuist}

Tuist のコマンドラインインターフェースは **macOS** および **Linux** で動作し、Xcode、生成済み、Gradle、Bazel、Rust の各プロジェクトを Tuist のキャッシュ、インサイト、ランナーインフラストラクチャに接続します。[ソース](https://github.com/tuist/tuist) から Tuist をビルドすることもできますが、有効で検証可能なインストールを保証するために、以下のインストール方法のいずれかをお勧めします。Elixir プロジェクトでは代わりに `tuist_ex` Hex パッケージを使用するため、CLI は不要です。

## Mise {#recommended-mise}

> [!NOTE]
> Mise がインストールされていない場合は、まず [はじめにガイド](https://mise.jdx.dev/getting-started.html) に従ってください。異なる環境間でツールのバージョンを決定論的に揃える必要があるチームや組織には、[Homebrew](https://brew.sh) の代替として Mise をお勧めします。


Homebrew のようにツールをグローバルに単一バージョンでインストールしてアクティブ化するのではなく、**Mise はバージョンを固定** します（グローバルまたはプロジェクト単位）。Tuist をインストールしてアクティブ化するには `mise use` を実行してください：

```bash
mise use tuist@x.y.z          # Install and pin tuist-x.y.z in the current project
mise use tuist@latest          # Install and pin the latest tuist in the current project
mise use -g tuist@x.y.z       # Install and pin tuist-x.y.z as the global default
mise use -g tuist@system       # Use the system's tuist as the global default
```

すでに `mise.toml` で Tuist のバージョンが固定されているプロジェクトをクローンした場合は、`mise install` を実行してインストールしてください。

> [!TIP]
> `tuist@latest` は最新の **安定版** リリースに解決されます。Tuist はプレリリースのカナリー版およびリリース候補版も公開していますが、これらはオプトインのみであり、`latest` では決して解決されません。信頼できる安定版ラインを固定する方法やプレリリースへのオプトイン方法については、<.localized_link href="/cli/release/channels">リリースチャンネル</.localized_link> を参照してください。

<details>
<summary>Linux サポート</summary>

Linux では、Tuist は Mise 経由でのみ利用可能です。Xcode に依存するコマンド（`tuist generate` など）は Linux では利用できませんが、プラットフォームに依存しないコマンド（`tuist inspect bundle` など）は期待どおりに動作します。

</details>


## Homebrew（macOS のみ） {#recommended-homebrew}

[Homebrew](https://brew.sh) と [私たちの Formula](https://github.com/tuist/homebrew-tuist) を使用して Tuist をインストールできます：

```bash
brew tap tuist/tuist
brew install --formula tuist
brew install --formula tuist@x.y.z
```

> [!TIP]
> **バイナリの正当性を検証する**
>
> 次のコマンドを実行すると、インストールされたバイナリが私たちによってビルドされたことを検証できます。このコマンドは証明書のチーム ID が `U6LC622NKF` であることを確認します：
>
> ```bash
> curl -fsSL "https://docs.tuist.dev/verify.sh" | bash
> ```

## HTTP プロキシ {#http-proxy}

ネットワークの送信トラフィックが HTTP プロキシを経由する場合は、<.localized_link href="/guides/integrations/http-proxy">HTTP プロキシガイド</.localized_link> を参照してください。

## 次のステップ {#next-steps}

- プロジェクトを Tuist に接続するには、<.localized_link href="/guides/get-started">はじめにガイド</.localized_link> に従ってください。
- より広範な製品コンテキストについては、[エンジニアリングチームとコーディングエージェント向け Tuist のビルドインフラストラクチャ](https://tuist.dev) をご覧ください。
