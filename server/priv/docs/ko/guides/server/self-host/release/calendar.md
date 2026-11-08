---
{
  "title": "릴리스 캘린더",
  "titleTemplate": ":title | 자체 호스팅 | 서버 | 가이드 | Tuist",
  "description": "Tuist 서버와 Kura의 최신 버전, 최근 릴리스 이력, 그리고 예정된 안정화 릴리스 일정을 확인하세요."
}
---

# 릴리스 캘린더 {#release-calendar}

현재 서버 및 Kura 버전, 최근 릴리스, 예정된 릴리스 일정을 확인하세요. 채널 보장, 이미지 고정 및 백포트 정책은 <.localized_link href="/guides/server/self-host/release/channels">릴리스 채널</.localized_link>을 참조하세요.

안정 버전 승격은 <.localized_link href="/cli/release/calendar">CLI 릴리스 일정</.localized_link>과 함께 매주 월요일 06:00 UTC에 진행됩니다. 다음 릴리스 후보는 예정된 승격이 성공한 후에만 생성됩니다. 실패 시 각 구성 요소가 독립적으로 지연될 수 있으며, 관리자는 정해진 일정 외에도 게시할 수 있습니다. 향후 일정은 확정된 게시 시간이 아닌 계획입니다.

패치 릴리스와 백포트는 주간 일정이 아닌 필요에 따라 제공됩니다. 아래 기록에는 게시된 릴리스의 노트와 실제 게시 날짜로 연결되는 링크가 포함되어 있습니다.

<.release_status status={@release_status} components="server,kura" />
