---
title: Logging
titleTemplate: :title · CLI · Contributors · Tuist
description: Tuistへの貢献を、コードレビューを通じて学ぶ
---

# ロギング {#logging}

CLI はロギングのために [swift-log](https://github.com/apple/swift-log) インターフェースを採用しています。 パッケージはロギングの実装の詳細を抽象化し、CLIがロギングバックエンドに依存しないようにします。 ロガーは [swift-service-context](https://github.com/apple/swift-service-context) を使用して依存性を注入されており、どこからでもアクセスできます：

```bash
ServiceContext.current?.logger
```

> [!NOTE]
> `swift-service-context` は、 `Dispatch` を使用して値を伝播しない[task locals](https://developer.apple.com/documentation/swift/tasklocal) を使用してインスタンスを渡します。 ですから、`Dispatch` を使用して非同期コードを実行する場合、コンテキストからインスタンスを取得し、非同期処理に渡すことになります。

## {#what-to-log} をログに記録するもの

ログはCLIのUIではありません。 They are a tool to diagnose issues when they arise.
Therefore, the more information you provide, the better.
When building new features, put yourself in the shoes of a developer coming across unexpected behavior, and think about what information would be helpful to them.
Ensure you you use the right [log level](https://www.swift.org/documentation/server/guides/libraries/log-levels.html). Otherwise developers won't be able to filter out the noise.
