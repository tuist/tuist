---
{
  "title": "Logging",
  "titleTemplate": ":title · CLI · Contributors · Tuist",
  "description": "Learn how to contribute to Tuist by reviewing code"
}
---
# 로그 {#logging}

CLI는 로깅을 위해 [swift-log](https://github.com/apple/swift-log) 인터페이스를 채택합니다. 이 패키지는
로깅 구현 세부사항을 추상화하여 CLI가 로깅 백엔드에 무관하도록 합니다. 로거는 작업 로컬 변수를 통해 의존성 주입되며 다음을 사용하여
어디서나 접근할 수 있습니다:

```bash
Logger.current
```

::: info Mise란?
<!-- -->
`를 사용할 때 Dispatch` 또는 분리된 작업의 경우 태스크 로컬 변수의 값이 전파되지 않습니다. 따라서 해당 변수를 사용하려면 직접
가져와 비동기 작업에 전달해야 합니다.
<!-- -->
:::

## 기록할 내용 {#what-to-log}

로그는 CLI의 UI가 아닙니다. 문제가 발생했을 때 진단하는 도구입니다. 따라서 정보를 많이 제공할수록 좋습니다. 새 기능을 구축할 때는
예상치 못한 동작을 마주한 개발자의 입장에서 생각하고, 그들에게 어떤 정보가 도움이 될지 고려하세요. 올바른 [로그
수준](https://www.swift.org/documentation/server/guides/libraries/log-levels.html)을
사용해야 합니다. 그렇지 않으면 개발자가 불필요한 정보를 걸러내지 못할 것입니다.
