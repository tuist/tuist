---
{
  "title": "Tuistのインストール",
  "titleTemplate": ":title · クイックスタート · ガイド · Tuist",
  "description": "開発環境にTuistをインストールする方法を学びます"
}
---
# Tuistのインストール {#install-tuist}

Tuist CLIは、実行可能ファイル、動的フレームワーク、およびリソースのセット (たとえば、テンプレート) で構成されています。 [ソース](https://github.com/tuist/tuist)からTuistを手動でビルドすることもできますが、**有効なインストールを確保するために、以下のインストール方法のいずれかを使用することをお勧めします。**

### <a href="https://github.com/jdx/mise">Mise</a> {#recommended-mise}

:::info
Miseは、異なる環境でツールの決定的なバージョンを確保する必要があるチームや組織にとって、推奨される[Homebrew](https://brew.sh)の代替手段です。
:::

Tuist は以下のコマンドのいずれかを使用してインストールできます。

```bash
mise install tuist            # .tool-versions/.mise.tomlに指定された現在のバージョンをインストール
mise install tuist@x.y.z      # 特定のバージョン番号をインストール
mise install tuist@3          # あいまいなバージョン番号をインストール
```

Homebrewのようなツールがグローバルに単一のバージョンをインストールしてアクティブにするのに対し、**miseではバージョンをグローバルまたはプロジェクト単位で有効にする必要があります。** これは `mise use` を実行することで行います。

```bash
mise use tuist@x.y.z          # 現在のプロジェクトでtuist-x.y.zを使用
mise use tuist@latest         # 現在のディレクトリで最新のtuistを使用
mise use -g tuist@x.y.z       # tuist-x.y.zをグローバルデフォルトとして使用
mise use -g tuist@system      # システムのtuistをグローバルデフォルトとして使用
```

### <a href="https://brew.sh">Homebrew</a> {#recommended-homebrew}

Tuist は [Homebrew](https://brew.sh) と私達の [formulas](https://github.com/tuist/homebrew-tuist) を使用してインストールできます:

```bash
brew tap tuist/tuist
brew install --formula tuist
brew install --formula tuist@x.y.z
```

:::tip VERIFYING THE AUTHENTICITY OF THE BINARIES

```bash
curl -fsSL "https://docs.tuist.dev/verify.sh" | bash
```

:::
