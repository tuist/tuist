---
{
  "title": "Logging",
  "titleTemplate": ":title · CLI · Contributors · Tuist",
  "description": "Learn how to contribute to Tuist by reviewing code"
}
---
# 로그 {#logging}

CLI는 로깅을 위해 [swift-log](https://github.com/apple/swift-log) 인터페이스를 사용합니다. 이 패키지는
로깅의 구현 세부 사항을 추상화하여 CLI가 로깅 백엔드에 구애받지 않고 사용할 수 있도록 합니다. 로거는 태스크 로컬을 사용하여 종속성이
주입되며 다음을 사용하여 어디서나 액세스할 수 있습니다:

```bash
Logger.current
```

::: info Mise란?
<!-- -->
태스크 로컬은 `Dispatch` 또는 분리된 태스크를 사용할 때 값을 전파하지 않으므로 이를 사용하는 경우 값을 가져와 비동기 작업에 전달해야
합니다.
<!-- -->
:::

## 기록할 내용 {#what-to-log}

로그는 CLI의 UI가 아닙니다. 로그는 문제가 발생했을 때 진단하기 위한 도구입니다. 따라서 더 많은 정보를 제공할수록 좋습니다. 새로운
기능을 만들 때는 예기치 않은 동작을 접하는 개발자의 입장에서 어떤 정보가 도움이 될지 생각해 보세요. 올바른 [로그
수준](https://www.swift.org/documentation/server/guides/libraries/log-levels.html)을
사용해야 합니다. 그렇지 않으면 개발자가 노이즈를 걸러낼 수 없습니다.
