---
{
  "title": "Install Tuist",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to install Tuist in your environment."
}
---
# Tuistのインストール {#install-tuist}

Tuist
CLIは実行ファイル、動的フレームワーク、およびリソース一式（たとえばテンプレート）から構成される。ソース](https://github.com/tuist/tuist)からTuistを手動でビルドすることもできますが、**、有効なインストールを保証するために以下のインストール方法のいずれかを使用することをお勧めします。**

### <a href="https://github.com/jdx/mise">Mise</a> {#recommended-mise}

::: info
<!-- -->
Miseは[Homebrew](https://brew.sh)の代替案として、異なる環境間でツールの確定的なバージョンを保証する必要があるチームや組織に推奨されます。
<!-- -->
:::

Tuistは以下のいずれかのコマンドでインストールできる：

```bash
mise install tuist            # Install the current version specified in .tool-versions/.mise.toml
mise install tuist@x.y.z      # Install a specific version number
mise install tuist@3          # Install a fuzzy version number
```

Homebrewのような、一つのバージョンのツールをグローバルにインストールしてアクティベートするツールとは異なり、**Miseは、グローバルまたはプロジェクトにスコープされたバージョン**
をアクティベートする必要があることに注意してください。これは、`mise use` を実行することで行えます：

```bash
mise use tuist@x.y.z          # Use tuist-x.y.z in the current project
mise use tuist@latest         # Use the latest tuist in the current directory
mise use -g tuist@x.y.z       # Use tuist-x.y.z as the global default
mise use -g tuist@system      # Use the system's tuist as the global default
```

### <a href="https://brew.sh">Homebrew</a> {#recommended-homebrew}

[Homebrew](https://brew.sh)と[公式
fomula](https://github.com/tuist/homebrew-tuist)を使ってTuistをインストールできます：

```bash
brew tap tuist/tuist
brew install --formula tuist
brew install --formula tuist@x.y.z
```

::: tip バイナリーの真正性を確認する
<!-- -->
証明書のチームが`U6LC622NKF`
であるかどうかをチェックする以下のコマンドを実行することで、インストールのバイナリが当社によってビルドされたことを確認できます：

```bash
curl -fsSL "https://docs.tuist.dev/verify.sh" | bash
```
<!-- -->
:::
