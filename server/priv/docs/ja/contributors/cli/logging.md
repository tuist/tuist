---
{
  "title": "ロギング",
  "titleTemplate": ":title · CLI · Contributors · Tuist",
  "description": "Tuist CLIにおけるロギングの仕組みと、コントリビューター向けのガイドライン。"
}
---
# ログ {#logging}

CLIは、ログ出力のために[swift-log](https://github.com/apple/swift-log)インターフェースを採用しています。このパッケージはログ出力の実装詳細を抽象化し、CLIがログバックエンドに依存しないようにします。ロガーはタスクローカルを使用して依存性注入され、どこからでも次の方法でアクセスできます。

```bash
Logger.current
```

> [!NOTE]
> `Dispatch`またはデタッチドタスクを使用する場合、タスクローカルは値を伝播しないため、それらを使用する際は値を取得して非同期操作に渡す必要があります。


## 何をログに記録するか {#what-to-log}

ログはCLIのユーザーインターフェースではありません。問題が発生した際に診断するためのツールです。したがって、提供する情報が多いほど良いでしょう。新機能を開発する際は、予期しない動作に遭遇した開発者の立場になり、どのような情報が役立つかを考えてください。適切な[ログレベル](https://www.swift.org/documentation/server/guides/libraries/log-levels.html)を使用してください。そうしないと、開発者はノイズをフィルタリングできなくなります。
