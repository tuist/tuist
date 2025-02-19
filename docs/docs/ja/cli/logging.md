---
title: ロギング
titleTemplate: :title · CLI · Tuist
description: Tuist でログの有効化と設定方法を学びます。
---

# ロギング {#logging}

CLI は問題を診断するのに役立つメッセージを内部的に記録します。

## ログ {#diagnose-issues-using-logs}を使用して問題を診断する

コマンド呼び出しが意図した結果をもたらさない場合は、ログを調べることで問題を診断できます。 CLI はログを [OSLog](https://developer.apple.com/documentation/os/oslog) とファイルシステムに転送します。

In every run, it creates a log file at `$XDG_STATE_HOME/tuist/logs/{uuid}.log` where `$XDG_STATE_HOME` takes the value `~/.local/state` if the environment variable is not set.

By default, the CLI outputs the logs path when the execution exits unexpectedly. If it doesn't, you can find the logs in the path mentioned above (i.e., the most recent log file).

> [!重要]
> 機密情報は編集されていませんので、ログを共有する際は注意してください。

### 継続的インテグレーション {#diagnose-issues-using-logs-ci}

In CI, where environments are disposable, you might want to configure your CI pipeline to export Tuist logs.
Exporting artifacts is a common capability across CI services, and the configuration depends on the service you use.
For example, in GitHub Actions, you can use the `actions/upload-artifact` action to upload the logs as an artifact:

```yaml
```
