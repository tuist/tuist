---
{
  "title": "Logging",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Learn how to enable and configure logging in Tuist."
}
---
# ロギング {#logging}

CLIは問題を診断するために内部的にメッセージを記録します。

## ログを使って問題を診断する{#diagnose-issues-using-logs}。

コマンドを実行しても意図した結果が得られない場合、ログを調べることで問題を診断することができます。CLIはログを[OSLog](https://developer.apple.com/documentation/os/oslog)とファイルシステムに転送します。

すべての実行で、`$XDG_STATE_HOME/tuist/logs/{uuid}.log` にログファイルを作成します。`$XDG_STATE_HOME`
は、環境変数が設定されていない場合、`~/.local/state` の値を取ります。また、`$TUIST_XDG_STATE_HOME`
を使用して、Tuist固有のステート・ディレクトリを設定することもできます。これは、`$XDG_STATE_HOME` よりも優先されます。

::: チップ
<!-- -->
Tuistのディレクトリ構成とカスタムディレクトリの設定方法については<LocalizedLink href="/cli/directories">Directoriesドキュメント</LocalizedLink>を参照してください。
<!-- -->
:::

デフォルトでは、CLIは実行が予期せず終了したときにログのパスを出力します。出力されない場合は、上記のパス（つまり最新のログファイル）でログを見つけることができます。

::: 警告
<!-- -->
機密情報は編集されないので、ログを共有するときは慎重に。
<!-- -->
:::

### 継続的インテグレーション{#diagnose-issues-using-logs-ci}。

環境を使い捨てにするCIでは、TuistログをエクスポートするようにCIパイプラインを設定したいかもしれない。アーティファクトのエクスポートはCIサービスに共通する機能であり、設定は利用するサービスに依存する。例えば
GitHub Actions では、`actions/upload-artifact` アクションを使ってログをアーティファクトとしてアップロードできます：

```yaml
name: Node CI

on: [push]

env:
  TUIST_XDG_STATE_HOME: /tmp

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
      # ... other steps
      - run: tuist generate
      # ... do something with the project
      - name: Export Tuist logs
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: tuist-logs
          path: /tmp/tuist/logs/*.log
```

### キャッシュ・デーモンのデバッグ{#cache-daemon-debugging}。

キャッシュ関連の問題をデバッグするために、Tuistはサブシステム`dev.tuist.cache` で`os_log`
を使用してキャッシュデーモンの操作をログに記録します。これらのログをリアルタイムでストリーミングすることができます：

```bash
log stream --predicate 'subsystem == "dev.tuist.cache"' --debug
```

これらのログは、`dev.tuist.cache` サブシステムをフィルタリングすることで、Console.app
にも表示されます。これはキャッシュ操作に関する詳細な情報を提供し、キャッシュのアップロード、ダウンロード、および通信の問題を診断するのに役立ちます。
