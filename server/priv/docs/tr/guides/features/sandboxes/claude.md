---
{
  "title": "Claude",
  "titleTemplate": ":title · Sandboxes · Özellikler · Kılavuzlar · Tuist",
  "description": "Claude Managed Agents oturumlarını ve Claude Code bulut oturumlarını (claude.ai, masaüstü ve mobil uygulamalar ve claude --cloud) Linux veya macOS üzerinde Tuist Sandboxes'ta çalıştırın."
}
---
# Claude {#claude}

> [!IMPORTANT]
> **Davet usulü erişim**
>
> Tuist Sandbox’lar, hem Linux hem de macOS için şu anda davet usulü erişime açıktır. Hesabınız için erişim talep etmek üzere [bize ulaşın](mailto:contact@tuist.dev) veya [topluluk Slack](https://slack.tuist.dev) kanalında bize mesaj atın.

Anthropic, Claude’un agent döngüsünü çalıştırır ve *kendi sunucunuzda barındırdığınız bir ortam*, Claude’un araçlarının nerede çalışacağını belirler. Birini Tuist’e bağlayın; içindeki her oturum, Linux veya macOS üzerinde kendi Tuist <.localized_link href="/guides/features/sandboxes">sandbox</.localized_link>’ına sahip olur. Tuist, bu ortamların ihtiyaç duyduğu worker’ları ve runner’ları çalıştırır, böylece hiçbir şeyi kendiniz barındırmazsınız.

İki tür ortam vardır, her biri bir Claude ürünü içindir:

- **[Claude Managed Agents](#managed-agents)**: Claude API veya Tuist’in agent-sessions API’si ile başlattığınız oturumlar. Ortamı (`env_…`) [Claude Console](https://platform.claude.com/environments) içinde oluşturursunuz ve her oturum Linux veya macOS seçebilir.
- **[Claude Code](#claude-code)**: Geliştiricilerin claude.ai’dan, Claude masaüstü ve mobil uygulamalarından ve `claude --cloud` komutundan başlattığı bulut oturumları. Bir Claude Team veya Enterprise sahibi, claude.ai yönetici ayarlarında her platform için bir tane olmak üzere ortamları (`ccpool_…`) oluşturur ve geliştiriciler ortamı seçerek Linux veya macOS tercih eder.

Her ikisi de bir hesap yöneticisi tarafından Tuist API üzerinden bağlanır. `tuist auth login` ile kimlik doğrulaması yapın, ardından:

```bash
export TUIST_TOKEN=$(tuist auth token)
```

## Claude Managed Agents {#managed-agents}

### Bir ortam bağlama {#managed-agents-connect}

Hesabınızın **Ayarlar → Entegrasyonlar → Claude** bölümünden bağlanın. Form, kendi sunucunuzda barındırdığınız bir ortamı ve Tuist’in oturumlarını başlatırken kullandığı kimlik bilgilerini ister:

1. **Ortamı oluşturun.** Claude Console’da, [Environments](https://platform.claude.com/environments) sayfasında kendi sunucunuzda barındırdığınız bir ortam oluşturun, açın ve **Generate environment key** düğmesine tıklayın. Anthropic yalnızca Console’da ortam anahtarları oluşturur.
2. Formun üst kısmındaki seçiciyle **bir kimlik bilgisi seçin** (aşağıya bakın).
3. **Ortam kimliğini ve anahtarını yapıştırın** ve ortamın sandbox’larının platformunu ve yapılandırmasını seçin.

Tuist, herhangi bir şeyi kaydetmeden önce kimlik bilgisiyle ortamı getirir; bu nedenle yanlış bir kimlik bilgisi, kimlik veya çalışma alanı formda hata verir. Anahtarları şifreli olarak saklar ve bir daha göstermez. Bir dakika içinde Tuist, ortamın oturumlarını sunmaya başlar. Yapılandırmalar için <.localized_link href="/guides/features/sandboxes#platforms">Linux ve macOS</.localized_link> bölümüne bakın.

#### API anahtarıyla {#managed-agents-connect-api-key}

Varsayılan ve sandbox’ları denemenin en hızlı yolu. Ortamın çalışma alanında geliştirici rolüne sahip bir API anahtarı yapıştırın. Entegrasyon, API anahtarı kullanan ortamları işaretler; birine güvenmeden önce, Tuist’in uzun ömürlü bir anahtar tutmaması için bunun yerine federated identity ile bağlayın.

#### Federated identity ile {#managed-agents-connect-federated}

Tuist, Anthropic’in [Workload Identity Federation](https://platform.claude.com/docs/en/manage-claude/workload-identity-federation) özelliğiyle kimlik doğrulaması yapar, böylece ona asla bir Anthropic API anahtarı vermezsiniz. Anthropic kuruluşunuzda yönetici rolüne ihtiyacınız var.

1. **Tuist’e güvenin.** Form, hesabınızın issuer URL’sini ve subject prefix’ini gösterir. Claude Console’da [Workload identity](https://platform.claude.com/settings/workload-identity-federation) bölümünü açın, **Connect workload** düğmesine tıklayın, **Custom OIDC** seçeneğini belirleyin ve bunları `workspace:developer` scope’u ile girin. Sihirbazın oluşturduğu hizmet hesabını ortamın çalışma alanına ekleyin.
2. **ID’leri girin.** Kuruluş ID’si **Ayarlar → Organization** altında, çalışma alanı ID’si ise **Ayarlar → Workspaces** altındadır. Connect workload işlemi tamamlandığında hizmet hesabı ve federation rule ID’lerini gösterir ve Workload identity sayfasındaki rule sayfası bunları tekrar gösterir. Hiçbiri gizli değildir. Anthropic, Tuist’in token’ını reddederse Console’un [authentication history](https://platform.claude.com/settings/workload-identity-federation?tab=history) bölümü nedenini gösterir.

#### API ile {#managed-agents-connect-api}

Otomasyondan bağlanmak için [Claude Console](https://platform.claude.com/environments) içinde kendi sunucunuzda barındırdığınız bir ortam oluşturun, anahtarını üretin ve her ikisini Tuist’e gönderin:

```bash
curl -X POST "https://tuist.dev/api/accounts/my-org/sandboxes/agent-environments" \
  -H "Authorization: Bearer $TUIST_TOKEN" -H "Content-Type: application/json" \
  -d '{
    "anthropic_environment_id": "env_...",
    "environment_key": "<environment key>"
  }'
```

Tuist’in API’si aracılığıyla oturum başlatmak için ayrıca dört federation ID’sini (bkz. [API anahtarı olmadan bağlanma](#managed-agents-federation)) veya bir `anthropic_api_key` gönderin. Ortam, `"platform": "darwin"` parametresini iletmediğiniz sürece Linux üzerinde çalışır; `vcpus`, `memory_mb` ve `workspace_gb` parametreleri sandbox’ların yapılandırmasını değiştirir.

### Bir oturum başlatma {#managed-agents-sessions}

Her oturum, oturum başka bir platform istemediği sürece ortamın platformunda çalışır.

**Claude API ile**, oturumu normal şekilde ortamın ID’siyle oluşturun ve oturumun meta verilerinde `tuist_platform` değerini `macos` veya `linux` olarak ayarlayın:

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

`repository_url` ve isteğe bağlı olarak `repository_ref` (bir dal veya commit), Tuist’in agent’ın ilk adımından önce genel bir depoyu sandbox’a klonlamasını sağlar.

**Tuist’in agent-sessions API’si ile**, Tuist sizin için agent’ı ve oturumu oluşturur ve Tuist hesabınıza bağlı olan özel GitHub depolarını klonlar:

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

Hesapta birden fazla ortam varsa `agent_environment_id` parametresini iletin. Oturumu `GET /agent-sessions/{id}/events` ile takip edebilir, `POST /agent-sessions/{id}/messages` ile yanıt verebilir ve `POST /agent-sessions/{id}/archive` ile sonlandırabilirsiniz.

Depo, Linux’ta `/workspace` dizinine, macOS’ta ise `/Users/runner/work` dizinine checkout edilir. Bir oturumun sandbox’ı, agent bir adımı tamamladıktan sonra duraklar ve sonraki mesajda devam eder.

> [!WARNING]
> Ortama sahip olan Claude çalışma alanında oturum oluşturabilen herkes, Tuist hesabınızda oturum çalıştırabilir ve oturum meta verileriyle macOS talep edebilir. Bu çalışma alanına erişimi buna göre sınırlayın.

### API anahtarı olmadan bağlanma {#managed-agents-federation}

Kontrol paneli bunu sizin için ayarlar. API üzerinden Tuist aynı şekilde çalışır: her hesabın Tuist’te kendi OpenID Connect issuer’ı vardır (`https://tuist.dev/oidc/accounts/<account id>`) ve Anthropic’e yapılan her çağrı için kısa ömürlü bir token imzalar; bunu birkaç dakikalık bir Anthropic erişim token’ıyla değiştirir. Issuer’ınıza güvenen bir federation rule, Tuist’in diğer hesaplar için imzaladığı token’ları asla kabul etmez.

- Her agent ortamı yanıtı `federation_issuer_url` ve `federation_subject` (`account:123:agent-environment:456`) içerir. Console’un Custom OIDC sihirbazında issuer URL’sini kullanın ve yalnızca bu ortamı kabul etmek için tam subject’i veya hesabın tüm ortamlarını kabul etmek için `account:123:*` değerini girin. Kontrol panelinin kurulum kontrolleri `account:123:setup` subject’ini kullanır; buna yalnızca prefix izin verir. Scope olarak `workspace:developer` kullanın.
- Kuruluş, çalışma alanı, hizmet hesabı ve rule ID’lerini oluşturma sırasında veya `PATCH /agent-environments/{id}` ile `anthropic_organization_id`, `anthropic_workspace_id`, `anthropic_service_account_id` ve `anthropic_federation_rule_id` olarak gönderin. Bir ortamda hem ID’ler hem de bir API anahtarı varsa Tuist federation kullanır.

> [!NOTE]
> Anthropic, issuer’ın anahtarlarını genel bir ana makine adından HTTPS üzerinden 443 numaralı bağlantı noktasında alır. Kendi kendine barındırılan Tuist sunucunuz internetten erişilebilir değilse, Console’da **inline** JWKS kaynağını seçin ve sunucunuzun `<issuer>/jwks.json` adresinde sunduğu anahtar kümesini yapıştırın. Tuist’in imzalama anahtarı değiştiğinde bunu yeniden yapıştırın; bu değişiklik, sunucunun `TUIST_SECRET_KEY_TOKENS` (veya ayarlanmamışsa `TUIST_SECRET_KEY_BASE`) değerinin değişmesiyle gerçekleşir.

## Claude Code {#claude-code}

Claude Code bulut oturumları, geliştiricilerin [claude.ai/code](https://claude.ai/code), Claude masaüstü ve mobil uygulamaları ve `claude --cloud` üzerinden başlattığı oturumlardır. Bir oturumun nerede çalışacağını ortamına göre seçerler; bu nedenle sunmak istediğiniz her platform için bir ortam bağlamanız gerekir.

### Ortamları bağlama {#claude-code-connect}

1. Bir Claude kuruluş Sahibi, [Cloud environments](https://claude.ai/admin-settings/cloud-environments) yönetici sayfasında **Allow self-hosted environments** seçeneğini açar. Bunun için Team veya Enterprise planı gerekir; Anthropic’in [self-hosted environments](https://code.claude.com/docs/en/self-hosted-environments) kılavuzuna bakın.
2. Aynı sayfada, her platform için geliştiricilerin göreceği adla kendi kendine barındırılan bir ortam oluşturun; örneğin **Tuist Linux** ve **Tuist macOS**. Her ortamın `ccpool_…` ID’sini ve yalnızca bir kez gösterilen ortam anahtarını kopyalayın.
3. Her ortamı, `kind` değeri `claude_code` olarak ayarlanmış ve platformu belirtilmiş şekilde Tuist hesabınıza bağlayın:

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

   Diğer ortamın ID’si ve anahtarıyla `"platform": "linux"` kullanarak tekrarlayın.

Bir dakika içinde ortamlar oturum almaya hazır hale gelir. Boşta kalan bir oturum sandbox’ını 30 dakika çalıştırır, ardından duraklatır; oturumun sonraki mesajı aynı sandbox’ı devam ettirir. Bekleme süresini `max_idle_seconds` ile değiştirin (en fazla 3600).

### Linux veya macOS seçme {#claude-code-choose}

Geliştiriciler, bir bulut oturumu başlattıklarında ortamı ve buna bağlı olarak platformu seçerler:

- **claude.ai, masaüstü ve mobil uygulamalar:** yeni bir oturumun ortam seçicisinde **Tuist Linux** veya **Tuist macOS** seçeneğini belirleyin.
- **Claude Code CLI:** `claude` içinde `/remote-env` komutunu çalıştırın ve ortamı adına göre seçin. `claude --cloud "<task>"` ardından üzerinde çalışır. Tek bir oturum için birini seçmek üzere ID’sini iletin: `claude --cloud "<task>" --environment ccpool_...`.
- **Tüm bir ekip veya depo:** Claude Code [settings](https://code.claude.com/docs/en/settings) içinde varsayılan ortamın ID’sini ayarlayın; örneğin bir deponun `.claude/settings.json` dosyasında:

  ```json
  { "remote": { "defaultEnvironmentId": "ccpool_..." } }
  ```

Bu ortamlardaki oturumlar, kuruluşunuzun Claude Code kullanımını normal şekilde kullanır ve sandbox’ları Tuist hesabınıza yansır.

### Daha hızlı oturum başlatma ve derlemeler {#claude-code-caching}

- **Tuist önbelleği:** oturumlar `TUIST_URL` alır ve hesabınız aynı rafta bir önbelleğe sahipse `TUIST_CACHE_ENDPOINT` alır. Oturumdaki Tuist CLI ve `tuist_ex` Mix görevleri, oturumun kimlik token’ıyla kendi başlarına oturum açar. Kimlik doğrulama kılavuzundaki <.localized_link href="/guides/server/authentication#claude-code-sessions">Claude Code sessions</.localized_link> bölümüne bakın.
- **Önbelleğe alınmış checkout’lar:** hesabınızın Tuist GitHub uygulaması bir oturumun deposunu okuyabildiğinde, yeni bir oturum Tuist runner’larınızın kullandığı aynı önbelleğe alınmış checkout’tan başlar; böylece klonlamak yerine yalnızca eksik olduğu commit’leri getirir. Oturum sonlandığında, varsayılan dalın en son commit’inin nesnelerini geri verir; bu da CI’yı Tuist üzerinde çalıştırmayan depolar için bile önbelleğe alınmış checkout’u güncel tutar. Yalnızca GitHub’ın varsayılan dal için bildirdiği commit bunu günceller; bir oturumun kendi dalları bunu asla yapmaz. Bunu durdurmak için sandbox’ları devre dışı bırakın veya uygulamayı kaldırın.
- **macOS:** Mac, her VM ile çalıştırılan Claude Code derleme oturumlarını paylaşır, bu nedenle yeni bir oturum onu indirmaz.

## Herhangi bir Claude Code oturumundan Mac kullanma {#remote-mac}

Linux üzerinde çalışan Claude Code oturumları, örneğin Anthropic tarafından barındırılan bir ortamdaki bulut oturumları, <.localized_link href="/guides/features/sandboxes#coding-agents">Build on a Mac from a coding agent</.localized_link> bölümünde açıklandığı gibi Tuist macOS sandbox’ında hâlâ Apple platformu kodunu derleyebilir ve test edebilir. **Tuist macOS** ortamının aksine, oturum kendi ortamını korur.

**Tuist Linux** ortamında kurulacak hiçbir şey yoktur: Tuist CLI ve Tuist MCP sunucusu zaten yüklüdür ve oturumun kimliğiyle oturum açar.

Anthropic tarafından barındırılan bir ortamdaki bulut oturumları için:

1. Tuist <.localized_link href="/guides/features/agentic-coding/mcp">MCP server</.localized_link> hizmetini oturumlara kullanılabilir hale getirin: claude.ai’de `https://tuist.dev/mcp` öğesini bağlayıcı olarak ekleyin ve oturum için etkinleştirin veya deponun commit edilmiş `.mcp.json` dosyasında bildirin.
2. Tuist CLI’yı ortamın [setup script](https://code.claude.com/docs/en/cloud-environments#setup-scripts) içine yükleyin; örneğin `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist` ile.
3. `account:sandboxes:write` scope’una sahip bir <.localized_link href="/guides/server/authentication#account-tokens">account token</.localized_link> oluşturun ve bunu ortamın [environment variables](https://code.claude.com/docs/en/cloud-environments#set-environment-variables) bölümüne `TUIST_TOKEN` olarak ekleyin. Ortamı kullanan herkes bunu okuyabilir, bu nedenle önbelleğinizi de kullanabilecek durumda olmadıkça başka bir scope vermeyin: Mac üzerindeki komutlar <.localized_link href="/guides/features/sandboxes#tuist-in-sandbox">cache access</.localized_link> yalnızca token’ın izin verdiği ölçüde elde eder, bu nedenle Mac üzerindeki derlemelerin önbelleğinizi okuyup yazabilmesi için `ci` ekleyin.
4. Ortamın Tuist’e ulaşmasına izin verin. Anthropic’in varsayılan **Trusted** ağ erişimi `tuist.dev` içermez, bu nedenle **Custom** seçeneğini belirleyin, varsayılan alan adlarını koruyun ve **Allowed domains** listesine `tuist.dev` ekleyin. CLI, oturumun dosyalarını Mac’e `tuist.dev` üzerinden yükler, bu nedenle başka bir alan adına ihtiyacı yoktur.

İlk senkronizasyondan sonra Claude, projenin sabitlenmiş Tuist sürümünü yüklemek için Mac üzerindeki depo kök dizininde `mise install` komutunu çalıştırır; Tuist 4.218.0 ve sonraki sürümler daha sonra her komutta hesabınızın önbelleğine kendi başlarına oturum açar.

Claude, görev tamamlandığında Mac’i siler. Geride kalan bir Mac, boşta kaldığında duraklar ve 14 gün durakladıktan sonra silinir. Bu şekilde oluşturulan Mac’ler, diğer tüm sandbox’lar gibi Tuist hesabınıza yansır.
