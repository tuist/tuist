---
title: 로깅
titleTemplate: :title · CLI · Contributors · Tuist
description: 코드 리뷰를 통해 Tuist에 어떻게 기여하는지 알아봅니다.
---

# 로깅 {#logging}

CLI의 로깅은 [swift-log](https://github.com/apple/swift-log)의 인터페이스를 차용하고 있습니다. 이 패키지는 로깅의 세부 구현 사항을 추상화하여 CLI가 로깅 백엔드에 종속되지 않도록 합니다. 로거는 태스크 로컬을 사용하여 의존성 주입되고, 다음과 같이 어디서든 접근할 수 있습니다:

```bash
Logger.current
```

> [!NOTE]\
> `Dispatch`나 분리된(detached) 태스크를 사용하는 경우 태스크 로컬의 값이 전달되지 않으므로, 이것을 사용할 경우 값을 가져와서 직접 비동기 작업에 전달해야 합니다.

## 무엇을 로깅하는 것이 좋을까요? {#what-to-log}

로그는 CLI의 UI가 아닙니다. 로그는 이슈가 발생하였을 때 진단을 도와주는 도구입니다.
그렇기 때문에, 많은 정보를 제공할 수록 더 좋은 결과를 얻을 수 있습니다.
새로운 기능을 만들 때 자신을 예상하지 못한 동작을 발견한 개발자라고 생각하고, 어떠한 정보들을 그 개발자들에게 제공해준다면 도움이 될지 생각해보면 좋습니다.
적절한 [log level](https://www.swift.org/documentation/server/guides/libraries/log-levels.html)을 사용하고 있는 지 확인하십시요. 그렇지 않으면 개발자들이 불필요한 정보들을 필터링하기 어려워집니다.
