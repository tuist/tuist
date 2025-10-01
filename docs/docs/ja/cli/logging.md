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

実行ごとに、`$XDG_STATE_HOME/tuist/logs/{uuid}.log` にログファイルが作成されます。`$XDG_STATE_HOME`
は、環境変数が設定されていない場合、`~/.local/state` の値を取ります。

デフォルトでは、CLIは実行が予期せず終了したときにログのパスを出力します。出力されない場合は、上記のパス（つまり最新のログファイル）でログを見つけることができます。

> [重要】機密情報は編集されないので、ログを共有するときは慎重に。

### 継続的インテグレーション{#diagnose-issues-using-logs-ci}。

環境を使い捨てにするCIでは、TuistログをエクスポートするようにCIパイプラインを設定したいかもしれない。アーティファクトのエクスポートはCIサービスに共通する機能であり、設定は利用するサービスに依存する。例えば
GitHub Actions では、`actions/upload-artifact` アクションを使ってログをアーティファクトとしてアップロードできます：

```yaml
name: Node CI

on: [push]

env:
  XDG_STATE_HOME: /tmp

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
        uses: actions/upload-artifact@v4
        with:
          name: tuist-logs
          path: /tmp/tuist/logs/*.log
```
