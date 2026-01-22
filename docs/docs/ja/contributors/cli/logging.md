---
{
  "title": "Logging",
  "titleTemplate": ":title · CLI · Contributors · Tuist",
  "description": "Learn how to contribute to Tuist by reviewing code"
}
---
# ロギング {#logging}

CLIはロギングに[swift-log](https://github.com/apple/swift-log)インターフェースを採用しています。このパッケージはロギングの実装詳細を抽象化するため、CLIはロギングバックエンドに依存しません。ロガーはタスクローカル変数による依存性注入で利用可能であり、以下の方法でどこからでもアクセスできます：

```bash
Logger.current
```

::: info
<!-- -->
`を使用する場合、タスクローカルは値を伝播しません。` や分離タスクをディスパッチする際は、値を取得して非同期操作に渡す必要があります。
<!-- -->
:::

## ログに記録すべき事項{#what-to-log}

ログはCLIのUIではありません。問題発生時の診断ツールです。したがって、提供する情報が多いほど有益です。新機能を構築する際は、予期せぬ動作に遭遇した開発者の立場に立って、どのような情報が役立つかを考えてください。適切な[ログレベル](https://www.swift.org/documentation/server/guides/libraries/log-levels.html)を使用してください。そうしないと、開発者はノイズをフィルタリングできなくなります。
