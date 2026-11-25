---
{
  "title": "Claude",
  "titleTemplate": ":title · Alanlar · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist Alanlarında, Linux veya macOS üzerinde Claude Yönetilen Ajan oturumlarını ve Claude Code bulut oturumlarını (claude.ai, masaüstü ve mobil uygulamalar ve claude --cloud) çalıştırın."
}
---
# Claude {#claude}

> [!IMPORTANT]
> **Yalnızca davetle**
>
> Tuist Sandbox'ları, hem Linux hem de macOS için şu anda yalnızca davetle erişilebilir. Hesabınız için erişim istemek üzere [bize ulaşın](mailto:contact@tuist.dev) veya [topluluk Slack](https://slack.tuist.dev) kanalında bize yazın.

Anthropic, Claude'un agent döngüsünü çalıştırır ve bir *kendi sunucunuzda barındırılan ortam*, Claude'un araçlarının nerede çalışacağını belirler. Birini Tuist'e bağlayın; içindeki her oturum, Linux veya macOS üzerinde kendi Tuist <.localized_link href="/guides/features/sandboxes">sandbox</.localized_link>'ına sahip olur. Tuist, bu ortamların ihtiyaç duyduğu worker'ları ve runner'ları çalıştırır, böylece hiçbir şeyi kendiniz barındırmazsınız.

İki tür ortam vardır, her biri bir Claude ürünü içindir:

- **[Claude Managed Agents](#managed-agents)**: Claude API veya Tuist'in agent-sessions API'si ile başlattığınız oturumlar. Ortamı (`env_…`) [Claude Console](https://platform.claude.com/environments)'da oluşturursunuz ve her oturum Linux veya macOS'u seçebilir.
- **[Claude Code](#claude-code)**: Geliştiricilerin claude.ai'den, Claude masaüstü ve mobil uygulamalarından ve `claude --cloud`'den başlattığı bulut oturumları. Bir Claude Team veya Enterprise sahibi, claude.ai yönetici ayarlarında her platform için bir tane olmak üzere ortamları (`ccpool_…`) oluşturur ve geliştiriciler ortamı seçerek Linux veya macOS'u tercih eder.

Her ikisi de bir hesap yöneticisi tarafından Tuist API üzerinden bağlanır. `tuist auth login` ile kimlik doğrulaması yapın, ardından:

```bash
export TUIST_TOKEN=$(tuist auth token)
```

## Claude Managed Agents {#managed-agents}

### Bir ortam bağlama {#managed-agents-connect}

Hesabınızın **Ayarlar → Entegrasyonlar → Claude** bölümünden bağlanın. Form, kendi sunucunuzda barındırılan bir ortam ve Tuist'in oturumlarını başlatmak için kullandığı kimlik bilgilerini ister:

1. **Ortamı oluşturun.** Claude Console'da, [Environments](https://platform.claude.com/environments) sayfasında kendi sunucunuzda barındırılan bir ortam oluşturun, açın ve **Generate environment key** düğmesine tıklayın. Anthropic, ortam anahtarlarını yalnızca Console'da oluşturur.
2. Formun üst kısmındaki seçici ile **bir kimlik bilgisi seçin** (aşağıya bakın).
3. **Ortam kimliğini ve anahtarını yapıştırın** ve ortamın sandbox'larının platformunu ve şeklini seçin.

Tuist, herhangi bir şeyi kaydetmeden önce ortamı kimlik bilgisiyle getirir; bu nedenle yanlış bir kimlik bilgisi, kimlik veya çalışma alanı formda hata verir. Anahtarları şifrelenmiş olarak saklar ve bir daha asla göstermez. Bir dakika içinde Tuist, ortamın oturumlarını sunmaya başlar. Şekiller için <.localized_link href="/guides/features/sandboxes#platforms">Linux ve macOS</.localized_link> bölümüne bakın.

#### API anahtarı ile {#managed-agents-connect-api-key}

Varsayılan ve sandbox'ları denemenin en hızlı yolu. Ortamın çalışma alanında geliştirici rolüne sahip bir API anahtarı yapıştırın. Entegrasyon, API anahtarı kullanan ortamları işaretler; birine güvenmeden önce, Tuist'in uzun ömürlü bir anahtar tutmaması için bunun yerine federated identity ile bağlayın.

#### Federated identity ile {#managed-agents-connect-federated}

Tuist, Anthropic'in [Workload Identity Federation](https://platform.claude.com/docs/en/manage-claude/workload-identity-federation) özelliğiyle kimlik doğrulaması yapar, böylece ona hiçbir zaman bir Anthropic API anahtarı vermezsiniz. Anthropic organizasyonunuzda yönetici rolüne ihtiyacınız vardır.

1. **Tuist'e güvenin.** Form, hesabınızın issuer URL'sini ve subject prefix'ini gösterir. Claude Console'da [Workload identity](https://platform.claude.com/settings/workload-identity-federation)yi açın, **Connect workload**a tıklayın, **Custom OIDC**yü seçin ve bunları `workspace:developer` scope'u ile girin. Sihirbazın oluşturduğu service account'u ortamın çalışma alanına ekleyin.
2. **ID'leri girin.** Organizasyon ID'si **Ayarlar → Organization** altında, çalışma alanı ID'si ise **Ayarlar → Workspaces** altındadır. Connect workload işlemi tamamlandığında service account ve federation rule ID'lerini gösterir ve Workload identity'deki kural sayfası bunları tekrar gösterir. Hiçbiri gizli değildir. Anthropic, Tuist'in token'ını reddederse, Console'un [authentication history](https://platform.claude.com/settings/workload-identity-federation?tab=history)si nedenini gösterir.

#### API ile {#managed-agents-connect-api}

Otomasyondan bağlanmak için [Claude Console](https://platform.claude.com/environments)'da kendi sunucunuzda barındırılan bir ortam oluşturun, anahtarını oluşturun ve her ikisini de Tuist'e gönderin:

```bash
curl -X POST "https://tuist.dev/api/accounts/my-org/sandboxes/agent-environments" \
  -H "Authorization: Bearer $TUIST_TOKEN" -H "Content-Type: application/json" \
  -d '{
    "anthropic_environment_id": "env_...",
    "environment_key": "<environment key>"
  }'
```

Tuist'in API'si aracılığıyla oturumları başlatmak için ayrıca dört federation ID'sini ([API anahtarı olmadan bağlanma](#managed-agents-federation) bölümüne bakın) veya bir `anthropic_api_key` gönderin. Ortam, `"platform": "darwin"` geçmediğiniz sürece Linux üzerinde çalışır; `vcpus`, `memory_mb` ve `workspace_gb` sandbox'ların şeklini değiştirir ve `xcode_version` macOS sandbox'larının [Xcode](#xcode) sürümünü belirler.

### Bir oturum başlatma {#managed-agents-sessions}

Oturum başka bir platform istemediği sürece her oturum ortamın platformunda çalışır.

**Claude API ile**, oturumu normal şekilde ortamın ID'si ile oluşturun ve oturumun metadata'sında `tuist_platform`'yi `macos` veya `linux` olarak ayarlayın:

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

`repository_url` ve isteğe bağlı olarak `repository_ref` (bir dal veya commit), agent'ın ilk turundan önce Tuist'in genel bir depoyu sandbox'a klonlamasını sağlar.

**Tuist'in agent-sessions API'si ile**, Tuist sizin için agent'ı ve oturumu oluşturur ve Tuist hesabınıza bağlı olan özel GitHub depolarını klonlar:

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

Depo, Linux'ta `/workspace` dizinine, macOS'ta ise `/Users/runner/work` dizinine checkout edilir. Bir oturumun sandbox'ı, agent bir turu tamamladıktan sonra duraklar ve sonraki mesajda devam eder.

### Bir oturumun Xcode'unu seçme {#managed-agents-xcode}

Bir oturumun Mac'i, Claude herhangi bir aracı çalıştırmadan önce önyüklenir, bu nedenle Claude kendi Xcode'unu seçemez. Oturumu oluşturan kişi, macOS'u seçtiği gibi bunu da seçer. Tuist, ayarlanan ilk seçeneği kullanır:

1. Tuist'in agent-sessions API'sinde, `platform` yanında bulunan `xcode_version`. Tuist'in sunmadığı bir sürüm, oturumu oluştururken seçebileceğiniz sürümlerin listesiyle birlikte reddedilir.
2. Claude API ile oturum oluşturduğunuzda, oturumun metadata'sındaki `tuist_xcode_version`:

   ```json
   "metadata": { "tuist_platform": "macos", "tuist_xcode_version": "26.1.1" }
   ```

3. Ortamın `xcode_version`, oturum ortamın platformunda çalıştığında.
4. Varsayılan Xcode.

Platform belirtilmeyen bir Xcode, macOS ister. Bilmeniz gereken bazı şeyler:

- **Oturum Xcode'unu korur.** Sandbox'ı bir kez önyüklenir ve sonraki bir mesaj veya değişen metadata onu değiştirmez. Başka bir Xcode için yeni bir oturum kullanın.
- **Tuist, ilk tur geldiğinde metadata'yı kontrol eder.** Eğer `tuist_xcode_version`, Tuist'in sunmadığı bir Xcode'u belirtirse, Tuist sandbox başlatmadan o turu durdurur ve seçebileceğiniz sürümleri günlüğe kaydeder. Oturumu oluştururken hatayı almak için Tuist'in agent-sessions API'sini kullanın.
- **macOS ortamında, Tuist tahmin etmek yerine bekler.** Tuist yeni bir oturumun metadata'sını okuyamazsa, ortamın Xcode'unu önyüklemek yerine turu bekletir ve tekrar dener.

> [!WARNING]
> Ortamın sahibi olan Claude çalışma alanında oturum oluşturabilen herkes, Tuist hesabınızda oturum çalıştırabilir ve oturum metadata'sı aracılığıyla macOS ve onun Xcode'unu talep edebilir. Bu çalışma alanına erişimi buna göre sınırlayın.

### API anahtarı olmadan bağlanma {#managed-agents-federation}

Kontrol paneli bunu sizin için ayarlar. API üzerinden Tuist aynı şekilde çalışır: her hesabın Tuist'te kendi OpenID Connect yayıncısı vardır, `https://tuist.dev/oidc/accounts/<account id>`, ve Anthropic'e yapılan her çağrı için kısa ömürlü bir token imzalar; bu token, birkaç dakika geçerli olan bir Anthropic erişim token'ı ile değiştirilir. Yayıncınıza güvenen bir federasyon kuralı, Tuist'in diğer hesaplar için imzaladığı token'ları asla kabul etmez.

- Her agent ortamı yanıtı `federation_issuer_url` ve `federation_subject` (`account:123:agent-environment:456`) içerir. Konsolun Özel OIDC sihirbazında, yayıncı URL'sini ve ya yalnızca bu ortamı kabul etmek için tam olarak o subject'i ya da hesabın tüm ortamlarını kabul etmek için `account:123:*` kullanın. Kontrol panelinin kurulum kontrolleri, yalnızca ön ekin kabul ettiği `account:123:setup` subject'ini kullanır. `workspace:developer` kapsamını kullanın.
- Kuruluşu, çalışma alanını, hizmet hesabını ve kural ID'lerini oluşturma sırasında veya `PATCH /agent-environments/{id}` ile `anthropic_organization_id`, `anthropic_workspace_id`, `anthropic_service_account_id` ve `anthropic_federation_rule_id` olarak gönderin. Bir ortamda hem ID'ler hem de bir API anahtarı varsa, Tuist federasyon kullanır.

> [!NOTE]
> Anthropic, yayıncının anahtarlarını genel bir ana makine adından 443 portu üzerinden HTTPS ile alır. Kendi kendine barındırdığınız Tuist sunucunuz internetten erişilebilir değilse, Konsolda **satır içi** JWKS kaynağını seçin ve sunucunuzun `<issuer>/jwks.json` adresinde sunduğu anahtar kümesini yapıştırın. Tuist'in imzalama anahtarı değiştiğinde, yani sunucunun `TUIST_SECRET_KEY_TOKENS` (veya ayarlanmamışsa `TUIST_SECRET_KEY_BASE`) değeri değiştiğinde, bunu tekrar yapıştırın.

## Claude Code {#claude-code}

Claude Code bulut oturumları, geliştiricilerin [claude.ai/code](https://claude.ai/code), Claude masaüstü ve mobil uygulamaları ve `claude --cloud` üzerinden başlattıkları oturumlardır. Bir oturumun nerede çalışacağını ortamına göre seçerler, bu nedenle sunmak istediğiniz her platform için bir ortam bağlarsınız.

### Ortamları bağlama {#claude-code-connect}

1. Bir Claude kuruluşu Sahibi, [Bulut ortamları](https://claude.ai/admin-settings/cloud-environments) yönetici sayfasında **Kendi kendine barındırılan ortamlara izin ver** seçeneğini açar. Bunun için Team veya Enterprise planı gerekir; Anthropic'in [kendi kendine barındırılan ortamlar](https://code.claude.com/docs/en/self-hosted-environments) kılavuzuna bakın.
2. Aynı sayfada, geliştiricilerin göreceği isimle her platform için kendi kendine barındırılan bir ortam oluşturun, örneğin **Tuist Linux** ve **Tuist macOS**. Her ortamın `ccpool_…` ID'sini ve yalnızca bir kez gösterilen ortam anahtarını kopyalayın.
3. Her ortamı, `kind` değerini `claude_code` ve platformuna ayarlayarak Tuist hesabınıza bağlayın:

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

   `"platform": "linux"` ve diğer ortamın ID'si ve anahtarı ile tekrarlayın.

Bir dakika içinde ortamlar oturum almaya hazır hale gelir. Boşta kalan bir oturum sandbox'ını 30 dakika çalışır durumda tutar, ardından duraklatır; oturumun sonraki mesajı aynı sandbox'ı devam ettirir. Bekleme süresini `max_idle_seconds` ile değiştirin (maksimum 3600).

### Linux veya macOS seçme {#claude-code-choose}

Geliştiriciler, bir bulut oturumu başlattıklarında ortamı ve dolayısıyla platformu seçerler:

- **claude.ai, masaüstü ve mobil uygulamalar:** yeni bir oturumun ortam seçicisinde **Tuist Linux** veya **Tuist macOS** seçin.
- **Claude Code CLI:** `claude` içinde `/remote-env` komutunu çalıştırın ve ortamı adına göre seçin. `claude --cloud "<task>"` ardından onun üzerinde çalışır. Tek bir oturum için birini seçmek üzere ID'sini iletin: `claude --cloud "<task>" --environment ccpool_...`.
- **Tüm bir ekip veya depo:** Claude Code [ayarlarında](https://code.claude.com/docs/en/settings) varsayılan ortamın ID'sini ayarlayın, örneğin bir deponun `.claude/settings.json` dosyasında:

  ```json
  { "remote": { "defaultEnvironmentId": "ccpool_..." } }
  ```

Bu ortamlardaki oturumlar, kuruluşunuzun Claude Code kullanımını normal şekilde kullanır ve sandbox'ları Tuist hesabınıza yansır.

### Bir Xcode seçme {#xcode}

Her macOS ortamı bir <.localized_link href="/guides/features/sandboxes#xcode">Xcode</.localized_link> önyükler; `xcode_version` ile bağlamazsanız varsayılan olan kullanılır, örneğin `"xcode_version": "26.1.1"`. Birden fazlasını sunmak için her biri için bir ortam bağlayın ve adını buna göre verin, örneğin **Tuist macOS · Xcode 26.1.1**. Geliştiriciler daha sonra ortamı seçerek Xcode'u seçer.

Bir ortamı başka bir Xcode'a taşımak için onu güncelleyin:

```bash
curl -X PATCH "https://tuist.dev/api/accounts/my-org/sandboxes/agent-environments/<id>" \
  -H "Authorization: Bearer $TUIST_TOKEN" -H "Content-Type: application/json" \
  -d '{ "xcode_version": "27.0" }'
```

Yeni oturumlar yeni Xcode'u alır ve zaten sandbox'ı olan oturumlar kendi sandbox'larını korur. `null` varsayılana döner. Aynı kural, oturumları da [kendi seçimlerini yapabilen](#managed-agents-xcode) Yönetilen Agent ortamları için de geçerlidir.

### Daha hızlı oturum başlatma ve derlemeler {#claude-code-caching}

- **Tuist önbelleği:** oturumlar `TUIST_URL` alır ve hesabınız aynı rafta bir önbelleğe sahipse `TUIST_CACHE_ENDPOINT` alır. Oturumdaki Tuist CLI ve `tuist_ex` Mix görevleri, oturumun kimlik token'ı ile kendi kendilerine giriş yapar. Kimlik doğrulama kılavuzundaki <.localized_link href="/guides/server/authentication#claude-code-sessions">Claude Code oturumları</.localized_link> bölümüne bakın.
- **Önbelleğe alınmış checkout'lar:** hesabınızın Tuist GitHub uygulaması bir oturumun deposunu okuyabildiğinde, yeni bir oturum Tuist runner'larınızın kullandığı aynı önbelleğe alınmış checkout'tan başlar, böylece klonlamak yerine yalnızca eksik olduğu commit'leri çeker. Oturum sona erdiğinde, varsayılan dalın en son commit'inin nesnelerini geri verir; bu, Tuist'te CI çalıştırmayan depolar için bile önbelleğe alınmış checkout'un güncel kalmasını sağlar. Yalnızca GitHub'ın varsayılan dal için bildirdiği commit bunu günceller; bir oturumun kendi dalları bunu asla yapmaz. Bunu durdurmak için sandbox'ları devre dışı bırakın veya uygulamayı kaldırın.
- **macOS:** Mac, her VM ile çalışan Claude Code derleme oturumlarını paylaşır, bu nedenle yeni bir oturum onu indirmez.

## Herhangi bir Claude Code oturumundan Mac kullanma {#remote-mac}

Linux'ta çalışan Claude Code oturumları, Anthropic tarafından barındırılan bir ortamda bulut oturumları gibi, yine de <.localized_link href="/guides/features/sandboxes#coding-agents">Kodlama agent'ından Mac'te derleme</.localized_link> bölümünde açıklandığı gibi Tuist macOS sandbox'ında Apple platform kodunu derleyebilir ve test edebilir. Bir **Tuist macOS** ortamının aksine, oturum kendi ortamını korur.

Bir **Tuist Linux** ortamında kurulacak bir şey yoktur: Tuist CLI ve Tuist MCP sunucusu zaten yüklüdür ve oturumun kimliği ile giriş yapar.

Anthropic tarafından barındırılan bir ortamda bulut oturumları için:

1. Tuist <.localized_link href="/guides/features/agentic-coding/mcp">MCP sunucusunu</.localized_link> oturumlar için kullanılabilir hale getirin: claude.ai'de `https://tuist.dev/mcp` bağlantısını ekleyin ve oturum için etkinleştirin veya deponun commit edilmiş `.mcp.json` dosyasında bildirin.
2. Tuist CLI'yı ortamın [kurulum betiğine](https://code.claude.com/docs/en/cloud-environments#setup-scripts) yükleyin, örneğin `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist` ile.
3. <.localized_link href="/guides/server/authentication#account-tokens">Hesap token'ı</.localized_link> oluşturun ve `account:sandboxes:write` kapsamını verin, ardından bunu ortamın [ortam değişkenlerine](https://code.claude.com/docs/en/cloud-environments#set-environment-variables) `TUIST_TOKEN` olarak ekleyin. Ortamı kullanan herkes bunu okuyabilir, bu nedenle önbelleğinizi de kullanma yetkileri yoksa başka bir kapsam vermeyin: Mac'teki komutlar, token'ın sahip olduğu ölçüde <.localized_link href="/guides/features/sandboxes#tuist-in-sandbox">önbellek erişimi</.localized_link> alır; bu nedenle Mac'teki derlemelerin önbelleğinizi okuyup yazabilmesi için `ci` ekleyin.
4. Ortamın Tuist'e ulaşmasına izin verin. Anthropic'in varsayılan **Güvenilir** ağ erişimi `tuist.dev` içermez, bu nedenle **Özel** seçeneğini belirleyin, varsayılan alan adlarını koruyun ve `tuist.dev` öğesini **İzin verilen alan adları** listesine ekleyin. CLI, oturumun dosyalarını Mac'e `tuist.dev` üzerinden yükler, bu nedenle başka bir alan adına ihtiyaç duymaz.

Mac'te Tuist CLI yüklüdür ve mise aracılığıyla bir sürüm sabitlendiğinde projenin kendi sürümünü çalıştırır; Tuist 4.218.0 ve sonraki sürümler, her komutta hesabınızın önbelleğine kendi kendilerine giriş yapar.

### Hazır Mac'ler {#remote-mac-snapshots}

Bir **Tuist Linux** ortamı bu Mac'leri önceden hazırlayabilir. macOS kurulum betiğini API ile ayarlayın (`PATCH /api/accounts/{account}/sandboxes/agent-environments/{id}` üzerinde `macos_setup_script`), örneğin:

```bash
mise install
tuist install
tuist generate --no-open
xcodebuild build -workspace App.xcworkspace -scheme App -destination 'platform=iOS Simulator,name=iPhone 17'
```

Claude, Tuist projelerinizden birine bağlı bir depo için bir Mac oluşturduğunda, `create_sandbox` depoyu alır ve Mac, Xcode'u için o deponun anlık görüntüsünden başlar: varsayılan dal `~/work/<name>` konumuna klonlanır, betik orada çalıştırılır ve derleme ürünleri yerinde olur. İlk `tuist sandbox sync` yalnızca o commit'ten farklı olan dosyaları gönderir, böylece Xcode yalnızca değiştirdikleri şeyleri yeniden derler. Bir deponun ve Xcode'un ilk Mac'i boşta başlar ve ondan sonra gelen Mac'ler için, boşta kalan bir Mac üzerinde anlık görüntüsü en fazla bir saat içinde oluşturulur. Betiği, Xcode'u veya imajı değiştirmek onu yeniden oluşturur. Anlık görüntü, imajın simülatörlerini korur ve betiğin oluşturduklarını atar; bu Mac'lerin her biri çalışmaya başladığında imajın en yeni Pro iPhone'unu (Xcode 27.2'de iPhone 18 Pro) başlatmaya başlar, böylece ilk derleme bittiğinde hazır olur; betikte de bu simülatör için derleme yapın, böylece oturumun onun için yaptığı derlemeler anlık görüntüyü yeniden kullanır.

Claude, görev tamamlandığında Mac'i siler. Geride bırakılan bir Mac boşta kaldığında duraklatılır ve 14 gün duraklatıldıktan sonra silinir. Bu şekilde oluşturulan Mac'ler, diğer tüm sandbox'lar gibi Tuist hesabınıza sayılır.
