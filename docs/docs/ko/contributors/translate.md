---
{
  "title": "Translate",
  "titleTemplate": ":title · Contributors · Tuist",
  "description": "이 문서는 Tuist의 개발을 위한 원칙을 설명합니다."
}
---
# Translate {#translate}

언어는 이해의 장벽이 될 수 있습니다. 우리는 Tuist가 가능한 많은 사람들에게 접근 가능하도록 하려고 합니다. Tuist에서 지원하지 않는 언어를 사용한다면, Tuist를 번역하여 우리를 도울 수 있습니다.

번역을 유지하는 것은 지속적인 노력이 필요하므로, 번역을 도와 줄 기여자가 있다면 해당 언어를 추가합니다. 현재 지원하고 있는 언어는 다음과 같습니다:

- 영어
- 한국어
- 일본어
- 러시아어

> [!TIP] 새로운 언어 요청\
> Tuist에 새로운 언어를 지원해야 된다면, 커뮤니티에 의논할 수 있도록 [커뮤니티 포럼에 주제](https://community.tuist.io/c/general/4)를 새로 생성해 주세요.

## 번역 방법

우리는 번역을 관리하기 위해 [Crowdin](https://crowdin.com/)을 사용합니다. 먼저, 기여하고 싶은 프로젝트로 이동합니다:

- [Documentation](https://crowdin.com/project/tuist-documentation)
- [Website](https://crowdin.com/project/tuist-documentation)

번역을 시작하려면 계정이 필요합니다. GitHub으로 로그인 할 수 있습니다. 접근 권한이 생기면 번역을 시작할 수 있습니다. 번역 가능한 리소스 목록을 확인할 수 있습니다. 리소스를 클릭하면 편집창이 열리고, 기존 언어는 왼편에 번역한 언어는 오른편에 나타나는 화면을 볼 수 있습니다. 오른편에 번역 내용을 작성하고 변경 사항을 저장합니다.

번역이 업데이트 되면 Crowdin은 자동으로 리포지토리에 저장하여 Pull Request를 열고, 메인테이너는 해당 내용을 검토하여 병합합니다.

> [!IMPORTANT] 번역 언어의 리소스를 수정하지 마세요
> Crowdin은 기존 언어와 번역 언어를 결합 하기 위해 파일을 분할합니다. 기존 언어를 수정하면 바인딩이 끊어지고 예상치 못한 결과를 가져올 수 있습니다.

## 가이드라인

번역할 때 따라야 하는 가이드라인은 다음과 같습니다.

### 커스텀 컨테이너와 GitHub alert

[커스텀 컨테이너 (Custom Container)](https://vitepress.dev/guide/markdown#custom-containers) 또는 [GitHub Alerts](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax#alerts)을 번역할 때는 **경고 타입은 번역하지 않고** 제목과 내용만 번역합니다.

:::details GitHub Alert 예제

````markdown
    > [!WARNING] 루트 변수
    > 매니페스트의 루트에 있어야 하는 변수는...

    // Instead of
    > [!주의] 루트 변수
    > 매니페스트의 루트에 있어야 하는 변수는...
    ```
:::


::: details Example with custom container
```markdown
    ::: warning 루트 변수\
    매니페스트의 루트에 있어야 하는 변수는...
    :::

    # Instead of
    ::: 주의 루트 변수\
    매니페스트의 루트에 있어야 하는 변수는...
    :::
````

:::

### 제목

제목을 번역할 때, ID는 번역하지 않고 제목만 번역합니다. 예를 들어, 다음의 제목을 번역할 때:

```markdown
# Add dependencies {#add-dependencies}
```

이것은 다음과 같이 번역합니다 (ID는 번역하지 않습니다):

```markdown
# 의존성 추가하기 {#add-dependencies}
```
