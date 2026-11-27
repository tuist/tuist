---
{
  "title": "ロギング",
  "titleTemplate": ":title · CLI · Contributors · Tuist",
  "description": "Tuist CLIでのロギングの仕組みと、コントリビューター向けのガイドライン。"
}
---
# ログ {#logging}

CLIは、ログ出力のために[swift-log](https://github.com/apple/swift-log)インターフェースを採用しています。このパッケージはログ出力の実装詳細を抽象化し、CLIが特定のログバックエンドに依存しないようにします。ロガーはタスクローカルを使用して依存性注入され、どこからでも以下のようにアクセスできます。

```bash
Logger.current
```

> [!NOTE]
> `Dispatch`またはデタッチされたタスクを使用する場合、タスクローカルは値を伝播しません。そのため、これらを使用する際は、値を取得して非同期操作に渡す必要があります。


## 何をログに残すか {#what-to-log}

ログはCLIのUIではありません。問題が発生した際に診断するためのツールです。したがって、提供する情報が多いほど有益です。新機能を実装する際は、予期しない動作に遭遇した開発者の立場になり、どのような情報が役立つかを考えてください。適切な[ログレベル](https://www.swift.org/documentation/server/guides/libraries/log-levels.html)を使用してください。そうしないと、開発者は不要な情報をフィルタリングできなくなります。
