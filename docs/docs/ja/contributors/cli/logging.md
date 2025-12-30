---
{
  "title": "Logging",
  "titleTemplate": ":title · CLI · Contributors · Tuist",
  "description": "Learn how to contribute to Tuist by reviewing code"
}
---
# ロギング {#logging}

CLIはロギングのための[swift-log](https://github.com/apple/swift-log)インターフェースを受け入れます。このパッケージはロギングの実装の詳細を抽象化し、CLI
がロギングバックエンドに依存しないようにします。ロガーはタスクローカルを使用して依存関係注入され、[swift-log](https://github.com/apple/swift-log)を使用してどこにでもアクセスできます：

```bash
Logger.current
```

::: info
<!-- -->
タスク・ローカルは、`Dispatch`
やデタッチド・タスクを使用したときに値を伝搬しないので、それらを使用する場合は、値を取得して非同期操作に渡す必要がある。
<!-- -->
:::

## 何を記録するか{#what-to-log}

ログはCLIのUIではない。問題が発生したときに診断するためのツールです。したがって、提供する情報は多ければ多いほど良い。新しい機能を作るときは、予想外の動作に出くわした開発者の立場になって、彼らにとってどんな情報が役に立つかを考えてください。正しい
[ログレベル](https://www.swift.org/documentation/server/guides/libraries/log-levels.html)
を使うようにしてください。そうしないと、開発者はノイズをフィルタリングできません。
