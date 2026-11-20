---
{
  "title": "Claude",
  "titleTemplate": ":title · Sandboxes · Özellikler · Kılavuzlar · Tuist",
  "description": "Claude Managed Agents oturumlarını ve Claude Code bulut oturumlarını (claude.ai, masaüstü ve mobil uygulamalar ve claude --cloud) Linux veya macOS üzerinde Tuist Sandboxes ile çalıştırın."
}
---
# Claude {#claude}

> [!IMPORTANT]
> **Davetiyeyle erişim**
>
> Tuist Sandboxes, hem Linux hem de macOS için şu anda yalnızca davetiyeyle erişilebilir. Hesabınız için erişim talep etmek üzere [bize ulaşın](mailto:contact@tuist.dev) veya [topluluk Slack](https://slack.tuist.dev) kanalından bize mesaj atın.

Anthropic, Claude'un agent döngüsünü çalıştırır ve bir *kendi barındırdığınız ortam*, Claude'un araçlarının nerede çalışacağını belirler. Birini Tuist’e bağladığınızda, içindeki her oturum Linux veya macOS üzerinde kendi Tuist <.localized_link href="/guides/features/sandboxes">sandbox</.localized_link> ortamına sahip olur. Tuist, bu ortamların ihtiyaç duyduğu worker’ları ve runner’ları çalıştırır; böylece hiçbir şeyi kendiniz barındırmak zorunda kalmazsınız.

İki tür ortam vardır, her biri bir Claude ürünü içindir:

- **[Claude Managed Agents](#managed-agents)**: Claude API veya Tuist’in agent-sessions API’si ile başlattığınız oturumlar. Ortamı (`env_…`) [Claude Console](https://platform.claude.com/environments) içinde oluşturursunuz ve her oturum Linux veya macOS seçebilir.
- **[Claude Code](#claude-code)**: Geliştiricilerin claude.ai’dan, Claude masaüstü ve mobil uygulamalarından ve `claude --cloud` komutundan başlattığı bulut oturumları. Bir Claude Team veya Enterprise sahibi, claude.ai yönetici ayarlarında her platform için birer tane olmak üzere ortamları (`ccpool_…`) oluşturur ve geliştiriciler ortamı seçerek Linux veya macOS tercih eder.

Her ikisi de bir hesap yöneticisi tarafından Tuist API üzerinden bağlanır. `tuist auth login` ile kimlik doğrulaması yapın, ardından:

```bash
export TUIST_TOKEN=$(tuist auth token)
```

## Claude Managed Agents {#managed-agents}

### Bir ortamı bağlama {#managed-agents-connect}

Hesabınızın **Ayarlar → Entegrasyonlar → Claude** bölümünden bağlanın. Form, kendi barındırdığınız bir ortamı ve Tuist’in oturumlarını başlatmak için kullandığı kimlik bilgisini ister:

1. **Ortamı oluşturun.** Claude Console’da, [Environments](https://platform.claude.com/environments) sayfasında kendi barındırdığınız bir ortam oluşturun, açın ve **Generate environment key** düğmesine tıklayın. Anthropic, ortam anahtarlarını yalnızca Console’da oluşturur.
2. Formun üst kısmındaki seçici ile **bir kimlik bilgisi seçin** (aşağıya bakın).
3. **Ortam kimliğini ve anahtarını yapıştırın** ve ortamın sandbox’larının platformunu ve yapılandırmasını seçin.

Tuist, herhangi bir şeyi kaydetmeden önce ortamı kimlik bilgisiyle getirir; bu nedenle yanlış bir kimlik bilgisi, kimlik veya çalışma alanı formda hata verir. Anahtarları şifreli olarak saklar ve bir daha asla göstermez. Bir dakika içinde Tuist, ortamın oturumlarını sunmaya başlar. Yapılandırmalar için <.localized_link href="/guides/features/sandboxes#platforms">Linux ve macOS</.localized_link> bölümüne bakın.

#### API anahtarı ile {#managed-agents-connect-api-key}

Varsayılan ve sandbox’ları denemenin en hızlı yolu. Ortamın çalışma alanına geliştirici rolüne sahip bir API anahtarı yapıştırın. Entegrasyon, API anahtarı kullanan ortamları işaretler; birine güvenmeden önce, Tuist’in uzun ömürlü bir anahtar tutmaması için bunun yerine federated identity ile bağlayın.

#### Federated identity ile {#managed-agents-connect-federated}

Tuist, Anthropic’in [Workload Identity Federation](https://platform.claude.com/docs/en/manage-claude/workload-identity-federation) özelliğiyle kimlik doğrulaması yapar, böylece ona asla bir Anthropic API anahtarı vermezsiniz. Anthropic organizasyonunuzda yönetici rolüne ihtiyacınız vardır.

1. **Tuist’e güvenin.** Form, hesabınızın issuer URL’sini ve subject prefix’ini gösterir. Claude Console’da [Workload identity](https://platform.claude.com/settings/workload-identity-federation) bölümünü açın, **Connect workload** düğmesine tıklayın, **Custom OIDC** seçeneğini belirleyin ve bunları `workspace:developer` scope’u ile girin. Sihirbazın oluşturduğu hizmet hesabını ortamın çalışma alanına ekleyin.
2. **Kimlikleri girin.** Organizasyon kimliği **Ayarlar → Organization** altında, çalışma alanı kimliği ise **Ayarlar → Workspaces** altındadır. Connect workload işlemi tamamlandığında hizmet hesabı ve federation rule kimliklerini gösterir ve Workload identity sayfasındaki rule detayları da bunları tekrar gösterir. Hiçbiri gizli değildir. Anthropic, Tuist’in token’ını reddederse, Console’un [authentication history](https://platform.claude.com/settings/workload-identity-federation?tab=history) bölümü nedenini gösterir.

#### API ile {#managed-agents-connect-api}

Otomasyondan bağlanmak için, [Claude Console](https://platform.claude.com/environments) içinde kendi barındırdığınız bir ortam oluşturun, anahtarını üretin ve her ikisini de Tuist’e gönderin:

```bash
curl -X POST "https://tuist.dev/api/accounts/my-org/sandboxes/agent-environments" \
  -H "Authorization: Bearer $TUIST_TOKEN" -H "Content-Type: application/json" \
  -d '{
    "anthropic_environment_id": "env_...",
    "environment_key": "<environment key>"
  }'
```

Tuist’in API’si aracılığıyla oturumları başlatmak için ayrıca dört federation kimliğinden birini ([API anahtarı olmadan bağlanma](#managed-agents-federation) bölümüne bakın) veya bir `anthropic_api_key` gönderin. Ortam, `"platform": "darwin"` parametresini geçirmediğiniz sürece Linux üzerinde çalışır; `vcpus`, `memory_mb` ve `workspace_gb` sandbox’ların yapılandırmasını değiştirir, `xcode_version` ise macOS sandbox’larının [Xcode](#xcode) sürümünü belirler.

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

`repository_url` ve isteğe bağlı olarak `repository_ref` (bir dal veya commit), Tuist’in agent’ın ilk turundan önce genel bir depoyu sandbox’a klonlamasını sağlar.

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

Hesapta birden fazla ortam varsa, `agent_environment_id` parametresini iletin. Oturumu `GET /agent-sessions/{id}/events` ile takip edebilir, `POST /agent-sessions/{id}/messages` ile yanıt verebilir ve `POST /agent-sessions/{id}/archive` ile sonlandırabilirsiniz.

Depo, Linux’ta `/workspace` dizinine, macOS’ta ise `/Users/runner/work` dizinine checkout edilir. Bir oturumun sandbox’ı, agent bir turu tamamladıktan sonra duraklar ve sonraki mesajda devam eder.

### Bir oturumun Xcode’unu seçme {#managed-agents-xcode}

Bir oturumun Mac’i, Claude herhangi bir aracı çalıştırmadan önce başlatılır, bu nedenle Claude kendi Xcode’unu seçemez. Oturumu oluşturan kişi, macOS’u seçtiği şekilde Xcode’u da seçer. Tuist, aşağıdakilerden ayarlanmış olan ilkini kullanır:

1. Tuist’in agent-sessions API’sinde, `platform` yanında yer alan `xcode_version`. Tuist’in sunmadığı bir sürüm, oturumu oluştururken reddedilir ve seçebileceğiniz sürümlerin listesi sunulur.
2. Claude API ile oturum oluşturduğunuzda, oturumun meta verilerindeki `tuist_xcode_version`:

   ```json
   "metadata": { "tuist_platform": "macos", "tuist_xcode_version": "26.1.1" }
   ```

3. Ortamın `xcode_version`, oturum ortamın platformunda çalıştığında.
4. Varsayılan Xcode.

Platform belirtilmeyen bir Xcode, macOS ister. Bilmeniz gereken bazı noktalar:

- **Oturum Xcode’unu korur.** Sandbox’ı bir kez başlatılır ve sonraki bir mesaj veya değiştirilen meta veriler bunu değiştirmez. Başka bir Xcode için yeni bir oturum kullanın.
- **Tuist, ilk tur geldiğinde meta verileri kontrol eder.** `tuist_xcode_version`, Tuist’in sunmadığı bir Xcode’u belirtiyorsa, Tuist o turu sandbox başlatmadan durdurur ve seçebileceğiniz sürümleri günlüğe kaydeder. Oturumu oluştururken hatayı almak için Tuist’in agent-sessions API’sini kullanın.
- **macOS ortamında, Tuist tahmin etmek yerine bekler.** Tuist yeni bir oturumun meta verilerini okuyamazsa, ortamın Xcode’unu başlatmak yerine turu bekletir ve tekrar dener.

> [!WARNING]
> Ortamın sahibi olan Claude çalışma alanında oturum oluşturabilen herkes, Tuist hesabınızda oturum çalıştırabilir ve oturum meta verileriyle macOS’u ve onun Xcode’unu talep edebilir. Bu çalışma alanına erişimi buna göre sınırlayın.

### API anahtarı olmadan bağlanma {#managed-agents-federation}

Kontrol paneli bunu sizin için ayarlar. API üzerinden Tuist aynı şekilde çalışır: her hesabın Tuist’te kendi OpenID Connect yayıncısı vardır, `https://tuist.dev/oidc/accounts/<account id>`, ve Anthropic’e yapılan her çağrı için kısa ömürlü bir imzalı jeton oluşturur; bunu birkaç dakika geçerli olan bir Anthropic erişim jetonuyla değiştirir. Yayıncınıza güvenen bir federasyon kuralı, Tuist’in diğer hesaplar için imzaladığı jetonları asla kabul etmez.

- Her agent ortamı yanıtı `federation_issuer_url` ve `federation_subject` (`account:123:agent-environment:456`) içerir. Konsolun Özel OIDC sihirbazında, yalnızca bu ortama izin vermek için yayıncı URL’sini ve tam olarak bu konuyu kullanın veya hesabın tüm ortamlarına izin vermek için `account:123:*` kullanın. Kontrol panelinin kurulum kontrolleri, yalnızca ön ek tarafından kabul edilen `account:123:setup` konusunu kullanır. `workspace:developer` kapsamını kullanın.
- Kuruluşu, çalışma alanını, hizmet hesabını ve kural kimliklerini oluşturma sırasında veya `PATCH /agent-environments/{id}` ile `anthropic_organization_id`, `anthropic_workspace_id`, `anthropic_service_account_id` ve `anthropic_federation_rule_id` olarak gönderin. Bir ortamda hem kimlikler hem de bir API anahtarı varsa, Tuist federasyonu kullanır.

> [!NOTE]
> Anthropic, yayıncının anahtarlarını genel bir ana makineden 443 numaralı bağlantı noktasında HTTPS üzerinden alır. Kendi barındırdığınız Tuist sunucusuna internetten ulaşılamıyorsa, Konsolda **satır içi** JWKS kaynağını seçin ve sunucunuzun `<issuer>/jwks.json` adresinde sunduğu anahtar kümesini yapıştırın. Tuist’in imzalama anahtarı değiştiğinde bunu tekrar yapıştırın; bu değişiklik, sunucunun `TUIST_SECRET_KEY_TOKENS` (veya ayarlanmamışsa `TUIST_SECRET_KEY_BASE`) değeri değiştiğinde gerçekleşir.

## Claude Code {#claude-code}

Claude Code bulut oturumları, geliştiricilerin [claude.ai/code](https://claude.ai/code), Claude masaüstü ve mobil uygulamaları ve `claude --cloud` üzerinden başlattıkları oturumlardır. Bir oturumun nerede çalışacağını ortamına göre seçerler, bu nedenle sunmak istediğiniz her platform için bir ortam bağlarsınız.

### Ortamları bağlama {#claude-code-connect}

1. Bir Claude kuruluşu Sahibi, [Bulut ortamları](https://claude.ai/admin-settings/cloud-environments) yönetici sayfasında **Kendi barındırılan ortamlara izin ver** seçeneğini açar. Bunun için Team veya Enterprise planı gerekir; Anthropic’in [kendi barındırılan ortamlar](https://code.claude.com/docs/en/self-hosted-environments) kılavuzuna bakın.
2. Aynı sayfada, geliştiricilerin göreceği adla her platform için kendi barındırılan bir ortam oluşturun, örneğin **Tuist Linux** ve **Tuist macOS**. Her ortamın `ccpool_…` kimliğini ve yalnızca bir kez gösterilen ortam anahtarını kopyalayın.
3. Her ortamı, `kind` değerini `claude_code` olarak ve platformuyla birlikte ayarlayarak Tuist hesabınıza bağlayın:

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

   Diğer ortamın kimliği ve anahtarıyla `"platform": "linux"` kullanarak tekrarlayın.

Bir dakika içinde ortamlar oturum almaya hazır hale gelir. Boşta kalan bir oturum, sandbox’ını 30 dakika çalışır durumda tutar, ardından duraklatır; oturumun sonraki mesajı aynı sandbox’ı devam ettirir. Bekleme süresini `max_idle_seconds` ile değiştirin (en fazla 3600).

### Linux veya macOS seçme {#claude-code-choose}

Geliştiriciler, bir bulut oturumu başlattıklarında ortamı ve dolayısıyla platformu seçerler:

- **claude.ai, masaüstü ve mobil uygulamalar:** yeni bir oturumun ortam seçicisinde **Tuist Linux** veya **Tuist macOS** seçin.
- **Claude Code CLI:** `claude` içinde `/remote-env` komutunu çalıştırın ve ortamı adına göre seçin. `claude --cloud "<task>"` ardından üzerinde çalışır. Tek bir oturum için birini seçmek üzere kimliğini iletin: `claude --cloud "<task>" --environment ccpool_...`.
- **Tüm bir ekip veya depo:** Claude Code [ayarlarında](https://code.claude.com/docs/en/settings) varsayılan ortamın kimliğini ayarlayın, örneğin bir deponun `.claude/settings.json` dosyasında:

  ```json
  { "remote": { "defaultEnvironmentId": "ccpool_..." } }
  ```

Bu ortamlardaki oturumlar, kuruluşunuzun Claude Code kullanımını normal şekilde kullanır ve sandbox’ları Tuist hesabınıza yansır.

### Bir Xcode seçme {#xcode}

Her macOS ortamı bir <.localized_link href="/guides/features/sandboxes#xcode">Xcode</.localized_link> başlatır; `xcode_version` ile bağlamazsanız varsayılan olan kullanılır, örneğin `"xcode_version": "26.1.1"`. Birden fazlasını sunmak için her biri için bir ortam bağlayın ve adını ona göre verin, örneğin **Tuist macOS · Xcode 26.1.1**. Geliştiriciler ardından ortamı seçerek Xcode’u seçer.

Bir ortamı başka bir Xcode’a taşımak için onu güncelleyin:

```bash
curl -X PATCH "https://tuist.dev/api/accounts/my-org/sandboxes/agent-environments/<id>" \
  -H "Authorization: Bearer $TUIST_TOKEN" -H "Content-Type: application/json" \
  -d '{ "xcode_version": "27.0" }'
```

Yeni oturumlar yeni Xcode’u alır ve zaten sandbox’ı olan oturumlar kendi sandbox’larını korur. `null` varsayılana döner. Aynı kural, oturumlarının da [kendinkini seçebildiği](#managed-agents-xcode) Yönetilen Agent ortamları için geçerlidir.

### Daha hızlı oturum başlatma ve derlemeler {#claude-code-caching}

- **Tuist önbelleği:** oturumlar `TUIST_URL` alır ve hesabınız aynı rafta bir önbelleğe sahipse `TUIST_CACHE_ENDPOINT` alır. Oturumdaki Tuist CLI ve `tuist_ex` Mix görevleri, oturumun kimlik jetonuyla kendi kendilerine oturum açar. Kimlik doğrulama kılavuzundaki <.localized_link href="/guides/server/authentication#claude-code-sessions">Claude Code oturumları</.localized_link> bölümüne bakın.
- **Önbelleğe alınmış checkout’lar:** hesabınızın Tuist GitHub uygulaması bir oturumun deposunu okuyabildiğinde, yeni bir oturum Tuist runner’larınızın kullandığı aynı önbelleğe alınmış checkout’tan başlar, böylece klonlamak yerine yalnızca eksik olduğu commit’leri çeker. Oturum sona erdiğinde, varsayılan dalın en son commit’inin nesnelerini geri verir; bu, Tuist’te CI çalıştırmayan depolar için bile önbelleğe alınmış checkout’u güncel tutar. Yalnızca GitHub’ın varsayılan dal için bildirdiği commit bunu günceller; bir oturumun kendi dalları bunu asla yapmaz. Bunu durdurmak için sandbox’ları devre dışı bırakın veya uygulamayı kaldırın.
- **macOS:** Mac, Claude Code derleme oturumlarının her VM ile paylaştığını kullanır, bu nedenle yeni bir oturum onu indirmez.

## Herhangi bir Claude Code oturumundan Mac kullanma {#remote-mac}

Linux’ta çalışan Claude Code oturumları, örneğin Anthropic tarafından barındırılan bir ortamda bulut oturumları, <.localized_link href="/guides/features/sandboxes#coding-agents">Kodlama agent’ından Mac’te derleme</.localized_link> bölümünde açıklandığı gibi Tuist macOS sandbox’ında hâlâ Apple platformu kodunu derleyip test edebilir. Bir **Tuist macOS** ortamının aksine, oturum kendi ortamını korur.

Bir **Tuist Linux** ortamında kurulacak hiçbir şey yoktur: Tuist CLI ve Tuist MCP sunucusu zaten yüklüdür ve oturumun kimliğiyle oturum açar.

Anthropic tarafından barındırılan bir ortamda bulut oturumları için:

1. Tuist <.localized_link href="/guides/features/agentic-coding/mcp">MCP sunucusunu</.localized_link> oturumlara kullanılabilir hale getirin: claude.ai’de `https://tuist.dev/mcp` bağlantısını ekleyin ve oturum için etkinleştirin veya deponun commit edilmiş `.mcp.json` dosyasında bildirin.
2. Tuist CLI’yı ortamın [kurulum betiğine](https://code.claude.com/docs/en/cloud-environments#setup-scripts) yükleyin, örneğin `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist` ile.
3. <.localized_link href="/guides/server/authentication#account-tokens">Hesap jetonu</.localized_link> oluşturun ve `account:sandboxes:write` kapsamını verin, ardından bunu ortamın [ortam değişkenlerine](https://code.claude.com/docs/en/cloud-environments#set-environment-variables) `TUIST_TOKEN` olarak ekleyin. Ortamı kullanan herkes bunu okuyabilir, bu nedenle önbelleğinizi de kullanma izni yoksa başka bir kapsam vermeyin: Mac üzerindeki komutlar, jetonun sahip olduğu ölçüde <.localized_link href="/guides/features/sandboxes#tuist-in-sandbox">önbellek erişimi</.localized_link> alır; bu nedenle Mac üzerinde derlemelerin önbelleğinizi okuyup yazabilmesi için `ci` ekleyin.
4. Ortamın Tuist’e ulaşmasına izin verin. Anthropic’in varsayılan **Güvenilir** ağ erişimi `tuist.dev` içermiyor, bu nedenle **Özel** seçeneğini belirleyin, varsayılan alan adlarını koruyun ve `tuist.dev` öğesini **İzin verilen alan adları** listesine ekleyin. CLI, oturumun dosyalarını Mac’e `tuist.dev` üzerinden yükler, bu nedenle başka bir alan adına ihtiyaç duymaz.

Mac’te Tuist CLI yüklüdür ve proje mise aracılığıyla bir sürüm sabitlediğinde projenin kendi sürümünü çalıştırır; Tuist 4.218.0 ve sonraki sürümler, her komutta hesabınızın önbelleğine kendi kendilerine oturum açar.

### Hazır Mac’ler {#remote-mac-snapshots}

Bir **Tuist Linux** ortamı bu Mac’leri önceden hazırlayabilir. macOS kurulum betiğini API ile ayarlayın (`PATCH /api/accounts/{account}/sandboxes/agent-environments/{id}` üzerinde `macos_setup_script`), örneğin:

```bash
mise install
tuist install
tuist generate --no-open
xcodebuild build -workspace App.xcworkspace -scheme App -destination 'platform=iOS Simulator,name=iPhone 17'
```

Claude, Tuist projelerinizden birine bağlı bir depo için bir Mac oluşturduğunda, `create_sandbox` depoyu alır ve Mac, Xcode’u için o deponun anlık görüntüsünden başlatılır: varsayılan dal `~/work/<name>` konumuna klonlanır, betik orada çalıştırılır ve derleme ürünleri yerindedir. İlk `tuist sandbox sync` yalnızca o commit’ten farklı olan dosyaları gönderir, bu nedenle Xcode yalnızca değiştirdikleri şeyleri yeniden derler. Bir depo ve Xcode için ilk Mac boşta başlar ve anlık görüntüsü, sonraki Mac’ler için boşta bir Mac üzerinde en fazla bir saat boyunca oluşturulur. Betiği, Xcode’u veya imajı değiştirmek onu tekrar oluşturur.

Claude, görev tamamlandığında Mac’i siler. Geride kalan bir Mac boşta kaldığında duraklatılır ve 14 gün duraklatıldıktan sonra silinir. Bu şekilde oluşturulan Mac’ler, diğer tüm sandbox’lar gibi Tuist hesabınıza dahil edilir.
