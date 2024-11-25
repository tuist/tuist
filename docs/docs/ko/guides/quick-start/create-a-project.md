---
title: Create a project
titleTemplate: :title · Quick-start · Guides · Tuist
description: Tuist에서 첫 프로젝트를 만들어 보세요.
---

# Create a project {#create-a-project}

Tuist를 설치한 후에는 다음 명령을 실행하여 새 프로젝트를 만들 수 있습니다.

```bash
mkdir MyApp
cd MyApp
tuist init --name MyApp
```

이것은 기본적으로 **iOS 애플리케이션** 프로젝트를 생성합니다. 프로젝트 디렉토리는 프로젝트를 나타내는 `Project.swift`, 프로젝트 범위의 Tuist 구성을 나타내는 `Tuist.swift`, 그리고 애플리케이션의 소스 코드를 포함하는 `MyApp/` 디렉토리를 포함합니다.

Xcode에서 작업하려면, Xcode 프로젝트를 실행하여 생성할 수 있습니다.

```bash
tuist generate
```

직접 열고 편집할 수 있는 Xcode 프로젝트와 달리, Tuist 프로젝트는 manifest 파일에서 생성됩니다. 즉, 생성된 Xcode 프로젝트를 직접 편집해서는 안 됩니다.

> [!TIP] Conflicts가 없고 사용자 친화적인 환경  Xcode 프로젝트는 Conflicts가 발생하기 쉽고 개발자가 다루기에 매우 복잡합니다. Tuist는 특히 프로젝트의 종속성 그래프 관리 영역에서 이를 추상화 합니다.

## Build the app {#build-the-app}

Tuist는 프로젝트에서 수행해야 하는 가장 기본적인 작업에 대한 명령어를 제공합니다. 앱을 빌드 하려면, 다음 명령어를 실행합니다.

```bash
tuist build
```

이 명령어는 내부적으로 플랫폼의 빌드 시스템(예: `xcodebuild`)을 사용하며, Tuist의 기능을 더해 빌드 시스템을 더욱 강력하게 만듭니다.

## Test the app {#test-the-app}

마찬가지로 다음을 사용하여 테스트를 실행할 수 있습니다.

```bash
tuist test
```

`build` 명령과 마찬가지로 `test` 명령도 플랫폼의 테스트 러너(예: `xcodebuild test`)를 사용하지만, Tuist의 테스트 기능과 최적화의 이점을 추가로 제공합니다.

> [!TIP] 기본 빌드 시스템에 인수 전달하기 `build`와 `test` 모두 `--` 뒤에 추가 인수를 받아 기본 빌드 시스템으로 전달할 수 있습니다.
