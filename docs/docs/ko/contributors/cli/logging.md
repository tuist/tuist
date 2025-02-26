---
title: 로깅
titleTemplate: :title · CLI · Contributors · Tuist
description: 코드 리뷰를 통해 Tuist에 어떻게 기여하는지 알아봅니다.
---

# 로깅 {#logging}

CLI의 로깅은 [swift-log](https://github.com/apple/swift-log)의 인터페이스를 차용하고 있습니다. The package abstracts away the implementation details of logging, allowing the CLI to be agnostic to the logging backend. The logger is dependency-injected using [swift-service-context](https://github.com/apple/swift-service-context) and can be accessed anywhere using:

```bash
ServiceContext.current?.logger
```

> [!NOTE]
> `swift-service-context` passes the instance using [task locals](https://developer.apple.com/documentation/swift/tasklocal) which don't propagate the value when using `Dispatch`, so if you run asynchronous code using `Dispatch`, you'll to get the instance from the context and pass it to the asynchronous operation.

## What to log {#what-to-log}

로그는 CLI의 UI가 아닙니다. 로그는 이슈가 발생하였을 때 진단을 도와주는 도구입니다.
그렇기 때문에, 많은 정보를 제공할 수록 더 좋은 결과를 얻을 수 있습니다.
새로운 기능을 만들 때 자신을 예상하지 못한 동작을 발견한 개발자라고 생각하고, 어떠한 정보들을 그 개발자들에게 제공해준다면 도움이 될지 생각해보면 좋습니다.
Ensure you you use the right [log level](https://www.swift.org/documentation/server/guides/libraries/log-levels.html). Otherwise developers won't be able to filter out the noise.
