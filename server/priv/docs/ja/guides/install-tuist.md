---
{
  "title": "Tuist のインストール",
  "titleTemplate": ":title · ガイド · Tuist",
  "description": "mise または Homebrew を使用して、macOS または Linux に Tuist コマンドラインインターフェースをインストールし、チームや継続的インテグレーション向けにバージョンを固定します。"
}
---
# Tuist をインストールする {#install-tuist}

Tuist のコマンドラインインターフェースは **macOS** および **Linux** で動作し、Xcode、生成済み、Gradle、Bazel の各プロジェクトを Tuist のキャッシュ、インサイト、ランナーインフラストラクチャに接続します。[ソース](https://github.com/tuist/tuist) から Tuist をビルドすることもできますが、有効で検証可能なインストールを保証するため、以下のいずれかのインストール方法を推奨します。

### <a href="https://github.com/jdx/mise">Mise</a> {#recommended-mise}

> [!NOTE]
> Mise がインストールされていない場合は、まず [はじめにガイド](https://mise.jdx.dev/getting-started.html) に従ってください。異なる環境間でツールのバージョンを確実に決定論的に揃える必要があるチームや組織には、[Homebrew](https://brew.sh) の代わりに Mise を使用することを推奨します。


グローバルに単一バージョンのツールをインストールしてアクティブ化する Homebrew などのツールとは異なり、**Mise はバージョンを固定** します（グローバルまたはプロジェクト単位）。Tuist をインストールしてアクティブ化するには `mise use` を実行してください：

```bash
mise use tuist@x.y.z          # Install and pin tuist-x.y.z in the current project
mise use tuist@latest          # Install and pin the latest tuist in the current project
mise use -g tuist@x.y.z       # Install and pin tuist-x.y.z as the global default
mise use -g tuist@system       # Use the system's tuist as the global default
```

すでに `mise.toml` で Tuist のバージョンが固定されているプロジェクトをクローンした場合は、`mise install` を実行してインストールしてください。

> [!TIP]
> `tuist@latest` は最新の **安定版** リリースに解決されます。Tuist はプレリリースのカナリアビルドとリリース候補ビルドも公開していますが、これらはオプトインのみであり、`latest` では決して解決されません。信頼できる安定版ラインを固定する方法とプレリリースにオプトインする方法については、<.localized_link href="/cli/release-channels">リリースチャンネル</.localized_link> を参照してください。

<details>
<summary>Linux のサポート</summary>

Linux では、Tuist は Mise 経由でのみ利用可能です。Xcode に依存するコマンド（`tuist generate` など）は Linux では利用できませんが、`tuist inspect bundle` のようなプラットフォーム非依存のコマンドは期待どおりに動作します。

</details>


### <a href="https://brew.sh">Homebrew</a>（macOS のみ） {#recommended-homebrew}

[Homebrew](https://brew.sh) と [当社の Formula](https://github.com/tuist/homebrew-tuist) を使用して Tuist をインストールできます：

```bash
brew tap tuist/tuist
brew install --formula tuist
brew install --formula tuist@x.y.z
```

> [!TIP]
> **バイナリの正当性を検証する**
>
> 次のコマンドを実行すると、インストールされたバイナリが当社によってビルドされたものであることを確認できます。このコマンドは、証明書のチームが `U6LC622NKF` であることを確認します：
>
> ```bash
> curl -fsSL "https://docs.tuist.dev/verify.sh" | bash
> ```

## HTTP プロキシ {#http-proxy}

ネットワークの送信トラフィックが HTTP プロキシを経由する場合は、<.localized_link href="/guides/integrations/http-proxy">HTTP プロキシガイド</.localized_link> を参照してください。
