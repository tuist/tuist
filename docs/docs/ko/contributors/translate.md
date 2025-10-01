---
{
  "title": "Translate",
  "titleTemplate": ":title · Contributors · Tuist",
  "description": "This document describes the principles that guide the development of Tuist."
}
---
# 번역 {#번역}

언어는 이해의 장벽이 될 수 있습니다. 우리는 가능한 한 많은 사람들이 Tuist를 이용할 수 있도록 하고 싶습니다. 튜이스트가 지원하지 않는
언어를 사용한다면 튜이스트의 다양한 표면을 번역하여 튜이스트를 도울 수 있습니다.

번역을 유지하는 것은 지속적인 노력이 필요하므로 번역 유지에 도움을 주겠다는 기여자가 있을 때마다 언어를 추가하고 있습니다. 현재 지원되는
언어는 다음과 같습니다:

- 영어
- 한국어
- 일본어
- 러시아어
- 중국어
- 스페인어
- 포르투갈어

> [!팁] 새로운 언어 요청하기 Tuist가 새로운 언어를 지원하면 도움이 될 것이라고 생각되면 커뮤니티 포럼에 새
> [주제](https://community.tuist.io/c/general/4)를 만들어 커뮤니티와 논의해 주세요.

## 번역 방법 {#번역 방법}

번역하다](https://weblate.org/en-gb/)의 인스턴스가
[translate.tuist.dev](https://translate.tuist.dev)에서 실행되고 있습니다.
프로젝트](https://translate.tuist.dev/engage/tuist/)로 이동하여 계정을 만들고 번역을 시작할 수 있습니다.

번역은 관리자가 검토하고 병합하는 GitHub 풀 리퀘스트를 사용하여 소스 리포지토리로 다시 동기화됩니다.

> [중요] 대상 언어의 리소스를 수정하지 마세요 웹레이트는 소스 언어와 대상 언어를 바인딩하기 위해 파일을 세그먼트화합니다. 소스 언어를
> 수정하면 바인딩이 깨지고 재조정 시 예기치 않은 결과가 발생할 수 있습니다.

## 가이드라인 {#guidelines}

다음은 번역할 때 따르는 가이드라인입니다.

### 사용자 지정 컨테이너 및 GitHub 알림 {#custom-containers-and-github-alerts}

사용자 지정 컨테이너](https://vitepress.dev/guide/markdown#custom-containers) 또는 [GitHub
알림](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax#alerts)을
번역할 때는 제목과 내용 **만 번역하고, 알림 유형** 은 번역하지 마세요.

::: 세부 정보 GitHub 알림 사용 예시
```markdown
    > [!WARNING] 루트 변수
    > 매니페스트의 루트에 있어야 하는 변수는...

    // Instead of
    > [!주의] 루트 변수
    > 매니페스트의 루트에 있어야 하는 변수는...
    ```
:::


::: details Example with custom container
```
    ::: warning 루트 변수\
    매니페스트의 루트에 있어야 하는 변수는...
    :::

    # Instead of
    ::: 주의 루트 변수\
    매니페스트의 루트에 있어야 하는 변수는...
    :::
```
:::

### Heading titles {#heading-titles}

When translating headings, only translate tht title but not the id. For example, when translating the following heading:

```
# 종속성 추가 {#add-dependencies}
```

It should be translated as (note the id is not translated):

```
# 의존성 추가하기 {#add-dependencies}
```

```
