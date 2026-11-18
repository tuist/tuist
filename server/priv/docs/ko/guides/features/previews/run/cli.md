---
{
  "title": "CLI로 미리보기 실행하기",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "Tuist CLI로 모바일 앱, macOS 애플리케이션 및 명령줄 미리보기를 실행하세요."
}
---
# CLI로 미리보기 실행하기

<.localized_link href="/guides/install-tuist">Tuist CLI</.localized_link>를 설치한 후 공유된 미리보기 링크를 실행하세요. 미리보기를 생성한 빌드 시스템이 필요하지 않습니다.

```bash
tuist run {url}
```

Tuist는 운영체제, CPU 아키텍처 및 대상에 맞는 호환되는 빌드를 선택합니다. 비공개 미리보기는 인증과 프로젝트 접근 권한이 필요합니다.

## 모바일 애플리케이션 {#mobile-applications}

연결된 장치 또는 시뮬레이터를 선택하세요:

```bash
tuist run --device "My device" {url}
```

Android 기기와 에뮬레이터는 ADB를 통해 연결되어야 합니다. 또한 미리보기 페이지에서 APK를 다운로드하여 해당 소스에서의 설치를 허용하는 Android 기기에 설치할 수 있습니다. Apple 빌드는 대상 플랫폼과 일치해야 하며 서명 요구 사항을 충족해야 합니다. IPA의 경우 대상 기기에서 미리보기 링크를 열어 설치하세요.

## 명령줄 미리보기 {#command-line-previews}

`--` 뒤에 인수를 전달하세요:

```bash
tuist run {url} -- --help
tuist run {url} -- build --configuration Release
```

`--` 뒤의 모든 내용은 `--verbose`, `--quiet` 및 `--path`를 포함하여 그대로 전달됩니다. 하위 인수는 Tuist 명령 분석에서 제외됩니다.

미리보기는 작업 디렉터리, 환경 및 터미널 입출력과 함께 실행되며 실행 파일의 종료 상태를 반환합니다. 이는 설치된 CLI를 대체하거나 `PATH`에 추가하지 않습니다. CLI 배포물은 실행 후 Tuist의 로컬 `previews` 캐시에 남아 있어 생성된 프로젝트가 계속 참조할 수 있으며, 해당 캐시를 삭제하면 이러한 참조의 대상도 제거됩니다.

데스크톱 및 CLI 미리보기는 샌드박스가 아닌 현재 사용자로 실행됩니다. 신뢰할 수 있는 작성자와 풀 리퀘스트의 빌드만 실행하세요.

## 버전 선택 {#select-a-version}

`tuist run`는 또한 `latest`가 포함된 앱 이름, 브랜치 이름 또는 커밋 해시를 허용합니다:

```bash
tuist run App@latest # Latest App preview associated with the project's default branch
tuist run App@my-feature-branch # Latest App preview associated with a branch
tuist run App@00dde7f56b1b8795a26b8085a781fb3715e834be # Preview associated with a commit
```

이러한 선택기는 해당하는 Git 메타데이터가 게시되어 있어야 합니다. Git 메타데이터를 생략하는 워크플로의 경우 대신 특정 미리보기 URL을 사용하세요.

접근 및 조직 관리는 <.localized_link href="/guides/features/previews#visibility">가시성 및 트랙</.localized_link>을 참조하세요.
