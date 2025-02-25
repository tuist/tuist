---
title: ロギング
titleTemplate: :title · CLI · Contributors · Tuist
description: Tuistへの貢献を、コードレビューを通じて学ぶ
---

# ロギング {#logging}

CLI はロギングのために [swift-log](https://github.com/apple/swift-log) インターフェースを採用しています。 パッケージはロギングの実装の詳細を抽象化し、CLIがロギングバックエンドに依存しないようにします。 ロガーは [swift-service-context](https://github.com/apple/swift-service-context) を使用して依存性を注入されており、どこからでもアクセスできます： パッケージはロギングの実装の詳細を抽象化し、CLIがロギングバックエンドに依存しないようにします。 ロガーは [swift-service-context](https://github.com/apple/swift-service-context) を使用して依存性を注入されており、どこからでもアクセスできます： パッケージはロギングの実装の詳細を抽象化し、CLIがロギングバックエンドに依存しないようにします。 ロガーは [swift-service-context](https://github.com/apple/swift-service-context) を使用して依存性を注入されており、どこからでもアクセスできます：

```bash
ServiceContext.current?.logger
```

> [!NOTE]
> `swift-service-context` は、 `Dispatch` を使用して値を伝播しない[task locals](https://developer.apple.com/documentation/swift/tasklocal) を使用してインスタンスを渡します。 ですから、`Dispatch` を使用して非同期コードを実行する場合、コンテキストからインスタンスを取得し、非同期処理に渡すことになります。

## {#what-to-log} をログに記録するもの

ログはCLIのUIではありません。 ログは発生した問題を診断するためのツールです。
したがって、提供する方法が多いほど良いです。
新しい機能を構築するときは、予期せぬ動作に遭遇する開発者の立場になって、 どんな情報が役に立つか考えください。
ログはCLIのUIではありません。 ログは発生した問題を診断するためのツールです。
したがって、提供する方法が多いほど良いです。
新しい機能を構築するときは、予期せぬ動作に遭遇する開発者の立場になって、 どんな情報が役に立つか考えください。
適切な[log level](https://www.swift.org/documentation/server/guides/libraries/log-levels.html)を使用することを徹底しましょう。 そうしないと、開発者は不要な情報を除去することができなくなってしまいます。 そうしないと、開発者は不要な情報を除去することができなくなってしまいます。
