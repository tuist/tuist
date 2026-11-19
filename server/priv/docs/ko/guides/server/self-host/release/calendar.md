---
{
  "title": "릴리스 캘린더",
  "titleTemplate": ":title | 셀프 호스팅 | 서버 | 가이드 | Tuist",
  "description": "Tuist 서버 및 Kura의 최신 버전, 최근 릴리스 이력, 그리고 예정된 안정화 릴리스 기간입니다."
}
---

# 릴리스 캘린더 {#release-calendar}

현재 서버 및 Kura 버전, 최근 릴리스, 예정된 릴리스 창을 확인하세요. 채널 보장, 이미지 고정 및 백포트 정책은 <.localized_link href="/guides/server/self-host/release/channels">릴리스 채널</.localized_link>을 참조하세요.

안정 버전 승격은 <.localized_link href="/cli/release/calendar">CLI 릴리스 트레인</.localized_link>과 함께 매주 월요일 06:00 UTC에 예약되어 있습니다. 다음 릴리스 후보는 예약된 승격이 성공한 후에만 생성됩니다. 실패 시 각 구성 요소가 독립적으로 지연될 수 있으며, 관리자는 예약 외부에 게시할 수 있습니다. 향후 일정은 계획일 뿐 약속된 게시 시간이 아닙니다.

패치 릴리스와 백포트는 주간 일정이 아닌 요청 시 제공됩니다. 아래 기록에서는 게시된 릴리스를 해당 노트 및 실제 게시 날짜와 연결합니다.

<.release_status status={@release_status} components="server,kura" />
