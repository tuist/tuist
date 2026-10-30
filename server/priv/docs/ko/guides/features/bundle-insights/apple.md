---
{
  "title": "Apple",
  "titleTemplate": ":title · 번들 인사이트 · 기능 · 가이드 · Tuist",
  "description": "Tuist Bundle Insights로 iOS, iPadOS, macOS, watchOS, tvOS 번들(.ipa, .xcarchive, .app)을 분석하세요."
}
---
# Apple {#bundle-insights-apple}

아카이브, 설치 가능 파일 또는 빌드된 앱을 대상으로 `tuist inspect bundle`를 실행하여 Apple 번들을 분석하세요:

::: code-group
```bash [Analyze an .ipa]
tuist inspect bundle App.ipa
```
```bash [Analyze an .xcarchive]
tuist inspect bundle App.xcarchive
```
```bash [Analyze an app bundle]
tuist inspect bundle App.app
```
```bash [Analyze by app name]
tuist inspect bundle App --platforms ios --configuration Debug
```
<!-- -->
:::

macOS에서 경로 대신 앱 이름을 전달하면, Tuist는 Xcode의 빌드 산출물에서 빌드된 `.app`를 해결합니다(`--derived-data-path`가 설정된 경우 이를 준수함). 이는 `tuist share`와 동일한 방식입니다.

이 명령은 번들을 Tuist에 업로드하고 콘텐츠 스캔 및 모듈 세부 정보를 포함한 상세 개요 링크를 반환합니다:

![분석된 번들](/images/guides/features/bundle-size/analyzed-bundle.png)

## App Store Connect와 비교하기 {#app-store-connect}

Tuist는 번들을 제공된 그대로 정확히 측정하며 [앱 슬라이밍](https://developer.apple.com/documentation/xcode/reducing-your-app-s-size)을 적용하지 않습니다. 보고되는 크기는 기기별 변형이 아닌 **유니버설**(슬라이밍되지 않은) 변형, 즉 App Store Connect의 앱 파일 크기 보고서에서 "Universal"로 표시된 행에 해당합니다.

수치가 Universal 행과 유사한 범위 내에 있지만 완전히 동일하지는 않을 것으로 예상하세요:

- **설치 크기**는 Universal 설치 크기와 비슷합니다. App Store Connect는 파일 시스템 블록 할당 및 Apple 자체 추정치 등 원시 파일 크기 측정으로는 포착되지 않는 온디바이스 오버헤드를 포함하므로 약간 더 높은 값을 보고합니다.
- **다운로드 크기**는 Universal 다운로드 크기보다 작습니다. Apple은 업로드 후 앱 바이너리를 암호화하며, 암호화된 데이터는 압축 효율이 낮기 때문에 App Store의 압축 다운로드 크기가 Tuist가 측정한 `.ipa` 아카이브보다 크게 나타납니다. 이는 업로드 후 Apple 측에서 발생하므로 Tuist의 수치에는 반영되지 않습니다.

App Store Connect의 기기별 행은 앱 슬리밍이 특정 기기에 필요 없는 CPU 아키텍처와 에셋 변형을 제거하므로 더 작습니다. Tuist는 현재 기기별(슬림된) 크기를 보고하지 않습니다.

<!-- @snippet: ./_shared -->
