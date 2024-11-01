---
title: Best practices
titleTemplate: :title · Projects · Develop · Guides · Tuist
description: Tuist와 Xcode 프로젝트를 다룰 때의 모범 사례들을 알아보세요.
---

# Best practices {#best-practices}

다양한 팀 및 프로젝트와의 수년간 협업 경험을 바탕으로, Tuist와 Xcode 프로젝트를 다룰 때 권장하는 모범 사례들을 정리했습니다. 이러한 모범 사례들은 필수 사항은 아니지만, 프로젝트를 보다 유지보수하기 쉽고 확장 가능한 방식으로 구조화하는데 도움이 될 수 있습니다.

## Xcode {#xcode}

### 권장하지 않는 패턴 {#discouraged-patterns}

#### 원격 환경을 모델링하기 위한 설정 {#configurations-to-model-remote-environments}

많은 조직이 다양한 원격 환경을 모델링하기 위해 빌드 설정을 사용합니다 (예: `Debug-Production` or `Release-Canary`). 하지만 이 접근 방식에는 몇 가지 단점이 있습니다:

- **불일치:** 그래프 전반에 걸쳐 설정이 일관되지 않으면, 빌드 시스템이 일부 타겟에 대해 잘못된 설정을 사용할 수 있습니다.
- **복잡성:** 프로젝트의 로컬 설정과 원격 환경 설정들이 많아질수록 이해하고 관리하기 어려워질 수 있습니다.

Build configurations were designed to embody different build settings, and projects rarely need more than just `Debug` and `Release`. The need to model different environments can be achieved by using schemes:

- Set a scheme environment variable: `REMOTE_ENV=production`.
- Add a new key to the `Info.plist` of the bundle that will use the environment information (e.g., app bundle): `REMOTE_ENV=${REMOTE_ENV}`.
- You can then read the value at runtime:

  ```swift
  let remoteEnvString = Bundle.main.object(forInfoDictionaryKey: "REMOTE_ENV") as? String
  ```

Thanks to the above, you can keep the list of configurations simple, preventing the aforementioned downsides, and give developers the flexibility to customize things like the remote environment via schemes.
