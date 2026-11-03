---
locale: ko
glossary:
  tests: 테스트
  features: 기능
  cache hit: 캐시 히트
  cache miss: 캐시 미스
  flaky tests: 불안정한 테스트
  test run: 테스트 실행
  test case: 테스트 케이스
  selective testing: 선택적 테스팅
---

# 한국어 번역 규칙

## 모든 페이지 대상 규칙
- "You"는 "귀하"나 "당신"대신 "여러분"으로 번역
- "Tuist"나, "tuist"를 "튜이스트"가 아닌 영문 그대로 번역
- 제거 가능한 주어는 번역시 제거해서 문장을 간결하게 번역: 예) 'our dashboard"를 "우리 대시보드" 대신 "대시보드"로 번역
- 페이지 내의 한 문장이 두개 이상의 단어 소스로 이루어져 있는 경우 완성된 문장이 어색하지 않고 자연 스럽게 부분 번역
ex) "Powered by" "open source"를 "기반 기술 오픈 소스" 대신, "만들어졌습니다 오픈소스로"와 같이 번역 

## 마케팅(Marketing) 페이지 전용 규칙
- "in one platform"는 "하나의 플랫폼으로"로 번역
- "Explore features, "live on our dashboard"에서 "Explore features"는 "기능을 탐색하세요"로, "live on our dashboard"는 "대시보드에서 실시간으로"로 번역

## Voice and Typography

- Retain the Korean rules above. Prefer omitted subjects to repeated "여러분"; do not reintroduce "당신" or "귀하" from the English source.
- Use concise noun phrases or natural action phrases in headings and labels, without a final period. In body copy, use consistent polite endings such as "합니다" and "하세요" with normal sentence punctuation. Do not alternate arbitrarily between clipped labels and full sentences within the same group.
- Use Korean punctuation and spacing. Do not leave an English dash between two clauses when a natural Korean sentence is clearer.

## Developer Vocabulary and Marketing

- Use established terms such as "빌드", "테스트", "캐시", "배포", and "실행". For dependency resolution, prefer "의존성 해결" rather than the ambiguous literal "패키지 해결".
- "Shipping" refers to releasing or delivering software, not "배송" or "출하". Avoid a literal "가상 동반자" pitch when the meaning can be expressed directly as support for the team's development workflow.
- For "Less waiting. More shipping.", a natural direction is "대기 시간은 줄이고, 개발에 더 집중하세요". For "More in the toolbox", prefer "팀을 위한 더 많은 도구" to a literal toolbox metaphor.
- Translate ordinary connective prose fully into Korean: constructions such as "AI 시대가到来하면서" and "모바일背后的 도구" are not protected technical terms. Use natural wording such as "AI가 등장하면서" and "모바일 개발을 뒷받침하는 도구".
- Keep quarantine metadata distinct: "Quarantined by" identifies who acted, while "Quarantined at" identifies when. Preserve the actor or timestamp in compact labels rather than reducing both to "격리됨".
