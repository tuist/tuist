---
{
  "title": "Directories",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Learn how Tuist organizes its configuration, cache, and state directories."
}
---
# ディレクトリ{#directories}

Tuistは、[XDG Base Directory
Specification](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html)に従い、システム上の複数のディレクトリにファイルを整理します。これにより、設定ファイル、キャッシュファイル、状態ファイルを管理するためのクリーンで標準的な方法が提供されます。

## サポートされている環境変数{#supported-environment-variables}

Tuistは標準のXDG変数とTuist固有の接頭辞付き変数の両方をサポートします。Tuist固有の変数（`TUIST_`
で始まるもの）が優先され、他のアプリケーションとは別にTuistを設定できます。

### 設定ディレクトリ{#configuration-directory}

**環境変数:**
- `TUIST_XDG_CONFIG_HOME` (優先される)
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

### キャッシュディレクトリ{#cache-directory}

**環境変数:**
- `TUIST_XDG_CACHE_HOME` (優先される)
- `XDG_CACHE_HOME`

**デフォルト:** `~/.cache/tuist`

**用途:**
- **プラグイン**: ダウンロード済みおよびコンパイル済みプラグインキャッシュ
- **ProjectDescriptionHelpers**: コンパイル済みプロジェクト説明ヘルパー
- **マニフェスト**: キャッシュされたマニフェストファイル
- **プロジェクト**: 自動生成プロジェクトキャッシュ
- **EditProjects**: 編集コマンド用キャッシュ
- **** を実行：テストおよびビルド実行の分析データを収集
- **バイナリ**: ビルド成果物バイナリ（環境間で共有不可）
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

### 州ディレクトリ{#state-directory}

**環境変数:**
- `TUIST_XDG_STATE_HOME` (優先度が高い)
- `XDG_STATE_HOME`

**デフォルト:** `~/.local/state/tuist`

**用途:**
- **ログ**: ログファイル (`logs/{uuid}.log`)
- **ロック**: 認証ロックファイル (`{handle}.sock`)

**例:**
```bash
# Set Tuist-specific state directory
export TUIST_XDG_STATE_HOME=/var/log/tuist
tuist generate

# Or use standard XDG variable
export XDG_STATE_HOME=/var/log
tuist generate
```

## 優先順位{#precedence-order}

使用するディレクトリを決定する際、Tuistは以下の順序で環境変数をチェックします：

1. **Tuist固有の変数** (例:`TUIST_XDG_CONFIG_HOME`)
2. **標準XDG変数** （例：`XDG_CONFIG_HOME` ）
3. **デフォルトの場所** (例:`~/.config/tuist`)

これにより、以下のことが可能になります：
- すべてのアプリケーションを一貫して整理するには、標準のXDG変数を使用してください
- Tuist用に異なる位置が必要な場合は、Tuist固有の変数で上書きしてください
- 設定なしで合理的なデフォルトに依存する

## 一般的な使用例{#common-use-cases}

### プロジェクトごとにTuistを分離する{#isolating-tuist-per-project}

プロジェクトごとにTuistのキャッシュと状態を分離することを検討してください：

```bash
# In your project's .envrc (using direnv)
export TUIST_XDG_CACHE_HOME="$PWD/.tuist/cache"
export TUIST_XDG_STATE_HOME="$PWD/.tuist/state"
export TUIST_XDG_CONFIG_HOME="$PWD/.tuist/config"
```

### CI/CD環境{#ci-cd-environments}

CI環境では、一時ディレクトリの使用が推奨されます：

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

### 分離されたディレクトリでのデバッグ{#debugging-with-isolated-directories}

問題のデバッグ時には、白紙の状態から始めたい場合があります：

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
