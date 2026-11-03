---
{
  "title": "CLI",
  "titleTemplate": ":title · Tuist",
  "description": "Tuist CLI, 명령어 및 워크플로우에 맞는 구성 방법입니다."
}
---
# CLI {#cli}

Tuist CLI는 Tuist와 상호작용하는 인터페이스 중 하나이며, <.localized_link href="/guides/features/projects">생성된 프로젝트</.localized_link>를 사용하는 경우 가장 일반적으로 사용됩니다. 프로젝트 생성, 바이너리 캐싱, 테스트 실행, 미리보기 공유 등을 위한 명령어를 제공합니다.

## 시작하기 {#getting-started}

Tuist를 아직 설치하지 않았다면, <.localized_link href="/guides/install-tuist">설치 가이드</.localized_link>를 따라 시작하세요.

설치가 완료되면 터미널에서 `tuist`을 실행하여 사용 가능한 명령어 목록을 확인할 수 있습니다:

```bash
tuist --help
```

## 설정 {#configuration}

CLI 동작은 `tuist.toml` 파일을 통해 구성할 수 있습니다. 사용 가능한 모든 옵션은 <.localized_link href="/references/tuist-toml">tuist.toml 참조</.localized_link>를 확인하세요.

## 문제 해결 {#troubleshooting}

문제가 발생하면 세션 로그 및 네트워크 기록을 포함한 문제 진단 도구는 <.localized_link href="/cli/debugging">디버깅 가이드</.localized_link>에서 확인하세요.
