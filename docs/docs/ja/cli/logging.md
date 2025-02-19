---
title: ロギング
titleTemplate: :title · CLI · Tuist
description: Tuist でログの有効化と設定方法を学びます。
---

# ロギング {#logging}

CLI は問題を診断するのに役立つメッセージを内部的に記録します。

## ログ {#diagnose-issues-using-logs}を使用して問題を診断する

コマンド呼び出しが意図した結果をもたらさない場合は、ログを調べることで問題を診断できます。 CLI はログを [OSLog](https://developer.apple.com/documentation/os/oslog) とファイルシステムに転送します。

実行ごとに、$XDG_STATE_HOME/tuist/logs/{uuid}.logにログファイルが作成されます。$XDG_STATE_HOMEは、環境変数が設定されていない場合、~/.local/stateの値をとります。

デフォルトでは、CLIは実行が予期せず終了した場合にログパスを出力します。 出力されない場合は、上記のパス（つまり、最新のログファイル）にログを見つけることができます。

> [!重要]
> 機密情報は編集されていませんので、ログを共有する際は注意してください。

### 継続的インテグレーション {#diagnose-issues-using-logs-ci}

使い捨て環境のCIでは、TuistログをエクスポートするためにCIパイプラインを設定することをお勧めします。
成果物のエクスポートはCIサービスに共通する機能であり、設定は利用するサービスによって異なります。
たとえば、GitHub Actionsでは、`actions/upload-artifact` アクションを使用してログを成果物としてアップロードできます：

```yaml
```
