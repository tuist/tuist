---
{
  "title": "ディレクトリ",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Tuist が設定、キャッシュ、および状態のディレクトリをどのように整理するかを学びます。"
}
---
# ディレクトリ {#directories}

Tuistは、[XDG Base Directory Specification](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html)に従って、システム上の複数のディレクトリにファイルを整理します。これにより、構成、キャッシュ、および状態ファイルを管理するためのクリーンで標準的な方法が提供されます。

## サポートされている環境変数 {#supported-environment-variables}

Tuistは、標準のXDG変数とTuist固有のプレフィックス付きバリアントの両方をサポートしています。Tuist固有のバリアント（`TUIST_`でプレフィックス）が優先され、他のアプリケーションとは別にTuistを設定できます。

### 構成ディレクトリ {#configuration-directory}

**環境変数:**
- `TUIST_XDG_CONFIG_HOME` （優先）
- `XDG_CONFIG_HOME`

**デフォルト:** `~/.config/tuist`

**用途:**
- サーバー認証情報 (`credentials/{host}.json`)

**例:**
```bash
# Set Tuist-specific config directory
export TUIST_XDG_CONFIG_HOME=/custom/config
tuist auth login

# Or use standard XDG variable
export XDG_CONFIG_HOME=/custom/config
tuist auth login
```

### キャッシュディレクトリ {#cache-directory}

**環境変数:**
- `TUIST_XDG_CACHE_HOME` （優先）
- `XDG_CACHE_HOME`

**デフォルト:** `~/.cache/tuist`

**用途:**
- **Plugins**: ダウンロードおよびコンパイルされたプラグインキャッシュ
- **ProjectDescriptionHelpers**: コンパイルされたプロジェクト記述ヘルパー
- **Manifests**: キャッシュされたマニフェストファイル
- **Projects**: 生成された自動化プロジェクトキャッシュ
- **EditProjects**: editコマンド用のキャッシュ
- **Runs**: テストおよびビルド実行の分析データ
- **Binaries**: ビルド成果物バイナリ（環境間で共有不可）
- **SelectiveTests**: 選択的テストキャッシュ

**例:**
```bash
# Set Tuist-specific cache directory
export TUIST_XDG_CACHE_HOME=/tmp/tuist-cache
tuist cache

# Or use standard XDG variable
export XDG_CACHE_HOME=/tmp/cache
tuist cache
```

### 状態ディレクトリ {#state-directory}

**環境変数:**
- `TUIST_XDG_STATE_HOME` （優先）
- `XDG_STATE_HOME`

**デフォルト:** `~/.local/state/tuist`

**用途:**
- **Sessions**: セッションログとネットワーク記録 (`sessions/{uuid}/`)
- **Locks**: 認証ロックファイル (`{handle}.sock`)

**例:**
```bash
# Set Tuist-specific state directory
export TUIST_XDG_STATE_HOME=/var/log/tuist
tuist generate

# Or use standard XDG variable
export XDG_STATE_HOME=/var/log
tuist generate
```

## 優先順位 {#precedence-order}

使用するディレクトリを決定する際、Tuistは以下の順序で環境変数を確認します:

1. **Tuist固有の変数** （例: `TUIST_XDG_CONFIG_HOME`）
2. **標準のXDG変数** （例: `XDG_CONFIG_HOME`）
3. **デフォルトの場所** （例: `~/.config/tuist`）

これにより、次のことが可能になります:
- 標準のXDG変数を使用して、すべてのアプリケーションを一貫して整理する
- Tuistに異なる場所が必要な場合は、Tuist固有の変数で上書きする
- 設定なしで妥当なデフォルト値を利用する

## 一般的なユースケース {#common-use-cases}

### プロジェクトごとにTuistを隔離する {#isolating-tuist-per-project}

プロジェクトごとにTuistのキャッシュと状態を隔離したい場合があります:

```bash
# In your project's .envrc (using direnv)
export TUIST_XDG_CACHE_HOME="$PWD/.tuist/cache"
export TUIST_XDG_STATE_HOME="$PWD/.tuist/state"
export TUIST_XDG_CONFIG_HOME="$PWD/.tuist/config"
```

### CI/CD環境 {#ci-cd-environments}

CI環境では、一時ディレクトリを使用したい場合があります:

```yaml
# GitHub Actions example
env:
  TUIST_XDG_CACHE_HOME: /tmp/tuist-cache
  TUIST_XDG_STATE_HOME: /tmp/tuist-state

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - run: tuist generate
      - name: Upload logs
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: tuist-logs
          path: /tmp/tuist-state/logs/*.log
```

### 隔離されたディレクトリを使用したデバッグ {#debugging-with-isolated-directories}

問題をデバッグする際は、クリーンな状態から始めたい場合があります:

```bash
# Create temporary directories for debugging
export TUIST_XDG_CACHE_HOME=$(mktemp -d)
export TUIST_XDG_STATE_HOME=$(mktemp -d)
export TUIST_XDG_CONFIG_HOME=$(mktemp -d)

# Run Tuist commands
tuist generate

# Clean up when done
rm -rf $TUIST_XDG_CACHE_HOME $TUIST_XDG_STATE_HOME $TUIST_XDG_CONFIG_HOME
```
