---
title: ロギング
titleTemplate: :title · CLI · Tuist
description: Tuist でログを有効にして設定する方法を学ぶ。
---

# ロギング {#logging}

CLI は問題を診断するのに役立つメッセージを内部的に記録します。

## ログを使用して問題を診断する {#diagnose-issues-using-logs}

コマンド呼び出しが意図した結果をもたらさない場合は、ログを調べることで問題を診断できます。 CLI はログを [OSLog](https://developer.apple.com/documentation/os/oslog) とファイルシステムに転送します。

実行ごとに、`$XDG_STATE_HOME/tuist/logs/{uuid}.log` にログファイルが作成されます。環境変数が設定されていない場合、 `$XDG_STATE_HOME` は `~/.local/state` の値をとります。

デフォルトでは、CLIは実行が予期せず終了した場合にログのパスを出力します。 出力されない場合は、上記のパス（つまり、最新のログファイル）にログを見つけることができます。

> [!IMPORTANT]
> 機密情報はマスキングされていないので、ログを共有する際は注意してください。

### 継続的インテグレーション {#diagnose-issues-using-logs-ci}

CIでは、環境が使い捨てであるため、CIパイプラインを設定してTuistのログをエクスポートすることを検討する必要があるかもしれません。
成果物のエクスポートはCIサービスに共通する機能であり、設定は利用するサービスによって異なります。
たとえば、GitHub Actionsでは、`actions/upload-artifact` アクションを使用してログを成果物としてアップロードできます：

```yaml
```
