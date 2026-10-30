---
{
  "title": "Xcode 프로젝트",
  "titleTemplate": ":title · Swift · 패키지 레지스트리 · 기능 · 가이드 · Tuist",
  "description": "Xcode 프로젝트에서 Tuist Registry를 사용하는 방법을 알아보세요."
}
---
# Xcode 프로젝트 {#xcode-project}

Xcode 프로젝트에서 레지스트리를 사용해 패키지를 추가하려면 기본 Xcode UI를 사용하세요. Xcode의 `Package Dependencies` 탭에서 `+` 버튼을 클릭해 레지스트리에서 패키지를 검색할 수 있습니다. 패키지가 레지스트리에 있으면 오른쪽 상단에 `tuist.dev` 레지스트리가 표시됩니다.

![패키지 종속성 추가](/images/guides/features/build/registry/registry-add-package.png)

## 소스 제어 패키지 해결 {#resolving-source-control-packages}

추가한 패키지의 전달적 종속성과 같이 소스 제어 URL로 선언된 패키지는 기본적으로 소스 제어에서 해결됩니다. `tuist registry setup`는 다음 사용자 기본값을 기록해 Xcode가 대신 레지스트리에서 이를 해결하도록 구성합니다.

```bash
defaults write com.apple.dt.Xcode IDEPackageDependencySCMToRegistryTransformation useRegistryIdentityAndSources
```

이후 Xcode는 레지스트리에 해당하는 항목이 있을 때 소스 제어 패키지를 레지스트리에서 해결하고, 없는 경우 소스 제어로 대체합니다.

> [!NOTE]
> 이는 기기별 Xcode 환경설정이며 프로젝트 설정이 아니므로, 레지스트리 구성 파일을 커밋해도 팀원들과 공유되지 않습니다. 각 개발자는 자신의 기기에서 `tuist registry setup`를 한 번 실행해야 합니다. 이 환경설정은 해당 기기의 모든 Xcode 프로젝트에 적용됩니다.
