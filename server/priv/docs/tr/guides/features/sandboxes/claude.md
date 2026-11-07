---
{
  "title": "Claude",
  "titleTemplate": ":title · Sandboxes · Özellikler · Kılavuzlar · Tuist",
  "description": "Claude Managed Agents oturumlarını ve Claude Code bulut oturumlarını (claude.ai, masaüstü ve mobil uygulamalar ve claude --cloud) Linux veya macOS üzerinde Tuist Sandboxes'da çalıştırın."
}
---
# Claude {#claude}

> [!IMPORTANT]
> **Yalnızca davetle**
>
> Tuist Sandbox'ları, hem Linux hem de macOS için şu anda yalnızca davetle erişilebilir. Hesabınız için erişim talep etmek üzere [bize ulaşın](mailto:contact@tuist.dev) veya [topluluk Slack](https://slack.tuist.dev) kanalında bize mesaj atın.

Anthropic, Claude'un ajan döngüsünü çalıştırır ve bir *kendi barındırdığınız ortam* Claude'un araçlarının nerede çalışacağına karar verir. Birini Tuist'e bağlayın; içindeki her oturum, Linux veya macOS üzerinde kendi Tuist <.localized_link href="/guides/features/sandboxes">sandbox</.localized_link>'ına sahip olur. Tuist, bu ortamların ihtiyaç duyduğu işçileri ve çalıştırıcıları çalıştırır, böylece hiçbir şeyi kendiniz barındırmazsınız.

İki tür ortam vardır, her biri bir Claude ürünü içindir:

- **[Claude Yönetilen Ajanlar](#managed-agents)**: Claude API veya Tuist'in ajan-oturumları API'si ile başlattığınız oturumlar. Ortamı (`env_…`) [Claude Konsolu](https://platform.claude.com/environments)'nda oluşturursunuz ve her oturum Linux veya macOS'u seçebilir.
- **[Claude Code](#claude-code)**: Geliştiricilerin claude.ai'den, Claude masaüstü ve mobil uygulamalarından ve `claude --cloud`'den başlattığı bulut oturumları. Bir Claude Team veya Enterprise sahibi, claude.ai yönetici ayarlarında her platform için bir tane olmak üzere ortamları (`ccpool_…`) oluşturur ve geliştiriciler ortamı seçerek Linux veya macOS'u belirler.

Her ikisi de bir hesap yöneticisi tarafından Tuist API aracılığıyla bağlanır. `tuist auth login` ile kimlik doğrulaması yapın, ardından:

```bash
export TUIST_TOKEN=$(tuist auth token)
```

## Claude Yönetilen Ajanlar {#managed-agents}

### Bir ortamı bağlama {#managed-agents-connect}

1. [Claude Konsolu](https://platform.claude.com/environments)'nda **Ortam oluştur** öğesine tıklayın ve **Barındırma** altında **Kendi barındırdığınız** seçeneğini belirleyin. Ortamı açın, **Ortam anahtarı oluştur** öğesine tıklayın ve ortamın `env_…` kimliğini ile anahtarını kopyalayın. Ayrıntılar için Anthropic'in [kendi barındırdığınız sandbox'lar](https://platform.claude.com/docs/en/managed-agents/self-hosted-sandboxes) kılavuzuna bakın.
2. Onu Tuist hesabınıza bağlayın:

   ```bash
   curl -X POST "https://tuist.dev/api/accounts/my-org/sandboxes/agent-environments" \
     -H "Authorization: Bearer $TUIST_TOKEN" -H "Content-Type: application/json" \
     -d '{
       "anthropic_environment_id": "env_...",
       "environment_key": "<environment key>",
       "anthropic_api_key": "<Anthropic API key>"
     }'
   ```

   `anthropic_api_key` isteğe bağlıdır. Aşağıda açıklandığı gibi Tuist'in API'si aracılığıyla oturum başlatmanıza olanak tanır. Tuist, her iki anahtarı da şifreli olarak saklar ve asla geri döndürmez.

Bir dakika içinde Tuist, ortamın oturumlarını sunmaya başlar. Ortam, siz `"platform": "darwin"` geçmediğiniz sürece Linux üzerinde çalışır. Sandbox'larının şeklini değiştirmek için `vcpus`, `memory_mb` ve `workspace_gb` değerlerini de geçebilirsiniz; bkz. <.localized_link href="/guides/features/sandboxes#platforms">Linux ve macOS</.localized_link>.

### Bir oturum başlatma {#managed-agents-sessions}

Her oturum, oturum başka bir platform istemediği sürece ortamın platformunda çalışır.

**Claude API ile**, oturumu ortamın kimliğiyle normal şekilde oluşturun ve oturumun meta verilerinde `tuist_platform` değerini `macos` veya `linux` olarak ayarlayın:

```bash
curl https://api.anthropic.com/v1/sessions \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "anthropic-beta: managed-agents-2026-04-01" \
  -H "content-type: application/json" \
  -d '{
    "agent": "agent_...",
    "environment_id": "env_...",
    "metadata": {
      "tuist_platform": "macos",
      "repository_url": "https://github.com/my-org/my-app"
    }
  }'
```

`repository_url` ve isteğe bağlı olarak `repository_ref` (bir dal veya commit), Tuist'in ajanın ilk dönüşünden önce genel bir depoyu sandbox'a klonlamasını sağlar.

**Tuist'in ajan-oturumları API'si ile**, Tuist sizin için ajanı ve oturumu oluşturur ve Tuist hesabınıza bağlı olan özel GitHub depolarını klonlar:

```bash
curl -X POST "https://tuist.dev/api/accounts/my-org/sandboxes/agent-sessions" \
  -H "Authorization: Bearer $TUIST_TOKEN" -H "Content-Type: application/json" \
  -d '{
    "prompt": "Fix the failing snapshot tests",
    "platform": "darwin",
    "repository_url": "https://github.com/my-org/my-app",
    "repository_ref": "main"
  }'
```

Hesapta birden fazla ortam olduğunda `agent_environment_id` değerini geçin. Oturumu `GET /agent-sessions/{id}/events` ile takip edebilir, `POST /agent-sessions/{id}/messages` ile yanıt verebilir ve `POST /agent-sessions/{id}/archive` ile sonlandırabilirsiniz.

Depo, Linux'ta `/workspace` ve macOS'ta `/Users/runner/work` dizinine checkout edilir. Bir oturumun sandbox'ı, ajan bir dönüşü tamamladıktan sonra duraklar ve sonraki mesajda devam eder.

> [!WARNING]
> Ortama sahip olan Claude çalışma alanında oturum oluşturabilen herkes, Tuist hesabınızda oturum çalıştırabilir ve oturum meta verileriyle macOS talep edebilir. Bu çalışma alanına erişimi buna göre sınırlayın.

## Claude Code {#claude-code}

Claude Code bulut oturumları, geliştiricilerin [claude.ai/code](https://claude.ai/code), Claude masaüstü ve mobil uygulamaları ve `claude --cloud`'den başlattıkları oturumlardır. Bir oturumun nerede çalışacağını ortamına göre seçerler, bu nedenle sunmak istediğiniz her platform için bir ortam bağlarsınız.

### Ortamları bağlama {#claude-code-connect}

1. Bir Claude kuruluşu sahibi, [Bulut ortamları](https://claude.ai/admin-settings/cloud-environments) yönetici sayfasında **Kendi barındırdığınız ortamlara izin ver** seçeneğini etkinleştirir. Bunun için Team veya Enterprise planı gerekir; Anthropic'in [kendi barındırdığınız ortamlar](https://code.claude.com/docs/en/self-hosted-environments) kılavuzuna bakın.
2. Aynı sayfada, geliştiricilerin göreceği adla her platform için bir kendi barındırdığınız ortam oluşturun, örneğin **Tuist Linux** ve **Tuist macOS**. Her ortamın `ccpool_…` kimliğini ve yalnızca bir kez gösterilen ortam anahtarını kopyalayın.
3. Her ortamı, `kind` değeri `claude_code` olarak ve platformuyla birlikte Tuist hesabınıza bağlayın:

   ```bash
   curl -X POST "https://tuist.dev/api/accounts/my-org/sandboxes/agent-environments" \
     -H "Authorization: Bearer $TUIST_TOKEN" -H "Content-Type: application/json" \
     -d '{
       "kind": "claude_code",
       "platform": "darwin",
       "name": "Tuist macOS",
       "anthropic_environment_id": "ccpool_...",
       "environment_key": "<environment key>"
     }'
   ```

   `"platform": "linux"` ve diğer ortamın kimliği ile anahtarıyla tekrarlayın.

Bir dakika içinde ortamlar oturum almaya hazır hale gelir. Boşta bir oturum, sandbox'ını 30 dakika boyunca çalışır durumda tutar, ardından duraklatır; oturumun sonraki mesajı aynı sandbox'ı devam ettirir. Bekleme süresini `max_idle_seconds` ile değiştirin (maksimum 3600).

### Linux veya macOS seçme {#claude-code-choose}

Geliştiriciler, bir bulut oturumu başlattıklarında ortamı ve buna bağlı olarak platformu seçerler:

- **claude.ai, masaüstü ve mobil uygulamalar:** yeni bir oturumun ortam seçicide **Tuist Linux** veya **Tuist macOS** seçeneğini belirleyin.
- **Claude Code CLI:** `claude` içinde `/remote-env` komutunu çalıştırın ve ortamı adına göre seçin. `claude --cloud "<task>"` daha sonra onun üzerinde çalışır. Tek bir oturum için birini seçmek üzere kimliğini geçin: `claude --cloud "<task>" --environment ccpool_...`.
- **Tüm bir ekip veya depo:** Claude Code [ayarları](https://code.claude.com/docs/en/settings)'nda varsayılan ortamın kimliğini ayarlayın, örneğin bir deponun `.claude/settings.json` dosyasında:

  ```json
  { "remote": { "defaultEnvironmentId": "ccpool_..." } }
  ```

Bu ortamlardaki oturumlar, kuruluşunuzun Claude Code kullanımını normal şekilde kullanır ve sandbox'ları Tuist hesabınıza yansır.
