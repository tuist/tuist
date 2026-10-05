---
{
  "title": "Cache",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Optimize build times with Tuist Cache, including module cache, Xcode cache, Gradle cache, and Bazel cache."
}
---
# 캐시 {#cache}

빌드 아티팩트는 환경 간에 공유되지 않아 동일한 코드를 반복해서 다시 빌드해야 합니다. Tuist의 캐싱 기능은 아티팩트를 원격으로 공유하여, 이미 빌드된 내용을 다시 빌드하지 않고도 팀과 CI에서 더 빠른 빌드를 가능하게 합니다.

프로젝트 또는 배포 모델에 맞는 캐시 워크플로우를 알아보세요:

\<.home\_cards\>
\<.home\_card
title="모듈 캐시"
details="Tuist의 생성된 프로젝트를 사용하는 프로젝트에서 개별 모듈을 바이너리로 캐시합니다. Tuist 프로젝트 생성이 필요합니다."
link="/guides/features/cache/module-cache"
/\>
\<.home\_card
title="Xcode 캐시"
details="환경 간에 Xcode 컴파일 아티팩트를 공유합니다. 모든 Xcode 프로젝트에서 작동하며, 프로젝트 생성이 필요하지 않습니다."
link="/guides/features/cache/xcode-cache"
/\>
\<.home\_card
title="Gradle 캐시"
details="Gradle 빌드 캐시 아티팩트를 원격으로 공유합니다. 성능 가시성을 위한 빌드 인사이트를 포함합니다."
link="/guides/features/cache/gradle-cache"
/\>
\<.home\_card
title="Bazel 캐시"
details="Bazel을 Tuist의 Remote Execution API 캐시에 연결하여 팀과 CI 간에 액션 출력을 공유합니다."
link="/guides/features/cache/bazel-cache"
/\>
\<.home\_card
title="셀프 호스팅"
details="CI, 사무실 또는 지역 컴퓨팅 환경 근처에 캐시 노드를 실행하고 이를 호스팅되거나 셀프 호스팅된 Tuist에 연결합니다."
link="/guides/features/cache/self-hosting"
/\>
\</.home\_cards\>

> \[\!TIP\]
> **Tuist Runners에서 가장 빠르게**
> 
> \<.localized\_link href="/guides/features/runners"\>Tuist Runners\</.localized\_link\>에서는 캐시가 러너의 프라이빗 네트워크에 공동 배치되며 개발자 머신이 사용하는 것과 동일한 캐시를 공유하므로, CI 작업은 별도의 CI 캐시를 예열할 필요 없이 즉시 웜 히트를 얻을 수 있습니다.

## CI로 업로드 제한 {#restrict-uploads-to-ci}

계정 관리자는 개발자에게 읽기 전용 권한을 부여하면서 CI가 캐시 아티팩트를 업로드할 수 있도록 허용할 수 있습니다. Tuist에서 계정의 **캐시** 설정을 열고 **캐시 업로드 액세스**를 **CI 및 계정 토큰만**으로 설정하세요. 이후에는 로그인 세션으로 인증된 멤버가 여전히 캐시에서 다운로드할 수 있지만, 업로드하려면 CI OIDC 인증 또는 `project:cache:write`나 `ci`와 같은 캐시 쓰기 스코프를 가진 계정 토큰이 필요합니다.

CI가 신뢰할 수 있는 캐시 생산자이고 로컬 머신은 캐시를 소비만 해야 할 때 이 설정을 사용하세요. 이 설정은 캐시 업로드 승인에만 영향을 미칩니다.