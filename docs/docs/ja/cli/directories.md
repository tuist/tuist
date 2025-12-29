---
{
  "title": "Directories",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Learn how Tuist organizes its configuration, cache, and state directories."
}
---
# ディレクトリ{#directories}

Tuistは、[XDG Base Directory
Specification](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html)に従って、システム上の複数のディレクトリにわたってファイルを整理します。これにより、設定ファイル、キャッシュファイル、ステートファイルを管理するためのクリーンで標準的な方法が提供されます。

## サポートされている環境変数{#supported-environment-variables}

Tuist は標準的な XDG 変数と、Tuist 固有の接頭辞付き変数の両方をサポートしています。Tuist 固有の変種 (`TUIST_`
のプレフィックス付き) が優先されるため、Tuist を他のアプリケーションとは別に設定することができます。

### 設定ディレクトリ{#configuration-directory}

**環境変数：**
- `TUIST_XDG_CONFIG_HOME` (優先)
- `xdg_config_home`

**デフォルト：** `~/.config/tuist`

**に使用される：**
- サーバー認証情報 (`credentials/{host}.json`)

**例**
```bash
# Set Tuist-specific config directory
export TUIST_XDG_CONFIG_HOME=/custom/config
tuist auth login

# Or use standard XDG variable
export XDG_CONFIG_HOME=/custom/config
tuist auth login
```

### キャッシュ・ディレクトリ{#cache-directory}

**環境変数：**
- `TUIST_XDG_CACHE_HOME` (優先)
- `XDG_CACHE_HOME`

**デフォルト：** `~/.cache/tuist`

**に使用される：**
- **プラグイン** ：ダウンロードしてコンパイルしたプラグインキャッシュ
- **ProjectDescriptionHelpers** ：コンパイルされたプロジェクト説明ヘルパー
- **マニフェスト** ：マニフェストファイルのキャッシュ
- **プロジェクト** ：生成されたオートメーション・プロジェクトのキャッシュ
- **EditProjects** ：編集コマンドのキャッシュ
- **Runs**: 分析データのテストと構築
- **バイナリ** ：ビルド・アーティファクト・バイナリ（環境間で共有不可）
- **SelectiveTests** ：選択テスト・キャッシュ

**例**
```bash
# Set Tuist-specific cache directory
export TUIST_XDG_CACHE_HOME=/tmp/tuist-cache
tuist cache

# Or use standard XDG variable
export XDG_CACHE_HOME=/tmp/cache
tuist cache
```

### 州ディレクトリ{#state-directory}

**環境変数：**
- `TUIST_XDG_STATE_HOME` (優先)
- `XDG_STATE_HOME`

**デフォルト：** `~/.local/state/tuist`

**に使用される：**
- **ログ** ：ログファイル (`logs/{uuid}.log`)
- **ロック** ：認証ロックファイル (`{handle}.sock`)

**例**
```bash
# Set Tuist-specific state directory
export TUIST_XDG_STATE_HOME=/var/log/tuist
tuist generate

# Or use standard XDG variable
export XDG_STATE_HOME=/var/log
tuist generate
```

## 優先順位{#precedence-order}

どのディレクトリを使うかを決めるとき、Tuistは次の順序で環境変数をチェックする：

1. **Tuist固有の変数** (例:`TUIST_XDG_CONFIG_HOME`)
2. **XDG 標準変数** (例:`XDG_CONFIG_HOME`)
3. **デフォルトの場所** (例:`~/.config/tuist`)

これにより、次のことが可能になる：
- 標準の XDG 変数を使用して、すべてのアプリケーションを一貫して整理します。
- Tuistに異なる場所が必要な場合、Tuist固有の変数でオーバーライドする。
- 設定なしで賢明なデフォルトに頼る

## 一般的な使用例{#common-use-cases}

### プロジェクトごとにTuistを分離{#isolating-tuist-per-project}

Tuistのキャッシュと状態をプロジェクトごとに分離したいかもしれない：

```bash
# In your project's .envrc (using direnv)
export TUIST_XDG_CACHE_HOME="$PWD/.tuist/cache"
export TUIST_XDG_STATE_HOME="$PWD/.tuist/state"
export TUIST_XDG_CONFIG_HOME="$PWD/.tuist/config"
```

### CI/CD環境{#ci-cd-environments}

CI環境では、テンポラリ・ディレクトリを使いたいかもしれない：

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

### 隔離されたディレクトリでのデバッグ{#debugging-with-isolated-directories}

問題をデバッグするときには、まっさらな状態にしておきたいものだ：

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
