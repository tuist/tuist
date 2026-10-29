---
{
  "title": "로깅",
  "titleTemplate": ":title · CLI · 기여자 · Tuist",
  "description": "Tuist CLI에서 로깅이 작동하는 방식과 기여자를 위한 가이드라인입니다."
}
---
# 로깅 {#logging}

CLI는 로깅을 위해 [swift-log](https://github.com/apple/swift-log) 인터페이스를 사용합니다. 이 패키지는 로깅 구현 세부 사항을 추상화하여 CLI가 로깅 백엔드에 종속되지 않도록 합니다. 로거는 작업 로컬을 통해 의존성 주입되며, 어디서나 다음과 같이 접근할 수 있습니다.

```bash
Logger.current
```

> [!NOTE]
> 작업 로컬은 `Dispatch` 또는 분리된 작업을 사용할 때 값을 전파하지 않으므로, 이를 사용하는 경우 값을 가져와 비동기 작업에 전달해야 합니다.


## 로깅 대상 {#what-to-log}

로그는 CLI의 UI가 아닙니다. 문제가 발생할 때 진단하기 위한 도구입니다. 따라서 제공하는 정보가 많을수록 좋습니다. 새로운 기능을 개발할 때는 예상치 못한 동작을 마주한 개발자의 입장에서 생각해 보고, 어떤 정보가 도움이 될지 고려하세요. 올바른 [로그 수준](https://www.swift.org/documentation/server/guides/libraries/log-levels.html)을 사용해야 합니다. 그렇지 않으면 개발자가 불필요한 정보를 걸러낼 수 없습니다.
