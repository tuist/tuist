---
{
  "title": "디버깅",
  "titleTemplate": ":title · 기여자 · Tuist",
  "description": "코딩 에이전트와 로컬 실행을 사용하여 Tuist의 문제를 디버깅하세요."
}
---
# 디버깅 {#debugging}

오픈 소스라는 점은 실용적인 장점입니다. 코드를 직접 확인할 수 있고, 로컬에서 실행할 수 있으며, 코딩 에이전트를 활용해 질문에 더 빠르게 답변하고 코드베이스의 잠재적 버그를 디버깅할 수 있습니다.

디버깅 중 누락되거나 불완전한 문서를 발견하면 `docs/` 아래의 영어 문서를 업데이트하고 PR을 열어주세요.

## CI에서 스레드 덤프 캡처하기 {#thread-dump-ci}

CLI가 간헐적으로 멈출 때 프로세스를 중단하지 않고 스레드 덤프를 캡처할 수 있습니다. 시그널 핸들러를 활성화하고 실행 중인 `tuist` 프로세스에 `SIGUSR1`를 전송하세요.

```bash
export TUIST_THREAD_DUMP_SIGNAL=1
export TUIST_THREAD_DUMP_SAMPLE=1 # macOS only, captures all threads via /usr/bin/sample
tuist generate &
TUIST_PID=$!
sleep 600
kill -USR1 "$TUIST_PID"
wait "$TUIST_PID"
```

`TUIST_THREAD_DUMP_SAMPLE`가 설정되지 않으면 핸들러는 현재 스레드 스택을 출력합니다. 출력은 stderr로 기록되므로 CI 로그에 표시됩니다.

## 코딩 에이전트 사용하기 {#use-coding-agents}

코딩 에이전트는 다음과 같은 경우에 유용합니다:

- 특정 동작이 구현된 위치를 코드베이스에서 검색합니다.
- 로컬에서 문제를 재현하고 빠르게 반복합니다.
- Tuist를 통해 입력이 어떻게 흐르는지 추적하여 근본 원인을 찾습니다.

가능한 가장 작은 재현 사례를 공유하고, 에이전트가 특정 컴포넌트(CLI, 서버, 캐시, 문서 또는 핸드북)를 대상으로 하도록 지정하세요. 범위가 집중될수록 디버깅 과정이 더 빠르고 정확해집니다.

### 자주 필요한 프롬프트(FNP) {#frequently-needed-prompts}

#### 예상치 못한 프로젝트 생성 {#unexpected-project-generation}

프로젝트 생성 결과가 예상과 다릅니다. `/path/to/project`에 있는 내 프로젝트를 대상으로 Tuist CLI를 실행하여 이 현상이 발생하는 이유를 파악하세요. 제너레이터 파이프라인을 추적하고 출력을 담당하는 코드 경로를 찾아보세요.

#### 생성된 프로젝트에서 재현 가능한 버그 {#reproducible-bug-in-generated-projects}

생성된 프로젝트에서 버그로 보입니다. 기존 예제를 참고하여 `examples/` 아래에 재현 가능한 프로젝트를 만드세요. 실패하는 인수 테스트를 추가하고, 해당 테스트만 선택한 상태로 `xcodebuild`를 통해 실행한 후, 문제를 수정하고 테스트를 다시 실행하여 통과하는지 확인한 다음 PR을 열어주세요.
