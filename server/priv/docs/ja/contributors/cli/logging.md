---
{
  "title": "ログ出力",
  "titleTemplate": ":title · CLI · Contributors · Tuist",
  "description": "Tuist CLIでのログ出力の仕組みと、コントリビューター向けのガイドライン。"
}
---
# ロギング {#logging}

CLI はロギングのために [swift-log](https://github.com/apple/swift-log) インターフェースを採用しています。このパッケージはロギングの実装詳細を抽象化し、CLI がロギングバックエンドに依存しないようにします。ロガーはタスクローカルを使用して依存性注入され、次の方法でどこからでもアクセスできます:

```bash
Logger.current
```

> [!NOTE]
> `Dispatch` またはデタッチドタスクを使用する場合、タスクローカルは値を伝播しません。そのため、これらを使用する場合は値を取得し、非同期操作に渡す必要があります。


## ログに記録すべき内容 {#what-to-log}

ログは CLI の UI ではありません。問題が発生した際に診断するためのツールです。したがって、提供する情報が多いほど効果的です。新機能を構築する際は、予期せぬ動作に遭遇した開発者の立場に立ち、どのような情報が役立つかを考えてください。適切な [ログレベル](https://www.swift.org/documentation/server/guides/libraries/log-levels.html) を使用するようにしてください。そうしないと、開発者はノイズをフィルタリングできなくなります。
