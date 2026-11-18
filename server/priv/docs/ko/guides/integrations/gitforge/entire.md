---
{
  "title": "Entire",
  "titleTemplate": ":title | Git 포지 | 통합 | 가이드 | Tuist",
  "description": "Tuist 빌드, 테스트, 번들 및 미리보기 인사이트를 Entire Trails에 게시하세요."
}
---
# Entire 통합 {#entire}

Tuist는 연결된 각 리포지토리의 열려 있거나 초안 상태인 [Trail](https://docs.entire.com/guides/trails/overview)에 요약 토론을 유지합니다. 이 요약에는 사용 가능한 빌드 결과, 테스트 실패 및 불안정한 테스트, 번들 크기, 앱 미리보기가 포함되며, Tuist의 전체 보고서로 연결되는 링크가 제공됩니다.

> [!IMPORTANT]
> **얼리 액세스**
>
> Entire 플러그인은 파트너 등록이 필요하며, Trail 토론과 웹훅 계약은 실험적인 기능입니다. Tuist 관리자는 모든 계정 또는 선택한 계정에 대해 이 통합을 활성화할 수 있습니다. 또한 Entire 프로젝트에서 등록된 플러그인을 설치할 수 있도록 허용되어야 합니다.

## 설정 {#setup}

설치 과정은 GitHub 통합과 동일한 흐름을 따릅니다. 계정에 플러그인을 설치한 후, 리포지토리를 Tuist 프로젝트에 연결하세요. 호스팅된 Tuist 환경에서는 관리자가 플러그인 등록과 서버 구성을 처리하므로, 아래 단계만 수행하면 됩니다.

1. 계정의 **Settings → Integrations**을 엽니다.
2. **Entire**에서 **Install Entire plugin**을 선택하세요. Tuist와 공유하려는 Entire 프로젝트와 리포지토리를 선택합니다.

   ![계정 통합에서 Entire 플러그인 설치](/images/guides/integrations/gitforge/entire/integrations.png)

3. Tuist로 돌아가 **Add new project connection**을 선택하세요. **Choose repository to connect to**에서 Tuist 프로젝트와 Entire 리포지토리를 선택한 후, **Create Connection**을 선택합니다. 사용 가능한 Tuist 프로젝트가 하나뿐이라면 자동으로 선택됩니다.

   ![Tuist 프로젝트를 Entire 리포지토리에 연결](/images/guides/integrations/gitforge/entire/add-project-connection.png)

4. 기존 인증된 Tuist 명령어를 사용하여 CI에서 인사이트를 계속 업로드하세요. Tuist는 이를 각 Trail의 현재 커밋 SHA와 일치시킵니다. Entire 전용 CLI 플래그는 필요하지 않습니다.

Tuist 프로젝트는 GitHub 연결을 유지하면서도 Entire에 요약을 게시할 수 있습니다. 이는 GitHub 미러에 유용합니다. Trail 요약에는 Tuist의 CI 실행기가 필요하지 않으며 기존 CI 제공자를 변경하지도 않습니다.

Tuist는 인사이트가 도착함에 따라 동일한 토론을 업데이트합니다. Trail을 열거나 다시 열면 헤드 커밋에 대해 이전에 업로드된 인사이트도 가져옵니다. 종료되거나 병합된 Trail은 업데이트되지 않습니다. 이전 커밋의 결과는 현재 헤드의 결과로 표시되지 않습니다. 현재 커밋에 대한 인사이트가 없으면 Tuist는 기존 요약을 그대로 유지하며, 각 결과에는 해당 커밋 해시가 포함됩니다.

프로젝트 연결을 제거하려면 GitHub와 마찬가지로 **Manage** 메뉴를 열고 **Remove connection**을 선택하세요. 이렇게 하면 향후 업데이트가 중단되고 Tuist의 로컬 토론 포인터가 삭제됩니다. 이미 게시된 댓글은 Entire에 남아 있습니다. 여전히 접근 가능한 경우 다시 연결하면 기존 요소를 복구할 수 있습니다. 플러그인의 리포지토리 액세스 권한을 변경하거나 제거하려면 Entire의 프로젝트 **Plugins** 설정을 사용하세요.

## 서버 구성 {#server-configuration}

이 섹션은 Tuist 서버 운영자를 위한 것입니다. [플러그인 등록 가이드](https://docs.entire.com/guides/api/plugins/register)를 사용하여 Entire에 플러그인을 등록하세요. `contents:read` 및 `discussions:write` 권한을 요청하세요. 읽기 권한은 Trail 이벤트와 토론 검색에 필요하지만, 리포지토리 쓰기 액세스는 필요하지 않습니다.

다음 서버 환경 변수를 구성하세요:

| 변수 | 목적 |
| --- | --- |
| `TUIST_ENTIRE_PLUGIN_SLUG` | Entire에서 확인된 슬러그 |
| `TUIST_ENTIRE_PLUGIN_PRIVATE_KEY` | PEM 형식의 Ed25519 비공개 키, 시크릿 스토어를 통해 공급됨 |
| `TUIST_ENTIRE_PLUGIN_KEY_ID` | JWKS 기반 키 등록을 사용할 때의 키 ID; 그렇지 않으면 선택 사항 |
| `TUIST_ENTIRE_CORE_URL` | 설치 요청에 사용되는 Entire Core; 기본값은 `https://eu.auth.entire.io` |
| `TUIST_ENTIRE_DELIVERY_JWKS_URL` | 등록 시 Entire에서 제공하는 웹훅 서명 키 URL |

관리형 Helm 배포의 경우, 환경의 1Password 볼트에 비공개 PEM을 `ENTIRE_PLUGIN/private_key`으로 저장한 후, `server.config.managedSecrets`과 함께 `server.config.entirePluginKey.enabled`를 활성화하세요. External Secrets는 멀티라인 PEM을 자르지 않고 기존 server-config Secret을 통해 `TUIST_ENTIRE_PLUGIN_PRIVATE_KEY`를 제공합니다. 항목 및 필드 이름은 `server.config.entirePluginKey.item` 및 `.field`을 통해 구성할 수 있습니다. 이 매핑은 기본적으로 비활성화되어 있으며 슬러그나 웹훅 서명 키 URL을 구성하지 않으므로, 등록 후에 별도로 제공해야 합니다. 각 환경은 고유한 서명 키를 사용해야 합니다. Entire와는 공개 PEM만 공유하고 비공개 키는 절대 공유하지 마세요.

`https://<your-tuist-host>/integrations/entire/callback`를 설치 후 URL로, `https://<your-tuist-host>/webhooks/entire`를 웹훅 URL로 등록하세요. 서버 마이그레이션을 적용한 후, `entire_trails` 기능 플래그를 전역적으로 활성화하여 모든 계정에 통합 기능을 제공하거나, 선택한 계정에만 활성화하세요. 공개 출시를 위해서는 Entire 담당자에게 플러그인 소유 프로젝트 외부에서의 설치를 허용하도록 요청하세요. Tuist 기능 플래그를 활성화해도 Entire의 설치 정책은 변경되지 않습니다. Entire Trail 요약은 Tuist의 CI 실행 구성 및 기능 플래그와 독립적입니다.

Tuist는 설치 영수증과 웹훅 서명을 검증하고, 단기적인 리포지토리 범위 토큰을 발급하며, 게시 전에 각 리포지토리의 현재 처리 지역을 확인합니다. 토큰은 보고서 링크에 절대 포함되지 않습니다.
