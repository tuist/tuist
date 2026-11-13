---
{
  "title": "Claude",
  "titleTemplate": ":title · Sandboxes · Özellikler · Kılavuzlar · Tuist",
  "description": "Claude Managed Agents oturumlarını ve Claude Code bulut oturumlarını (claude.ai, masaüstü ve mobil uygulamalar ve claude --cloud) Linux veya macOS üzerinde Tuist Sandboxes'ta çalıştırın."
}
---
# Claude {#claude}

> [!IMPORTANT]
> **Yalnızca davetiyeyle**
>
> Tuist Sandbox’ları, hem Linux hem de macOS için şu anda yalnızca davetiyeyle erişilebilir. Hesabınız için erişim talep etmek üzere [bize ulaşın](mailto:contact@tuist.dev) veya [topluluk Slack](https://slack.tuist.dev) kanalından bize yazın.

Anthropic, Claude’un ajan döngüsünü çalıştırır ve bir *kendi kendine barındırılan ortam* Claude’un araçlarının nerede çalışacağını belirler. Birini Tuist’e bağladığınızda, içindeki her oturum Linux veya macOS üzerinde kendi Tuist <.localized_link href="/guides/features/sandboxes">sandbox</.localized_link>’ını alır. Tuist, bu ortamların ihtiyaç duyduğu worker’ları ve runner’ları çalıştırır; böylece hiçbir şeyi kendiniz barındırmazsınız.

İki tür ortam vardır, her biri bir Claude ürünü içindir:

- **[Claude Managed Agents](#managed-agents)**: Claude API veya Tuist’in agent-sessions API’si ile başlattığınız oturumlar. Ortamı (`env_…`) [Claude Console](https://platform.claude.com/environments) içinde oluşturursunuz ve her oturum Linux veya macOS’u seçebilir.
- **[Claude Code](#claude-code)**: geliştiricilerin claude.ai’dan, Claude masaüstü ve mobil uygulamalarından ve `claude --cloud` üzerinden başlattığı bulut oturumları. Bir Claude Team veya Enterprise sahibi, claude.ai yönetici ayarlarında her platform için bir tane olmak üzere ortamları (`ccpool_…`) oluşturur ve geliştiriciler ortamı seçerek Linux veya macOS’u tercih eder.

Her ikisi de bir hesap yöneticisi tarafından Tuist API üzerinden bağlanır. `tuist auth login` ile kimlik doğrulaması yapın, ardından:

```bash
export TUIST_TOKEN=$(tuist auth token)
```

## Claude Managed Agents {#managed-agents}

### Bir ortamı bağlama {#managed-agents-connect}

Hesabınızın **Ayarlar → Entegrasyonlar → Claude** bölümünden bağlanın. Form, kendi kendine barındırılan bir ortamı ve Tuist’in oturumlarını başlatırken kullandığı kimlik bilgisini ister:

1. **Ortamı oluşturun.** Claude Console’da, [Ortamlar](https://platform.claude.com/environments) sayfasında kendi kendine barındırılan bir ortam oluşturun, açın ve **Ortam anahtarı oluştur** düğmesine tıklayın. Anthropic ortam anahtarlarını yalnızca Console’da oluşturur.
2. Formun üst kısmındaki seçiciyle **bir kimlik bilgisi seçin** (aşağıya bakın).
3. **Ortam kimliğini ve anahtarını yapıştırın** ve ortamın sandbox’larının platformunu ve şeklini seçin.

Tuist, herhangi bir şeyi kaydetmeden önce ortamı kimlik bilgisiyle getirir; bu nedenle yanlış bir kimlik bilgisi, kimlik veya çalışma alanı formda hata verir. Anahtarları şifreli olarak saklar ve bir daha asla göstermez. Bir dakika içinde Tuist, ortamın oturumlarını sunmaya başlar. Şekiller için <.localized_link href="/guides/features/sandboxes#platforms">Linux ve macOS</.localized_link> bölümüne bakın.

#### API anahtarıyla {#managed-agents-connect-api-key}

Varsayılan ve sandbox’ları denemenin en hızlı yolu. Ortamın çalışma alanında geliştirici rolüne sahip bir API anahtarı yapıştırın. Entegrasyon, API anahtarı kullanan ortamları işaretler; birine güvenmeden önce bunun yerine onu federatif bir kimlikle bağlayın, böylece Tuist uzun ömürlü bir anahtar tutmaz.

#### Federatif bir kimlikle {#managed-agents-connect-federated}

Tuist, Anthropic’in [Workload Identity Federation](https://platform.claude.com/docs/en/manage-claude/workload-identity-federation) ile kimlik doğrulaması yapar, bu nedenle ona bir Anthropic API anahtarı vermezsiniz. Anthropic kuruluşunuzda yönetici rolüne ihtiyacınız var.

1. **Tuist’e güvenin.** Form, hesabınızın yayıncı URL’sini ve konu ön ekini gösterir. Claude Console’da [Workload identity](https://platform.claude.com/settings/workload-identity-federation) öğesini açın, **Connect workload** öğesine tıklayın, **Custom OIDC** seçeneğini belirleyin ve bunları `workspace:developer` kapsamıyla girin. Sihirbazın oluşturduğu hizmet hesabını ortamın çalışma alanına ekleyin.
2. **Kimlikleri girin.** Kuruluş kimliği **Ayarlar → Organization** altında, çalışma alanı kimliği ise **Ayarlar → Workspaces** altındadır. Connect workload işlemi tamamlandığında hizmet hesabı ve federasyon kuralı kimliklerini gösterir ve Workload identity sayfasındaki kural da bunları tekrar gösterir. Hiçbiri gizli değildir. Anthropic, Tuist’in token’ını reddederse Console’un [kimlik doğrulama geçmişi](https://platform.claude.com/settings/workload-identity-federation?tab=history) nedenini gösterir.

#### API ile {#managed-agents-connect-api}

Otomasyondan bağlanmak için [Claude Console](https://platform.claude.com/environments) içinde kendi kendine barındırılan bir ortam oluşturun, anahtarını oluşturun ve her ikisini de Tuist’e gönderin:

```bash
curl -X POST "https://tuist.dev/api/accounts/my-org/sandboxes/agent-environments" \
  -H "Authorization: Bearer $TUIST_TOKEN" -H "Content-Type: application/json" \
  -d '{
    "anthropic_environment_id": "env_...",
    "environment_key": "<environment key>"
  }'
```

Tuist’in API’si üzerinden oturumları başlatmak için ayrıca dört federasyon kimliğinden birini ([API anahtarı olmadan bağlanma](#managed-agents-federation) bölümüne bakın) veya bir `anthropic_api_key` gönderin. Ortam, `"platform": "darwin"` parametresini iletmediğiniz sürece Linux üzerinde çalışır; `vcpus`, `memory_mb` ve `workspace_gb` sandbox’ların şeklini değiştirir.

### Bir oturum başlatma {#managed-agents-sessions}

Her oturum, oturum başka bir platform istemediği sürece ortamın platformunda çalışır.

**Claude API ile**, oturumu normal şekilde ortamın kimliğiyle oluşturun ve oturumun meta verilerinde `tuist_platform` değerini `macos` veya `linux` olarak ayarlayın:

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

`repository_url` ve isteğe bağlı olarak `repository_ref` (bir dal veya commit), Tuist’in aracı ilk turundan önce genel bir depoyu sandbox’a klonlamasını sağlar.

**Tuist’in agent-sessions API’si ile**, Tuist sizin için aracı ve oturumu oluşturur ve Tuist hesabınıza bağlı olan özel GitHub depolarını klonlar:

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

Hesapta birden fazla ortam olduğunda `agent_environment_id` parametresini iletin. Oturumu `GET /agent-sessions/{id}/events` ile takip edebilir, `POST /agent-sessions/{id}/messages` ile yanıt verebilir ve `POST /agent-sessions/{id}/archive` ile sonlandırabilirsiniz.

Depo Linux’ta `/workspace` dizinine, macOS’ta ise `/Users/runner/work` dizinine checkout edilir. Bir oturumun sandbox’ı, ajan bir turu tamamladıktan sonra duraklar ve sonraki mesajda devam eder.

> [!WARNING]
> Ortamın sahibi olan Claude çalışma alanında oturum oluşturabilen herkes, Tuist hesabınızda oturum çalıştırabilir ve oturum meta verileriyle macOS talep edebilir. Bu çalışma alanına erişimi buna göre sınırlayın.

### API anahtarı olmadan bağlanma {#managed-agents-federation}

Panolar bunu sizin için kurar. API üzerinden Tuist aynı şekilde çalışır: her hesabın Tuist’te kendi OpenID Connect yayıncısı vardır, `https://tuist.dev/oidc/accounts/<account id>`, ve Anthropic’e yapılan her çağrı için kısa ömürlü bir token imzalar; bunu birkaç dakika geçerli olan bir Anthropic erişim token’ı ile değiştirir. Yayıncınıza güvenen bir federasyon kuralı, Tuist’in diğer hesaplar için imzaladığı token’ları asla kabul etmez.

- Her ajan ortamı yanıtı `federation_issuer_url` ve `federation_subject` (`account:123:agent-environment:456`) içerir. Console’un Custom OIDC sihirbazında, yayıncı URL’sini ve ya yalnızca bu ortamı kabul etmek için tam olarak o konuyu ya da hesabın tüm ortamlarını kabul etmek için `account:123:*` kullanın. Panonun kurulum kontrolleri `account:123:setup` konusunu kullanır; buna yalnızca ön ek izin verir. `workspace:developer` kapsamını kullanın.
- Kuruluş, çalışma alanı, hizmet hesabı ve kural kimliklerini `anthropic_organization_id`, `anthropic_workspace_id`, `anthropic_service_account_id` ve `anthropic_federation_rule_id` olarak, oluşturma sırasında veya `PATCH /agent-environments/{id}` ile gönderin. Bir ortamda hem kimlikler hem de bir API anahtarı varsa Tuist federasyonu kullanır.

> [!NOTE]
> Anthropic, yayıncının anahtarlarını herkese açık bir ana makine adından HTTPS üzerinden 443 numaralı bağlantı noktasında alır. Kendi sunucunuzda barındırdığınız Tuist sunucusuna internetten erişilemiyorsa, Console’da **satır içi** JWKS kaynağını seçin ve sunucunuzun `<issuer>/jwks.json` adresinde sunduğu anahtar kümesini yapıştırın. Tuist’in imzalama anahtarı değiştiğinde bunu tekrar yapıştırın; bu durum, sunucunun `TUIST_SECRET_KEY_TOKENS` (veya ayarlanmamışsa `TUIST_SECRET_KEY_BASE`) değiştiğinde gerçekleşir.

## Claude Code {#claude-code}

Claude Code bulut oturumları, geliştiricilerin [claude.ai/code](https://claude.ai/code), Claude masaüstü ve mobil uygulamaları ve `claude --cloud` üzerinden başlattığı oturumlardır. Bir oturumun nerede çalışacağını ortamına göre seçerler; bu nedenle sunmak istediğiniz her platform için bir ortam bağlamanız gerekir.

### Ortamları bağlama {#claude-code-connect}

1. Bir Claude kuruluşu Sahibi, [Bulut ortamları](https://claude.ai/admin-settings/cloud-environments) yönetici sayfasında **Kendi kendine barındırılan ortamlara izin ver** seçeneğini açar. Bunun için Team veya Enterprise planı gerekir; Anthropic’in [kendi kendine barındırılan ortamlar](https://code.claude.com/docs/en/self-hosted-environments) kılavuzuna bakın.
2. Aynı sayfada, her platform için geliştiricilerin göreceği adla kendi kendine barındırılan bir ortam oluşturun, örneğin **Tuist Linux** ve **Tuist macOS**. Her ortamın `ccpool_…` kimliğini ve yalnızca bir kez gösterilen ortam anahtarını kopyalayın.
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

   `"platform": "linux"` ile ve diğer ortamın kimliği ve anahtarıyla tekrarlayın.

Bir dakika içinde ortamlar oturum almaya hazır hale gelir. Boşta kalan bir oturum sandbox’ını 30 dakika çalışır durumda tutar, ardından duraklatır; oturumun sonraki mesajı aynı sandbox’ı devam ettirir. Bekleme süresini `max_idle_seconds` ile değiştirin (en fazla 3600).

### Linux veya macOS seçme {#claude-code-choose}

Geliştiriciler bir bulut oturumu başlattıklarında ortamı ve dolayısıyla platformu seçerler:

- **claude.ai, masaüstü ve mobil uygulamalar:** yeni bir oturumun ortam seçicisinde **Tuist Linux** veya **Tuist macOS** seçeneğini belirleyin.
- **Claude Code CLI:** `claude` içinde `/remote-env` komutunu çalıştırın ve ortamı adına göre seçin. `claude --cloud "<task>"` ardından bunun üzerinde çalışır. Tek bir oturum için birini seçmek üzere kimliğini iletin: `claude --cloud "<task>" --environment ccpool_...`.
- **Tüm bir ekip veya depo:** varsayılan ortamın kimliğini Claude Code [ayarlarında](https://code.claude.com/docs/en/settings) belirleyin, örneğin bir deponun `.claude/settings.json` dosyasında:

  ```json
  { "remote": { "defaultEnvironmentId": "ccpool_..." } }
  ```

Bu ortamlardaki oturumlar, kuruluşunuzun Claude Code kullanımını her zamanki gibi kullanır ve sandbox’ları Tuist hesabınıza yansır.

### Daha hızlı oturum başlatma ve derlemeler {#claude-code-caching}

- **Tuist önbelleği:** oturumlar `TUIST_URL` alır ve hesabınız aynı rafta bir önbelleğe sahipse `TUIST_CACHE_ENDPOINT` alır. Oturumdaki Tuist CLI ve `tuist_ex` Mix görevleri, oturumun kimlik token’ı ile kendi başlarına oturum açar. Kimlik doğrulama kılavuzundaki <.localized_link href="/guides/server/authentication#claude-code-sessions">Claude Code oturumları</.localized_link> bölümüne bakın.
- **Önbelleğe alınmış checkout’lar:** hesabınızın Tuist GitHub uygulaması bir oturumun deposunu okuyabildiğinde, yeni bir oturum Tuist runner’larınızın kullandığı aynı önbelleğe alınmış checkout’tan başlar; böylece klonlamak yerine yalnızca eksik olduğu commit’leri getirir. Oturum sona erdiğinde, varsayılan dalın en son commit’inin nesnelerini geri verir; bu da Tuist üzerinde CI çalıştırmayan depolar için bile önbelleğe alınmış checkout’un güncel kalmasını sağlar. Yalnızca GitHub’ın varsayılan dal için bildirdiği commit bunu günceller; bir oturumun kendi dalları bunu asla yapmaz. Bunu durdurmak için sandbox’ları devre dışı bırakın veya uygulamayı kaldırın.
- **macOS:** Mac, Claude Code derleme oturumlarını her VM ile paylaşır, bu nedenle yeni bir oturum onu indirmek zorunda kalmaz.

## Herhangi bir Claude Code oturumundan Mac kullanma {#remote-mac}

Linux üzerinde çalışan Claude Code oturumları, örneğin Anthropic tarafından barındırılan bir ortamdaki bulut oturumları, <.localized_link href="/guides/features/sandboxes#coding-agents">Kodlama aracından bir Mac üzerinde derleme</.localized_link> bölümünde anlatıldığı gibi Tuist macOS sandbox’ında Apple platformu kodunu hâlâ derleyebilir ve test edebilir. Bir **Tuist macOS** ortamından farklı olarak, hiçbir şeyin bağlanmasına gerek yoktur ve oturum kendi ortamını korur. Bulut oturumları için:

1. Tuist <.localized_link href="/guides/features/agentic-coding/mcp">MCP sunucusunu</.localized_link> oturumlar için kullanılabilir hale getirin: claude.ai’de `https://tuist.dev/mcp` öğesini bağlayıcı olarak ekleyin ve oturum için etkinleştirin veya deponun commit edilmiş `.mcp.json` dosyasında beyan edin.
2. Tuist CLI’yı ortamın [kurulum betiğine](https://code.claude.com/docs/en/cloud-environments#setup-scripts) yükleyin, örneğin `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist` ile.
3. `account:sandboxes:write` kapsamına sahip bir <.localized_link href="/guides/server/authentication#account-tokens">hesap token’ı</.localized_link> oluşturun ve bunu ortamın [ortam değişkenlerine](https://code.claude.com/docs/en/cloud-environments#set-environment-variables) `TUIST_TOKEN` olarak ekleyin. Ortamı kullanan herkes bunu okuyabilir, bu nedenle başka bir kapsam vermeyin.
4. Ortamın Tuist’e ulaşmasına izin verin. Anthropic’in varsayılan **Güvenilir** ağ erişimi `tuist.dev` içermez, bu nedenle **Özel** seçeneğini belirleyin, varsayılan alan adlarını koruyun ve **İzin verilen alan adları** listesine `tuist.dev` ekleyin. CLI, oturumun dosyalarını Mac’e `tuist.dev` üzerinden yükler, bu nedenle başka bir alan adına ihtiyacı yoktur.

Claude, görev tamamlandığında Mac’i siler. Geride bırakılan bir Mac boşta kaldığında duraklar ve 14 gün durakladıktan sonra silinir. Bu şekilde oluşturulan Mac’ler, diğer tüm sandbox’lar gibi Tuist hesabınıza yansır.
