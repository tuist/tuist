---
{
  "title": "Model Context Protocol (MCP)",
  "titleTemplate": ":title · Ajan tabanlı kodlama · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist'in MCP uç noktası aracılığıyla AI ajanlarına test içgörülerine ve daha fazlasına erişim sağlayın."
}
---
# Model Context Protocol

[Model Context Protocol (MCP)](https://modelcontextprotocol.io/docs/getting-started/intro), yapay zeka ajanlarının harici hizmetler ve veri kaynaklarıyla etkileşime girmesini sağlayan açık bir standarttır. [Claude](https://claude.ai/), [Claude Code](https://docs.anthropic.com/en/docs/claude-code), [Codex](https://developers.openai.com/codex/) gibi uygulamaların ve [Zed](https://zed.dev), [Cursor](https://www.cursor.com) veya [Visual Studio Code](https://code.visualstudio.com) gibi düzenleyicilerin Tuist ile birlikte çalışabilir olmasını sağlar.

Tuist, sunucu tarafında bir Model Context Protocol uç noktasını `https://tuist.dev/mcp` adresinde barındırır. İstemcinizi bu uç noktaya bağlayarak ajanların test içgörülerini, kararsız test analizlerini ve daha fazlasını içeren Tuist proje verilerinize erişmesini sağlayabilirsiniz. Çoğu araç salt okunurdur ve kimliği doğrulanmış Tuist proje verileriyle sınırlıdır. Hesap kurulum araçları; kimliği doğrulanmış kullanıcının gerekli izinlere sahip olması durumunda hesapları listeleyebilir, organizasyonlar oluşturabilir, projeler oluşturabilir ve mevcut kullanıcıları organizasyonlara ekleyebilir. Her araç; salt okunur olup olmadığını, geri alınması zor bir değişikliğe neden olup olmayacağını ve genel İnternet durumunu değiştirip değiştiremeyeceğini belirten açıklamalar sunar. Hesap kurulum araçları kullanıcı kimlik doğrulaması gerektirir. Proje token’ları veya normal hesap token’ları için kullanılamazlar. Bir kullanıcı tarayıcıda bir istemciyi yetkilendirdiğinde veya bir `auth.md` kaydını talep ettiğinde, Tuist bu kimlik bilgisini yalnızca Model Context Protocol uç noktasında kullanıcıyla ilişkilendirir; böylece kurulum araçları istenen iş akışını tamamlayabilir.

Tuist, [2026-07-28 protokolünü](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http) uygular. İstekler durumsuzdur: istemciler her istekle birlikte protokol meta verilerini gönderir ve araçları başlatma olmadan doğrudan çağırabilir. `server/discover`, sunucunun kimliğini, yeteneklerini, desteklenen sürümleri ve talimatları döndürür. Oturum tanımlayıcıları veya bağımsız olay akışları yoktur. 2025-06-18 veya 2025-03-26 başlatma akışını kullanan istemciler desteklenmeye devam eder; bunlar da sunucu oturumları olmadan çalışır.

## Model Context Protocol ile beceriler arasındaki fark

Model Context Protocol araçları ile <.localized_link href="/guides/features/agentic-coding/skills">beceriler</.localized_link> yaptıkları işlevler açısından örtüşebilir. İkisi arasındaki mevcut örtüşme göz önüne alındığında, her iş akışı için tek bir yaklaşım seçin ve aynı akışta ikisini karıştırmak yerine tutarlı bir şekilde kullanın.

Eklenti yüklemeyi destekleyen istemciler için, ikisini birlikte yüklemek amacıyla <.localized_link href="/guides/features/agentic-coding/plugins">Tuist eklentilerini</.localized_link> kullanın.

## Yapılandırma

İstemcinize uzak bir Model Context Protocol sunucusu olarak `https://tuist.dev/mcp` ekleyin. Sunucunun başlatma talimatları ve genel sunucu kartı, dinamik istemci kaydı ile OAuth 2.0’ı ve standart tarayıcı yetkilendirme akışını satır içinde açıklar; ajanlardan harici kimlik doğrulama belgelerini getirmelerini veya takip etmelerini istemez. Bu sunucu çapındaki talimatlar, iş akışı rehberliğini genel tutar: araç kimlik doğrulaması, yerel komut satırı araçlarını veya derleme sistemi entegrasyonlarını kimlik doğrulamaz ve ajanlar istenen değişiklikleri ilgili Tuist araçları aracılığıyla doğrulamalıdır. Derleme sistemine özgü kurulum ve kimlik doğrulama kontrolleri entegrasyon kılavuzlarında ve prompt’larda belgelenmiştir. Tuist, hem [Open Authorization](https://oauth.net/2/) keşif meta verilerini hem de güncel [auth.md protokolünü](https://workos.com/auth-md) ayrı olarak `https://tuist.dev/auth.md` adresinde yayınlamaya devam eder.

Organizasyonlarınızdan biri tek oturum açmayı (SSO) zorunlu kılıyorsa, tarayıcıda bir istemciyi yetkilendirmek o organizasyon üzerinden oturum açılmış bir oturum gerektirir ve Tuist gerektiğinde sizi önce sağlayıcıya yönlendirir. Bkz. <.localized_link href="/guides/integrations/authentication/sso#choose-an-enrollment-policy">tek oturum açma</.localized_link>.

Uç nokta, daha eski oturum tabanlı yaşam döngüsünün yanı sıra durumsuz `2026-07-28` Model Context Protocol istek yaşam döngüsünü, `server/discover` dahil olmak üzere kabul eder. Mevcut istemciler mevcut bağlantı yöntemlerini kullanmaya devam edebilir.

Model Context Protocol olaylarını destekleyen istemciler proje olaylarına abone olabilir. Mevcut olay ve teslimat gereksinimleri için bkz. [Olaylar](#events).

Zaten uzaktan tarayıcı kimlik doğrulamasını destekleyen istemciler, tarayıcıda kimlik doğrulamaya devam edebilir. `auth.md` destekleyen istemciler ve ajanlar anonim olarak kayıt olabilir, güvenilir bir sağlayıcı kimlik iddiası sunabilir veya hizmet tarafından kimliği doğrulanmış bir e-posta talebi başlatabilir. Kayıt, Tuist tarafından imzalanmış bir kimlik iddiası döndürür; ajan bunu standart token uç noktasında bir saatlik erişim token’ı ile değiştirir. Tuist genel imzalama anahtarını yayınlar ve standart token iptalini ile sağlayıcı güvenlik olayı teslimatını destekler.

Kimliği doğrulanmamış bir ajan, Model Context Protocol uç noktasından döndürülen `WWW-Authenticate` başlığını okumalı, korunan kaynak meta verilerini getirmeli, yetkilendirme sunucusu meta verilerini getirmeli ve `agent_auth.skill` URL’sini takip etmelidir. Tuist ayrıca yetkisiz yanıt gövdesinde aynı yerel `auth_md` URL’sini döndürür; böylece dil modeli tabanlı istemciler, yerel bir istemci entegrasyonuna güvenmeden akışı keşfedebilir. Dağıtım yerel belgesi; uç nokta adları, istek gövdeleri, talep yoklaması ve iddia değişimi için geçerli kaynaktır.

Bir ajan e-posta talebini başlatmadan önce, kullanıcının Tuist hesabına ait e-posta adresini onaylamasını istemelidir. Bu adresi bir sağlayıcı profilinden, Git yapılandırmasından, ortam değişkeninden veya oturum meta verilerinden çıkarmamalıdır.

Uç nokta `mcp` kapsam grubunu kullanır. Anonim, talep öncesi bir kimlik bilgisi yetenekleri keşfedebilir ve genel entegrasyon rehberliğini okuyabilir ancak oturum açmış bir kullanıcı olarak değerlendirilmez. Tarayıcı yetkilendirmesinden veya talepten sonra kimlik bilgisi kullanıcı kapsamına alınır ve her araç, gösterge panelindekiyle aynı yetkilendirme kontrollerini uygular. Ayrıntılar için bkz. <.localized_link href="/guides/server/authentication#scope-groups">kapsam grupları belgeleri</.localized_link>.

Araçlar, kimliği doğrulanmış kullanıcının zaten okuyabildiği projelere çözülür. Xcode ve Gradle derleme araçları bir derleme UUID’sini veya gösterge paneli URL’sini kabul eder. UUID tam olarak bir projeyi tanımlamalıdır; birden fazla projede görünüyorsa araç, başka bir projenin raporunu seçmek yerine bulunamadı hatası döndürür. Proje kapsamlı gösterge paneli ve API okuma işlemleri kullanılmaya devam eder. Bildirilen aktör tanımlayıcıları doğrulanmamış etiketlerdir; kimlik bilgileri veya ek erişim hakları değildir.

Derleme listesi ve ayrıntı araçları, isteğe bağlı `tuist_version` meta verilerini sunar: Xcode ve Cargo için raporlayan Tuist CLI, Gradle için Tuist Gradle eklentisi ve Mix için `tuist_ex` kütüphanesi. Xcode ayrıca, yükleyen CLI’dan farklı olabilen bağlantılı proje oluşturma olayından `tuist_generation_version` değerini de sunar. Eksik gözlemler null olarak gelir; sunucudan veya başka bir rapordan çıkarılmaz. Bazel mevcut `bazel_version` değerini kullanır; Once çalıştırma ayrıntıları `once_version` değerini sunar. Bu alanlar bildirilen sürümleri tanımlar; doğrulanmış kimlik veya iletişim sözleşmesi sürümlerini değil. REST derleme uç noktaları aynı meta verileri sunar. Mevcut entegrasyon ve kararsız test yetenekleri sürüm alanlarına bağlı değildir ve iş akışı değişikliği gerektirmez.

Bir müşterinin hesabını inceleyen Tuist operatörleri bunu, her çağrıyı kaydeden Tuist’in dahili operasyon araçları aracılığıyla yapar; bu uç noktaya doğrudan bağlantı, kullanıcının kendi üyelikleri dışında hiçbir erişim sağlamaz.

### Pulse

Pulse, tümü `account_handle` ile adreslenen dört salt okunur aracı sunar:

| Araç | `/api/accounts/:account_handle/pulse` altındaki REST eşdeğeri |
| --- | --- |
| `query_pulse` | `GET /:signal` |
| `get_pulse_analytics` | `GET /:signal/analytics` |
| `get_pulse_error_issue` | `GET /errors/issues/:issue_id` |
| `get_pulse_error_event` | `GET /errors/issues/:issue_id/events/:event_id` |

Pulse, bir hesap veya proje herkese açık olsa bile sunucu tarafından yapılandırılan organizasyonun mevcut üyeleriyle sınırlıdır. Kullanıcı kimlik doğrulaması veya kullanıcı ilişkili bir `mcp` kimlik bilgisi ve hesap okuma yetkisi gerektirir. Proje token’ları, normal hesap token’ları, anonim kayıtlar ve organizasyon üyeliği olmayan operatör erişimi Pulse erişimi sağlamaz. Kimlik bilgileri başka bir arka uç veya telemetri kiracısı seçemez. Tarayıcı ajanları bu dört aracı yalnızca Pulse sayfalarında, o sayfanın hesap kapsamı içinde alır.

REST bir kullanıcı kimlik bilgisi gerektirir. OAuth ve `auth.md` kullanıcı ilişkilendirmeleri yalnızca `/mcp` uç noktasında kullanılabilir; ilişkili hesabın üyeliği veya görünürlüğünden bağımsız olarak, geçerli bir kullanıcı içermeyen bir hesap kimlik bilgisi reddedilir.

`query_pulse`, `signal` (`metrics`, `logs`, `traces` veya `errors`), isteğe bağlı bir `query` ve `range` (`15m`, `1h`, `6h` veya `24h`, varsayılan `1h`) parametrelerini alır. Metrikler, günlükler ve izler yerel PromQL, LogQL ve TraceQL ifadelerini kabul eder. Hatalar gruplandırılmış sorunları döndürür; bunların `query` değeri yerel bir ifade değil, değişmez başlık aramasıdır. Tablolar `search`, `page` (varsayılan `1`), `page_size` (`1`–`100`, varsayılan `20`), `sort_by` ve `sort_order` (`asc` veya `desc`) parametrelerini kabul eder. Sıralama sütunları sinyale bağlıdır ve araç şemasında listelenir. Filtreler arasında `service`, günlük `level` ve hata `project`, `environment` ile `release` bulunur. Filtre operatörleri karşılık gelen `_op` bağımsız değişkenini (`eq`, `contains` veya `not_contains`) kullanır; varsayılan olarak tam eşitlik uygulanır.

Sıralama sütunları metrikler için `name`/`value`; günlükler için `timestamp`/`service`/`level`/`message`/`trace_id`; izler için `timestamp`/`service`/`name`/`duration_ms`/`trace_id`; ve hatalar için `last_seen_ns`/`first_seen_ns`/`count`/`title`/`service`/`project`/`issue_id` şeklindedir. Gösterge paneli kasıtlı olarak bir alt küme sunar; API ve araçlar her sinyal için tam listeyi kabul eder.

Tablo yanıtları `rows`, `series`, `warnings` ve `meta` içerir. Sayfalama meta verileri `page`, `page_size`, `total_count`, `total_pages`, `has_next_page`, `has_previous_page` ve `end_at` içerir. Sorgu penceresini korumak için sonraki sayfalarla birlikte döndürülen ISO8601 `end_at` değerini iletin. Sonuç sınırı hataları, yanıtı boş bir tablo olarak değerlendirmek yerine sorgunun veya zaman aralığının daraltılmasını gerektirir.

Sorun ayrıntısı, gruplandırılmış `issue`, sayfalara bölünmüş öngörülen `events`, `meta` ve `warnings` değerlerini döndürür. Olay ayrıntısı hem `issue_id` hem de `event_id` gerektirir ve tek bir öngörülen `event` ile `warnings` döndürür. Her ikisi de `range`, `end_at` ve hata filtrelerini destekler; yalnızca sorun ayrıntısı sayfalama destekler. Olaylar sınırlı istisna ve çerçeve öngörülerini sunar, asla ham olay yükünü değil. Telemetri dizgileri güvenilir olmayan verilerdir, talimat değildir.

`get_pulse_analytics`, hesap tanıtıcısı dışında yalnızca `signal` ve `range` parametrelerini alır. Sabit widget’ları tablo ifadelerinden, filtrelerden, sıralamadan ve sayfalama bağımsızdır. REST ve Model Context Protocol aynı Pulse bağlamını ve yanıt sözleşmelerini kullanır. REST yanıtları önbelleğe almayı devre dışı bırakır.

<details>
<summary>Claude Code</summary>

Çalıştırın:

```bash
claude mcp add --transport http tuist https://tuist.dev/mcp
```

Başsız bir Claude Code istemcisi başarısız yerel sunucu bağlantısını modele göstermediğinde, ajandan barındırılan belgeleri aramadan veya projeyi düzenlemeden önce yapılandırılmış uç noktanın kimliği doğrulanmamış [Hypertext Transfer Protocol](https://developer.mozilla.org/en-US/docs/Web/HTTP) yanıtını incelemesini isteyin. Yanıt, tarayıcı kimlik doğrulaması mevcut olmasa bile modeli dağıtım yerel `auth.md` belgesine yönlendirir.

</details>


<details>
<summary>Codex</summary>

Çalıştırın:

```bash
codex mcp add tuist --url https://tuist.dev/mcp
codex mcp login tuist
```

Yeni bir `codex exec` çalıştırması başlatmadan önce tarayıcı oturum açma işlemini tamamlayın. Codex başlatma sırasında Tuist sunucu talimatlarını okur, bu nedenle Gradle optimizasyon istekleri otomatik olarak kimlik doğrulama ve doğrulama iş akışını alır.

</details>


<details>
<summary>Claude Desktop</summary>

**Ayarlar → Bağlayıcılar → Özel bağlayıcı ekle** seçeneğini açın, ardından ayarlayın:

- **Ad:** `tuist`
- **URL:** `https://tuist.dev/mcp`

İstendiğinde tarayıcıda [Open Authorization](https://oauth.net/2/) işlemini tamamlayın.

</details>


<details>
<summary>Pi</summary>

Pi bir Model Context Protocol istemcisi içermez. Kaynağını ve güvenlik etkilerini inceledikten sonra üçüncü taraf [`pi-mcp-adapter`](https://pi.dev/packages/pi-mcp-adapter) uzantısını kurabilirsiniz:

```bash
pi install npm:pi-mcp-adapter
```

Proje düzeyinde bir `.mcp.json` dosyası ekleyin:

```json
{
  "mcpServers": {
    "tuist": {
      "url": "https://tuist.dev/mcp",
      "auth": false
    }
  }
}
```

`auth` değerini `false` olarak ayarlamak, adaptörün tarayıcı kimlik doğrulama işleyicisinin Tuist’in yetkisiz yanıtını gizlemesini engeller. Başsız bir ajan daha sonra döndürülen `auth_md` URL’sini okuyabilir ve Tuist’in kayıt, kimlik iddiası değişimi ve talep yoklama akışını takip edebilir. Değiştirilen erişim token’ını bearer token olarak yapılandırın veya ajanın doğrudan kimliği doğrulanmış Model Context Protocol çağrıları yapmasına izin verin.

Tarayıcı kimlik doğrulamasını tercih ediyorsanız, `auth` değerini `"oauth"` olarak ayarlayın. Bu akış için, kimlik doğrulama tamamlanırken Pi’nin [uzaktan yordam çağrısı modu](https://pi.dev/docs/latest/rpc) ile bir işlemi canlı tutun:

```bash
pi --mode rpc
```

Bekleyen bir tarayıcı kimlik doğrulamasını ayrı `pi --print` çağrılarına bölmeyin çünkü geri arama durumuna sahip olan süreç çıkmıştır.

</details>


<details>
<summary>OpenCode</summary>

Tuist Model Context Protocol sunucusunu `opencode.json` dosyasına ekleyin:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "tuist": {
      "type": "remote",
      "url": "https://tuist.dev/mcp"
    }
  }
}
```

Ardından sunucuyu kimlik doğrulayın:

```bash
opencode mcp auth tuist
```

</details>


<details>
<summary>Cursor</summary>

**Cursor Ayarları → Araçlar ve Entegrasyonlar → Model Context Protocol Araçları** seçeneğini açın ve ekleyin:

- **Ad:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>


<details>
<summary>Visual Studio Code</summary>

**Komut Paleti → MCP: Sunucu Ekle** seçeneğini kullanın, ardından şu özelliklere sahip bir [Hypertext Transfer Protocol](https://developer.mozilla.org/en-US/docs/Web/HTTP) sunucusu yapılandırın:

- **Ad:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>


<details>
<summary>Zed</summary>

**Ajan paneli → Ayarlar → Özel Sunucu Ekle** seçeneğini açın, ardından ayarlayın:

- **Ad:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>

Ajanınız `auth.md` destekliyorsa, tarayıcı açmadan anonim olarak başlayabilir. Güvenilen bir sağlayıcı kimliği zaten bağlıysa, tarayıcı olmadan da işlem tamamlanabilir. Hizmetle kimliği doğrulanmış e-posta, anonim talep veya ilk sağlayıcı bağlantısı için ajan size bir Tuist doğrulama bağlantısı ve altı haneli bir kod gösterir. Bağlantıyı açın, oturum açın ve Tuist sayfasında ajanın kodunu girin. Kodu asla ajana geri göndermeyin. Tuist’in yetkilendirme sunucusu meta verileri, doğrudan dağıtımın kendi `/auth.md` adresine işaret eder; bu adres tam istek ve yoklama yapılarını içerir.

## WebMCP

[WebMCP](https://webmachinelearning.github.io/webmcp) destekleyen tarayıcılarda, Tuist sayfaları araçları `document.modelContext` ile kaydeder, böylece tarayıcıya yerleşik ajanlar bunları ek yapılandırma olmadan çağırabilir. Çağrılar Tuist sunucusunda çalışır.

- **Web sitesi ve dokümantasyon sayfaları**, dokümantasyon ve kaynak araçlarını (`search_tuist`, `search_tuist_code`, `list_tuist_files` ve `read_tuist_file`) kaydeder. Oturum açmanıza gerek yoktur.
- **Bir hesabın kontrol paneli sayfaları**, oturum açtığınızda o hesap için Tuist’in salt okunur araçlarını kaydeder. Her sayfa yalnızca gösterdiği içeriğe, projenin derleme sistemine uygun araçları kaydeder: bir Gradle projesinin derlemeler sayfası Gradle derleme araçlarını, test sayfaları test ve kapsam araçlarını, çalışanlar sayfaları çalışan araçlarını ve sandbox’lar sayfaları sandbox araçlarını alır. Kişisel hesabınızın AI ayarları sayfasındaki Abonelikler bölümü `list_ai_subscriptions` alır; bu yalnızca kendi hesabınızla ilgili soruları yanıtlar. Her sayfa ayrıca dokümantasyon araçlarını, `list_projects` ve `get_project` alır. Araçlar oturum açmış kullanıcı olarak çalışır, bu nedenle yalnızca kontrol panelinde okuyabileceğiniz verilere ve yalnızca baktığınız hesaba erişirler. Başka bir sayfaya veya hesaba geçtiğinizde araçlar o sayfanın araçlarıyla değiştirilir.

Veri oluşturan, değiştiren veya silen araçlar WebMCP üzerinden kullanılamaz çünkü tarayıcı ajanı araçları sizin eklemeniz olmadan alır ve derlemeler ile testlerin ürettiği içeriği okur. Bu araçları kullanmak için bir MCP istemcisini `/mcp` uç noktasına bağlayın.

Kuruluş tek oturum açmayı zorunlu kılıyorsa, araçlarını kullanmak için sağlayıcısıyla kontrol panelinde oturum açın.

## Derleme sistemi entegrasyonları iki kimlik bilgisi kullanır

Model Context Protocol araçları için kullanılan kimlik bilgisi, Gradle eklentisini veya Bazel’in uzaktan hizmetlerini kimlik doğrulamaz. Bir ajan bir Gradle veya Bazel entegrasyonunu düzenlemeden veya doğrulamadan önce şunu çalıştırmalıdır:

```bash
tuist auth whoami --url https://tuist.dev
```

Bu komut kimlik doğrulaması yapmamışsa, ajan durmalı ve kullanıcıdan şunu çalıştırmasını istemelidir:

```bash
tuist auth login --url https://tuist.dev
```

Yerel veya kendi kendine barındırılan bir dağıtım için, her iki komuttaki ve `tuist.toml` içindeki URL’yi değiştirin. Ana bilgisayar adının yazımını her yerde aynı tutun. Örneğin, `localhost` ve `127.0.0.1` ayrı saklanan kimlik bilgilerini kullanır.


## Yetenekler

### Araçlar

Aşağıdaki araçlar Tuist Model Context Protocol sunucusu üzerinden kullanılabilir:

Her araç, açık giriş ve çıkış şemalarıyla birlikte insan tarafından okunabilir bir açıklama yayımlar. Başarılı çağrılar, ilan edilen çıkış şemasına uyan yapılandırılmış içerik döndürür ve ayrıca yapılandırılmış içeriği henüz tüketmeyen istemciler için metin olarak serileştirilmiş aynı sonucu içerir.

Tek bir kaydın tanımlayıcısını alan araçlar, örneğin `build_run_id`, `test_run_id`, `test_case_id`, `bundle_id`, `run_id`, `generation_id` veya `cache_run_id`, o kaydın Tuist kontrol paneli URL’sini de kabul eder. Tanımlayıcıyı ayıklamak yerine URL’yi doğrudan tarayıcıdan yapıştırın.

#### Dokümantasyon ve topluluk araması

Bu salt okunur araç, Tuist’in dokümantasyonunu, [application programming interface](https://en.wikipedia.org/wiki/API) referansını, GitHub sürümlerini, topluluk forumunu ve GitHub sorunlarını dokümantasyon web sitesine güç veren aynı arama motoru üzerinden arar. Sürüm sonuçları ürünü, sürümü, yayın tarihini ve ön sürüm durumunu içerir. Varsayılan olarak kararlı sürümler aranır ve ön sürümler `include_prereleases` ile dahil edilebilir. Araç yalnızca `https://tuist.dev/mcp` adresindeki Tuist tarafından barındırılan sunucuda kullanılabilir.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `search_tuist` | Genel Tuist dokümantasyonunu, application programming interface referansını, GitHub sürümlerini, topluluk tartışmalarını ve GitHub sorunlarını arayın. İsteğe bağlı olarak tek bir `source` ile sınırlayın (`docs`, `api_reference`, `releases`, `forum`, `issues`). | `query` |

#### Geri bildirim

Ajanlar, bir Tuist aracının veya isteminin bekledikleri gibi çalışmadığında (kafa karıştırıcı bir sonuç, hata, eksik veri veya eksik yetenek gibi) Tuist ekibine bildirebilir. Ajanlardan bir rapor önermeleri ve yalnızca siz onayladıktan sonra göndermeleri istenir. Her rapor, Tuist desteğiyle bir konuşma başlatır; destek ekibi size e-posta ile yanıt verebilir. Bir rapor, ajanın ne beklediğini, ne olduğunu, isteğe bağlı bir öneriyi, Tuist kullanıcı kimliğinizi, kullanıcı adınızı ve e-postanızı ile ait olduğunuz kuruluşları içerir. Ajanlar ayrıca sorunun yaşandığı hesabı ve projeyi belirtebilir, böylece ekip hangi kuruluşla iletişime geçeceğini bilir; yalnızca ait olduğunuz hesaplar kabul edilir. Yalnızca Tuist kullanıcısı olarak oturum açmış ajanlar rapor gönderebilir ve her kullanıcı saatte en fazla 10 rapor açabilir. Araç yalnızca `https://tuist.dev/mcp` adresindeki Tuist tarafından barındırılan sunucuda kullanılabilir.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `report_feedback` | Bir Tuist aracı veya istemiyle ilgili bir sorunu bildirin. İsteğe bağlı olarak `tool_name`, gerçekleştiği `account_handle` ve `project_handle` belirtin ve bir `suggestion` ekleyin. | `category`, `expected`, `actual` |

#### Kaynak destekli yanıtlar

Bu salt okunur araçlar, ajanların mevcut davranışa dayalı yanıtlar için gerçek kaynağı olarak barındırılan sunucuyla birlikte dağıtılan tam genel Tuist kaynak revizyonunu kullanmasına olanak tanır. Yalnızca `https://tuist.dev/mcp` adresinde kullanılabilirler.

Uyumlu istemciler, başlatma sırasında satır içi OAuth kimlik doğrulama bilgilerinin yanı sıra araçların kaynak revizyonu, bağlantıları ve sonuç sınırları hakkında olgusal açıklamalar alır. Bu açıklamalar yanıt stilini veya bir doğrulama iş akışını dikte etmez. Kullanıcılar, önce `ask_tuist` istemini çağırmadan doğrudan soru sorabilir; istem, açık kaynak destekli bir iş akışı için kullanılmaya hazır kalır.

Her işlemin eşzamanlılık, süre, gezinme, okunan bayt ve yanıt boyutu için sabit sınırları vardır. Arama ve listeleme sonuçları `truncated` ve `truncation_reason` alanlarını içerir. Bir sonuç kesildiğinde, sonucu kapsamlı olarak değerlendirmek yerine yolu, dosya desenini veya arama terimini daraltın.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `search_tuist_code` | Kaynak dosyaları arayarak mevcut davranış, varsayılanlar, yapılandırma, özellik kapıları, hata yönetimi veya belgelenmemiş ayrıntılar hakkındaki soruları yanıtlayın. Sonuçlar çevreleyen satırları, revizyon sabitli kaynak bağlantılarını ve tarama istatistiklerini içerir. | `pattern` |
| `list_tuist_files` | İlgili yol bilinmediğinde bir kaynak alt sistemini veya yakındaki testleri keşfedin. Listelemelerin derinliği ve sonuç sayıları sınırlıdır. | Yok |
| `read_tuist_file` | İlgili yolu bulduktan sonra bir uygulama dosyasındaki, çağrı noktasındaki veya testteki belirli bir satır aralığını inceleyin. Kesilmiş yanıtlar devam için `next_start_line` sağlar. | `path` |

#### Projeler

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_accounts` | Kimliği doğrulanmış kullanıcının erişebileceği kişisel ve organizasyon hesap tanıtıcılarını, her hesabın proje oluşturup oluşturamayacağı dahil olmak üzere listeler. | Yok |
| `get_organization` | Bir organizasyonun üye dizinini alın. Bekleyen davetler, kontrol panelindekiyle aynı yönetici iznini gerektirir; davet kabul belirteçleri asla döndürülmez. | `account_handle` |
| `create_organization` | Kimliği doğrulanmış kullanıcı için bir Tuist organizasyonu oluşturun. | `handle` |
| `create_project` | Kimliği doğrulanmış kullanıcının erişebileceği bir hesap altında bir Tuist projesi oluşturun. | `account_handle`, `project_handle` |
| `add_organization_member` | Mevcut bir Tuist kullanıcısını bir organizasyona ekleyin veya mevcut bir üyenin rolünü güncelleyin. `user` (varsayılan), `admin` veya `viewer` kabul eder; burada görüntüleyici kontrol panellerini ve çalıştırmaları okuyabilir ancak hiçbir şeyi değiştiremez. | `organization_handle`, `email` |
| `invite_organization_member` | Bir e-posta adresini, mevcut bir Tuist kullanıcısına ait olup olmadığına bakmaksızın bir organizasyona davet edin. Tuist, 14 gün sonra sona eren bir kabul bağlantısı e-postası gönderir; sunucu e-posta gönderemediğinde `email_sent` değeri `false` olur ve bağlantının kontrol panelinden kopyalanması gerekir. `user` (varsayılan), `admin` veya `viewer` kabul eder. Organizasyon yöneticisi izni gerektirir. | `organization_handle`, `email` |
| `cancel_organization_invitation` | Bekleyen bir organizasyon davetini iptal edin, böylece bağlantısı artık kabul edilemez. Organizasyon yöneticisi izni gerektirir. | `organization_handle`, `email` |
| `list_projects` | Kimliği doğrulanmış kullanıcının erişebileceği tüm projeleri listeler. | Yok |
| `get_project` | Bir projenin yapılandırmasını ve bağlı depo URL'sini alın. | `account_handle`, `project_handle` |
| `connect_project_repository` | Bir projeyi, hesabın GitHub Uygulaması kurulumunun erişebileceği bir GitHub deposuna bağlayın. Proje, deponun varsayılan dalını benimser. Proje yöneticisi izni gerektirir. | `account_handle`, `project_handle`, `repository_full_handle` |
| `disconnect_project_repository` | Bir projenin GitHub deposuna olan bağlantısını kaldırın. Proje yöneticisi izni gerektirir. | `account_handle`, `project_handle` |

#### Hesap belirteçleri

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_account_tokens` | Belirteç değerlerini açığa çıkarmadan hesap belirteci meta verilerini listeler. | `account_handle` |
| `get_account_token` | Değerini açığa çıkarmadan hesap belirteci meta verilerini alır. | `account_handle`, `token_id` |
| `list_project_tokens` | Belirteç değerlerini açığa çıkarmadan proje belirteci meta verilerini listeler. | `account_handle`, `project_handle` |

#### AI abonelikleri

Bu araçlar, kimliği doğrulanmış kullanıcının konular gibi AI özellikleri için kendi Claude ve ChatGPT aboneliklerini yönetir. Kullanıcı kimlik doğrulaması ve AI özelliklerine erişim gerektirirler ve yalnızca bağlantı meta verilerini döndürürler, asla kimlik bilgilerini döndürmezler. Bağlantıyı kesmek kaydedilen kimlik bilgilerini siler ancak sağlayıcıdaki yetkilendirmeyi iptal etmez.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_ai_subscriptions` | Her aboneliğin bağlı olup olmadığını ve sunucunun onu bağlayıp bağlayamayacağını listeler. | Yok |
| `connect_claude_subscription` | `claude setup-token` tarafından yazdırılan abonelik belirtecini kaydedin. Belirteç, istemci ve model üzerinden geçen bir sırdır, bu nedenle yalnızca açıkça sağlayın; bunu kontrol panelinin AI ayarlarına yapıştırmak, konuşmanın dışında tutar. | `token` |
| `start_chatgpt_subscription_login` | Bir OpenAI cihaz oturum açma işlemini başlatın ve kullanıcının oraya girdiği doğrulama URL'sini ve kodunu artı bir `login_id` döndürün. 15 dakika sonra sona erer. | Yok |
| `poll_chatgpt_subscription_login` | Bekleyen bir oturum açma işlemini kontrol edin: Kullanıcı kodu onaylayana kadar `pending`, ardından `connected`. | `login_id` |
| `cancel_chatgpt_subscription_login` | Bekleyen bir oturum açma işlemini iptal edin. Bağlı bir abonelik bağlı kalır. | `login_id` |
| `disconnect_ai_subscription` | Bir aboneliğin kaydedilen kimlik bilgilerini ve varsa bekleyen oturum açma işlemlerini silin. | `provider` |

#### Bildirim kuralları

Bu araçlar, kimliği doğrulanmış kullanıcının kendi bildirim kurallarını yönetir: Kuralın projelerinde (veya hiçbirini listelemediğinde hakkında bildirim alabileceğiniz herhangi bir projede) yeni bir önizleme gibi bir olay gerçekleştiğinde ve koşullarını karşıladığında, Tuist uygulama cihazlarınıza gönderilen anlık bildirim gibi eylemlerini çalıştırır. Kurallar olmadan bildirim almazsınız. Kullanıcı kimlik doğrulaması gerektirirler, yalnızca kendi kurallarınız üzerinde işlem yaparlar ve yalnızca ait olduğunuz hesaplara ait projeleri kabul ederler. Kurallar tüm hesaplarınızı kapsadığından kontrol paneli sayfalarında sunulmazlar.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_notification_events` | Kuralların abone olabileceği olay türlerini, her biri için koşullarına ait bir JSON Şemasıyla birlikte listeler. | Yok |
| `list_notification_condition_options` | Bir projedeki bir olay için koşul değerleri önerir; örneğin, son önizlemelerinin dalları ve kolları. | `event`, `account_handle`, `project_handle` |
| `list_notification_rules` | Kurallarınızı listeler. | Yok |
| `create_notification_rule` | Bir olaydan, isteğe bağlı projelerden ve koşullardan ve en az bir eylemden oluşan bir kural oluşturur. | `event`, `actions` |
| `update_notification_rule` | Bir kuralın etkin durumunu, projelerini, koşullarını veya eylemlerini değiştirir. | `rule_id` |
| `delete_notification_rule` | Bir kuralı siler. | `rule_id` |

#### Sürekli entegrasyon çalıştırıcıları

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_runner_jobs` | Bir hesap için sürekli entegrasyon çalıştırıcı işlerini listeler. | `account_handle` |
| `get_runner_job` | Bir sürekli entegrasyon çalıştırıcı işini alır. | `account_handle`, `workflow_job_id` |
| `list_runner_job_steps` | Bir sürekli entegrasyon çalıştırıcı işi için kaydedilen adımları listeler. | `account_handle`, `workflow_job_id` |
| `list_runner_job_metrics` | Bir sürekli entegrasyon çalıştırıcı işi için kaydedilen makine metriklerini listeler. | `account_handle`, `workflow_job_id` |
| `list_runner_job_logs` | Bir sürekli entegrasyon çalıştırıcı işi için yakalanan en fazla 500 günlük satırını listeler. | `account_handle`, `workflow_job_id` |
| `list_runner_workflows` | Bir hesap için sürekli entegrasyon iş akışı özetlerini listeler. | `account_handle` |
| `list_runner_profiles` | Bir hesap için sürekli entegrasyon çalıştırıcı profillerini, her birinin `runs-on` etiketiyle birlikte listeler. | `account_handle` |
| `get_runner_catalog` | Bir çalıştırıcı profilinin kullanabileceği makine şekillerini ve Xcode sürümlerini listeler. | `account_handle` |
| `create_runner_profile` | Bir platform, bir makine şekli ve macOS'ta bir Xcode sürümü ile bir çalıştırıcı profili oluşturur. İsteğe bağlı olarak hangi dalların önbellek birimlerini kaydedeceğini ayarlayabilirsiniz. Hesap yönetimi veya `account:runners:write` kapsamı gerektirir. | `account_handle`, `name`, `platform`, `vcpus`, `memory_gb` |
| `update_runner_profile` | Bir çalıştırıcı profilinin makine şeklini, Xcode sürümünü veya özel önbellek birimi değişikliklerini hangi dalların kaydedeceğini değiştirir. Atlanmış alanlar değerlerini korur. Hesap yönetimi veya `account:runners:write` kapsamı gerektirir. | `account_handle`, `profile_name` |
| `delete_runner_profile` | Kullanıcı onayından sonra bir çalıştırıcı profilini siler. Varsayılan profiller silinemez. Hesap yönetimi veya `account:runners:write` kapsamı gerektirir. | `account_handle`, `profile_name` |

Çalıştırıcı birim araçları, Birimler kontrol panelindekiyle aynı verileri ortaya çıkarır. Okuma araçları çalıştırıcı erişimi gerektirir; temizleme işlemi hesap yönetimi veya `account:runners:write` kapsamı ve kullanıcı onayı gerektirir.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_runner_volumes` | Ada ve depoya göre filtreleyin, birimleri sıralayın ve sayfalara bölün. | `account_handle` |
| `get_runner_volume` | Depo, platform, kapasite, kullanılan alan ve son kullanım. | `account_handle`, `volume_id` |
| `list_runner_volume_jobs` | Sayfalanmış iş ve iş akışı referansları, önbellek durumu, isabet sonucu ve bağlama zamanı. | `account_handle`, `volume_id` |
| `list_runner_job_volumes` | Bir iş tarafından bağlanan birimler. | `account_handle`, `workflow_job_id` |
| `get_runner_volume_analytics` | Depolama serileri, iş çalıştırmaları, isabet oranı ve trendler. İsteğe bağlı `volume_id`, `start` ve `end` (ISO 8601); varsayılan yedi gün, maksimum 90. | `account_handle` |
| `delete_runner_volume` | Bir birimi ve kaydedilen içeriğini siler. Çalışan işler kendi özel kopyalarını tutar ancak bunları kaydedemez; aynı anahtara sahip sonraki işler boş başlar. | `account_handle`, `volume_id` |

Listeler `page` ve `page_size` (en fazla 100) kabul eder. Birim envanteri ayrıca `name` ve `repository` (tam eşleşmeler, AND ile birleştirilmiş), `sort_by` (`volume`, `repository`, `used_space`, `capacity`, `last_used`) ve `sort_order` (`asc`, `desc`) kabul eder. Bilinmeyen ölçümler ve isabet sonuçları `null` olarak kalır. Önbellek durumu, iş başarısını değil, birim değişikliklerinin kaydedilip kaydedilmediğini açıklar.

#### Kum Havuzları

Kum havuzu araçları, Kum Havuzları kontrol panelindekiyle aynı verileri ve eylemleri ortaya çıkarır. Kum havuzları rastgele komutlar çalıştırdığından, salt okunur olanlar dahil her araç hesap yönetimi gerektirir ve hesabın kum havuzlarının etkinleştirilmiş olması gerekir. Kontrol panelinin kum havuzu sayfaları salt okunur araçları kaydeder.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_sandboxes` | Kum havuzlarını durumları, şekilleri ve zaman damgalarıyla sayfalara bölün. İsteğe bağlı `search` (kum havuzundaki metin, Amp Orb veya Anthropic oturum kimliği), `status`, `vcpus`, `sort_by` (`created`, `last_active`, `identifier`) ve `sort_order`. | `account_handle` |
| `get_sandbox` | Bir kum havuzunun durumu, şekli, düğümü, arşivi ve zaman damgaları. | `account_handle`, `sandbox_id` |
| `get_sandbox_analytics` | vCPU-saatleri, oluşturulan kum havuzları, oturum, kurulum ve başlama süresi süreleri ve hesabın limitlerine göre tepe vCPU'lar, bellek ve disk, trendlerle birlikte. İsteğe bağlı `start` ve `end` (ISO 8601); varsayılan 30 gün, maksimum 90. | `account_handle` |
| `create_sandbox` | Boş bir kum havuzunu başlatın ve çalıştığında geri döndürün. İsteğe bağlı `platform` (`linux` veya `darwin`), `template`, `vcpus` ile `memory_mb` (Linux: 2x4096, 4x8192 veya 8x16384, varsayılan 2x4096; macOS: 8x8192, 8x16384 veya 8x24576, varsayılan 8x8192) ve `workspace_gb`. | `account_handle` |
| `pause_sandbox` | Çalışan bir kum havuzunun anlık görüntüsünü düğümünün diskine alır. | `account_handle`, `sandbox_id` |
| `resume_sandbox` | Duraklatılmış veya arşivlenmiş bir kum havuzunu devam ettirir. | `account_handle`, `sandbox_id` |
| `archive_sandbox` | Duraklatılmış bir kum havuzunun disklerini nesne depolamaya taşımayı sıraya alır. | `account_handle`, `sandbox_id` |
| `delete_sandbox` | Kullanıcı onayından sonra bir kum havuzunu ve disklerini siler. | `account_handle`, `sandbox_id` |

#### Web Kancaları

Web kanca araçları, kontrol panelindekiyle aynı yalnızca yönetici iznini kullanır. Teslimat denemeleri, uç nokta için kaydedilen istek ve yanıt verilerini içerir, ancak asla uç nokta imzalama gizli anahtarını içermez.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_webhook_endpoints` | Bir hesap için web kanca uç noktalarını listeler. | `account_handle` |
| `get_webhook_endpoint` | Bir web kanca uç noktasını alır. | `account_handle`, `webhook_endpoint_id` |
| `list_webhook_delivery_attempts` | Bir uç nokta için teslimat denemelerini listeler. | `account_handle`, `webhook_endpoint_id` |
| `get_webhook_delivery_attempt` | Bir teslimat denemesini alır. | `account_handle`, `webhook_endpoint_id`, `delivery_attempt_id` |

#### Xcode derlemeleri

Xcode, Gradle, Bazel, Mix ve Cargo için derleme ayrıntı araçları, mevcut `custom_metadata: {tags, values}` yapısını, raporlandığında altyapı gözlemleri dahil olmak üzere ortaya çıkarır. Değerler dize olarak kalır ve bilinmeyen anahtarlar korunur. Örneğin, `tuist.cpu.available_processors` çalışma zamanında kullanılabilir mantıksal işlemcileri tanımlarken, `tuist.gradle.max_workers` bir Gradle çalışan limiti ve `tuist.jvm.max_heap_bytes` bir JVM yığın limitidir, ana makine belleği değildir. Bunlar güvenilmeyen istemci gözlemleridir, doğrulanmış çalıştırıcı kimlikleri değildir. Eksik gözlemler eksik kalır; içe aktarılan günlükler ve eski istemcilerde altyapı meta verileri olmayabilir. Meta veri, koordineli bir istemci/protokol güncellemesini beklemektedir.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_xcode_builds` | Bir proje için Xcode derleme çalıştırmalarını listeler. | `account_handle`, `project_handle` |
| `get_xcode_build` | Ham `.xcactivitylog` dosyasını içeren arşiv için geçici bir indirme URL'si dahil olmak üzere belirli bir Xcode derleme çalıştırması hakkında ayrıntılı bilgi alır. | `build_run_id` |
| `list_xcode_build_targets` | Belirli bir Xcode derleme çalıştırması için derleme hedeflerini listeler. | `build_run_id` |
| `list_xcode_build_files` | Belirli bir Xcode derleme çalıştırması için derlenen dosyaları listeler. | `build_run_id` |
| `list_xcode_build_steps` | Günlük metni olmadan, zamanlamalar ve sonuçlarla kaydedilen derleme adımlarını listeler. | `build_run_id` |
| `get_xcode_build_step` | Günlüğü ve kesme bayrağı dahil olmak üzere tek bir kaydedilmiş derleme adımını alır. | `build_run_id`, `step_id` |
| `list_xcode_build_issues` | Belirli bir derleme çalıştırması için derleme sorunlarını (uyarılar ve hatalar) listeler. | `build_run_id` |
| `list_xcode_build_cache_tasks` | Belirli bir Xcode derleme çalıştırması için önbelleklenebilir görevleri (önbellek isabetleri/ıska) listeler. | `build_run_id` |
| `list_xcode_build_cas_outputs` | Belirli bir Xcode derleme çalıştırması için [içerik adreslenebilir depolama](https://en.wikipedia.org/wiki/Content-addressable_storage) çıktılarını listeler. | `build_run_id` |

`list_xcode_build_steps` varsayılan olarak 20 adımlık sayfalar döndürür (`page_size` ile maksimum 100), gezinme için `page` ve `pagination_metadata` ile birlikte. Başlıkları, projeleri veya hedefleri eşleştirmek için `search` kullanın veya tam `project`, `target`, `category` (örneğin, `swiftCompilation`) ve `status` (`success` veya `failure`) filtreleyin. En yavaş önce gelecek şekilde `duration_ms` ile veya kronolojik sıra için `start_ms` ile sıralayın. Adım kimlikleri beraberlikleri bozar ve tam 64 bit hassasiyetlerini korumak için ondalık dizeler olarak döndürülür. Kimlikler bir derlemeyle sınırlıdır ve derlemeler arasında eşleştirilmemelidir.

İsteğe bağlı `start_ms` ve `end_ms`, derleme başlangıcından itibaren milisaniye cinsinden bir zaman aralığıyla örtüşen adımları seçer; bitiş hariçtir. Her iki araç da `build_run_id` olarak bir derleme UUID'sini veya kontrol paneli URL'sini kabul eder. Günlüğünü almak için döndürülen adım `id` değerini `step_id` olarak değiştirmeden iletin. Günlükler adım başına en fazla 64 KiB tutar, `log_truncated` atlanan çıktıyı gösterir.

Adımlar, Xcode derlemeleri işlendiğinde varsayılan olarak toplanır. Kaydedilen adım verileri 90 gün boyunca saklanır. Liste yanıtı `availability` içerir: kaydedilmiş adımlar mevcut olduğunda, filtreler hiçbirini eşleştirmese bile `available`; derleme hâlâ işleniyor ve henüz adımı yoksa `processing`; veya adımlar kaydedilmediyse ya da süresi dolduysa `unavailable`.

Aynı işlemler, aynı filtreler ve sayfalama ile `GET /api/projects/{account_handle}/{project_handle}/xcode/builds/{build_id}/steps` ve `GET /api/projects/{account_handle}/{project_handle}/xcode/builds/{build_id}/steps/{step_id}` adreslerindeki HTTP API üzerinden kullanılabilir. Her ikisi de derlemenin projesine okuma erişimi gerektirir.

#### Gradle derlemeleri

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `get_gradle_integration_guide` | Tam kimlik doğrulama, proje kurulumu, Gradle eklentisi, önbellek politikası ve iki derlemeli doğrulama iş akışını döndürür. Temsilciler, mevcut bir Android veya Gradle projesini düzenlemeden önce bunu çağırmalıdır. | Yok |
| `list_gradle_builds` | Özel meta veriler dahil olmak üzere bir proje için Gradle derleme çalıştırmalarını listeler. İsteğe bağlı `tag` parametresiyle özel bir etikete göre filtreler. | `account_handle`, `project_handle` |
| `get_gradle_build` | Derleme meta verilerini ve görev/önbellek sayılarını alır. | `build_run_id` |
| `list_gradle_build_tasks` | Görev sonuçlarını, bileşik derleme kimliğini, önbelleklenebilirliği ve artımlı durumu listeler. | `build_run_id` |
| `list_gradle_build_steps` | Arama, meta veri ve örtüşen zaman filtreleriyle zamanlanmış görevleri, yapılandırmayı ve dönüşümleri listeler. | `build_run_id` |
| `get_gradle_build_step` | Opak kimliğe göre kaydedilmiş adım meta verilerini inceler; adım başına günlükler kullanılamaz. | `build_run_id`, `step_id` |

Gradle ve Bazel adım listeleri varsayılan olarak 20 sonuç döndürür (maksimum 100), `search`, tam `project`, `target`, `category` ve `status`, örtüşen `start_ms` / `end_ms` filtrelerini (bitiş hariç) ve `duration_ms` veya `start_ms` sıralamasını destekler. Döndürülen kimlikleri değiştirmeden iletin; bunlar kendi derlemeleriyle sınırlıdır. Listeler `time_origin` ve `coverage` sunar. Eski Gradle raporları, derleme başlangıcı yüklenmediği için `first_recorded_timestamp` kullanır. Bazel profilleri, tüm kaydedilmiş aralıkları `trace_profile` kapsamıyla ve zaman kökeni olarak `profile_start` ile sunar. Eski derlemeler, saklanan BEP özetlerine geri döner. Kaynak kayıtlar 90 gün sonra sona erer. Bazel ayrıntıları, yayınlandığında temizlenmiş eylem günlüklerini içerir; Gradle ayrıntısı `log` null değerindedir. `compare_builds` istemi, bu kapsamı tam Bazel izlerini saklanan özetlerden ayırt etmek için kullanır ve daha geniş çağrı çıktısını kontrol etmeden önce temsilcileri eylem sonuçları ve günlükler için adım ayrıntılarına yönlendirir.

Tek adımlı araçlar `get_gradle_build_step` ve `get_bazel_build_step` bir adımı kimliğe göre alır ve zaman filtrelerini kabul etmez; adımları zaman aralığına göre filtrelemek için ilgili liste araçlarını kullanın.

Saklanan özetlerden döndürülen Bazel adım kimlikleri, listeleme ve bir adımı getirme arasında tam bir profil gelirse okunabilir kalır. Adım verilerinin süresi dolmuş indekslenmiş bir profil, kullanılamıyor olarak bildirilir. Gradle adım listeleri, sıfır süreli önbelleğe alınmış ve atlanmış işlemleri içerir.

#### Bazel çağrıları

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `get_bazel_integration_guide` | Kimlik doğrulama, proje kurulumu, Bazel yapılandırması ve doğrulama iş akışını döndürür. | Yok |
| `list_bazel_invocations` | Bir proje için derleme ölçümleri, sınırlı bir yürütme zaman çizelgesi, kritik yol tanılama ve ilişkili uzak önbellek toplamlarıyla tamamlanmış [Bazel Yapı Olay Protokolü](https://bazel.build/remote/bep) çağrılarını listeler. | `account_handle`, `project_handle` |
| `get_bazel_invocation` | Derleme ölçümleri, sınırlı bir yürütme zaman çizelgesi, kritik yol tanılama ve ilişkili uzak önbellek toplamlarıyla tek bir tamamlanmış Bazel çağrısını alır. | `account_handle`, `project_handle`, `invocation_id` |
| `list_bazel_build_steps` | Filtreler ve açık kapsamla kaydedilmiş Bazel profil aralıklarını listeler. | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_build_step` | Kaydedilmiş bir Bazel adımını ve yayınlanan eylem sonucunu ve temizlenmiş günlüğünü inceler. | `account_handle`, `project_handle`, `invocation_id`, `step_id` |
| `list_bazel_invocation_logs` | Bir Bazel çağrısı için yürütme sırasına göre yakalanan temizlenmiş test günlüklerini listeler. | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_invocation_log` | Bir Bazel çağrısı için yakalanan tek bir temizlenmiş test günlüğünü alır. | `account_handle`, `project_handle`, `invocation_id`, `invocation_log_id` |
| `list_bazel_cache_events` | İşlemi, uç noktası ve gözlem zamanıyla ham Bazel uzak önbellek gözlemlerini listeler; isteğe bağlı olarak bir çağrı, sonuç veya işlemle daraltılabilir. | `account_handle`, `project_handle` |
| `get_bazel_cache_event` | Tek bir ham Bazel uzak önbellek gözlemini alır. | `account_handle`, `project_handle`, `cache_event_id` |

#### Cargo derlemeleri

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_cargo_builds` | Bir proje için Cargo derlemelerini, en yeniden eskiye doğru listeler. `git_branch`, `status`, `is_ci` veya `command` ile filtreler. Cargo test yürütme sonuçları bu derleme listesi aracılığıyla değil, test araçları aracılığıyla kullanılabilir. | `account_handle`, `project_handle` |
| `get_cargo_build` | Derleme meta verilerini, toplam önbellek sayaçlarını ve tanılama içeren en fazla 500 kaydedilmiş derleyici işini alır. `compilations_truncated` atlanan işleri gösterir; tanılama yalnızca döndürülen işleri kapsar. | `account_handle`, `project_handle`, `build_id` |

Doğrulanmış görev kararlarını ve CAS işlemlerini almak, 4 MB ile sınırlı olmak üzere, `get_cargo_build` üzerinde `include_cache_inspection: true` ayarlayın. Varsayılan olarak ve kayıtlar eksik veya geçersiz olduğunda `cache_inspection` null değerindedir. Kısmi yakalama `truncated` bayrağına saygı gösterin; aktarımlar her görev isabetinin yerel/uzak kökenini belirlemez. HTTP ayrıntı uç noktası aynı sorgu parametresini kabul eder.

#### Mix derlemeleri

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_mix_builds` | Bir proje için özel meta veriler dahil olmak üzere Mix (Elixir) derleme işlerini, en yeniden eskiye doğru listeler. `git_branch`, `status`, `is_ci` veya `mix_env` ile filtreler. | `account_handle`, `project_handle` |
| `get_mix_build` | Derleme meta verilerini, tanılama sayılarını ve bağımlılık önbelleği özetini alır. | `account_handle`, `project_handle`, `build_id` |

#### Derleme izleri

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `get_build_trace` | [Perfetto](https://ui.perfetto.dev) içinde açabileceğiniz bir iz dosyası olarak Xcode, Gradle, Bazel veya Mix derlemesinin zaman çizelgesi için bir indirme bağlantısı alın. | `account_handle`, `project_handle`, `build_id` |

`build_id`, derleme çalıştırma kimliğidir (Bazel için çağrı kimliği) veya derlemenin kontrol paneli URL'sidir. Döndürülen `trace_url`, bir [Chrome Trace Event](https://docs.google.com/document/d/1CvAClvFfyA5R-PhYUmn5OOQtYMH4h6I0nSsKchNAySU) JSON dosyası sunar. Bağlantıya sahip olan herkes, aramadan bir saat sonra sona eren `expires_at` tarihine kadar başka kimlik bilgileri olmadan o derlemenin izini indirebilir. Ajanlar bunu `curl` ile indirebilir, Perfetto'da açmanız için size verebilir veya Perfetto'nun `trace_processor` özelliğiyle sorgulayabilir. İz, paralellik tarafından şeritlere paketlenmiş kaydedilmiş adımları, tüm derlemeyi kapsayan bir yolu ve derleme makine ölçümlerini kaydettiğinde CPU ve bellek sayaçlarını içerir. Günlükler olmadan yukarıdaki adım araçlarıyla aynı verileri tutar. Kontrol paneli, her derlemenin Zaman Çizelgesi sekmesinden aynı dosyayı sunar.

#### Once çalıştırmaları

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_once_runs` | Bir proje için Once çalıştırmalarını, en yeniden eskiye doğru listeler. `kind` (`build`, `test` veya `generic`), `status`, `is_ci` veya `git_branch` ile filtreler. Tamamlanmamış çalıştırmaların durumu `in_progress` olur. | `account_handle`, `project_handle` |
| `get_once_run` | Eylem toplamları, önbellek özeti ve test çalıştırmaları için test toplamlarıyla birlikte bir çalıştırmayı alır. | `account_handle`, `project_handle`, `run_id` |

Cargo derleme, Mix derleme ve Once çalıştırma kimlikleri bir proje içinde benzersizdir. Aynı okuma işlemleri HTTP API üzerinden `GET /api/projects/{account_handle}/{project_handle}/cargo/builds`, `.../mix/builds` ve `.../once/runs` adreslerinde mevcuttur; her biri tek bir kimlik için bir ayrıntı uç noktasına sahiptir.

#### Görevler, eylemler, modüller ve dosyalar

Bu proje kapsamındaki araçlar, çalıştırmalar arasındaki kalıcı derleme kimliklerini inceler. `list_build_entities` ile başlayın, ardından döndürülen kararlı `id` değerini aynı `kind` ile birlikte `get_build_entity` veya `list_build_entity_history` öğesine, `account_handle` ve `project_handle` ile birlikte iletin. Derleme veya çağrı tanımlayıcısı gerekmez.

| Araç | Açıklama | Gerekli parametreler |
| --- | --- | --- |
| `list_build_entities` | Bir projenin derlemeleri arasında görülen tek bir türdeki görevleri, modülleri, eylemleri veya dosyaları listeler. | `account_handle`, `project_handle`, `kind` |
| `get_build_entity` | Seçilen dönem için yerel kimliği ve analitikleriyle tek bir derleme varlığını alır. | `account_handle`, `project_handle`, `kind`, `id` |
| `list_build_entity_history` | Tek bir derleme varlığının kaydedilmiş yürütmelerini, derlemelerini veya önbellek olaylarını, en yeniden eskiye doğru listeler. | `account_handle`, `project_handle`, `kind`, `id` |

| `kind` | Araç zinciri | Geçmiş listeleri |
| --- | --- | --- |
| `bazel_actions` | Bazel eylemleri | BEP tarafından bildirilen eylem yürütmeleri |
| `gradle_tasks` | Gradle görevleri | Görev yürütmeleri |
| `xcode_modules` | Xcode modülleri | Derlemeler ve modül önbelleği olayları |
| `once_actions` | Once eylemleri | Yürütmeler |
| `mix_files` | Mix derlenmiş dosyalar | Derlemeler |
| `mix_modules` | Mix derlenmiş modüller | Derlemeler |
| `cargo_crates` | Cargo kasaları | Kaydedilmiş rustc çağrıları |

Bu araçlar kademeli olarak kullanıma sunulmaktadır ve yalnızca etkinleştirildiği projeler için veri döndürür; diğer projeler için boş bir sonuç yerine hata döndürür. Bir tür, yalnızca ilgili derleme araç zincirini kullanan projeler için kullanılabilir. Araçlar sınırlı `start_at`/`end_at` filtrelerini, `environment` (`any`, `ci` veya `local`) ve tam eşleşen bir `branch` kabul eder. `list_build_entities` `q` parametresini kabul eder; `list_build_entity_history` şeffaf olmayan `after`/`before` imleçlerini destekler. Bilinmeyen zamanlama veya önbellek gözlemleri sıfır veya isabetsizlik olarak değil, mevcut değil olarak kalır. Geçmiş, mevcut çalıştırma araçlarını kullanarak detaylı inceleme için kaydedilen üst öğeyi ve yerel yürütmeyi referans alır.

`get_build_entity` metrikleri, kaydedilmiş zamanlamaya sahip gözlem sayısını içeren `duration_samples` değerini içerir: Gerçek sıfır süreler sayılır, eksik zamanlama sayılmaz. Bu sayı, gözlem sayısından daha düşük olabilir; mevcut olmayan süre istatistikleri null olarak kalır.

Xcode modül süreleri, derleme günlüklerindeki ölçülen hedef derlemelerden gelir. Modül önbelleği çözümlemeleri ve derleme işi olmayan hedefler süre örneklerine katkıda bulunmaz. Derleme gözlemleri Xcode derlemesini referans alır; önbellek olayları ise oluşturma veya önbellek komutunu referans alır.

Bazel eylemleri, hedef etiketi, anımsatıcı ve yapılandırılmış birincil çıktı ile tanımlanır; böylece girişe bağlı önbellek özetlerine güvenmeden ayrı eylemler ve yapılandırmalar birbirinden ayrılır. Geçmiş, önbellek aramalarını veya izleme profili aşamalarını değil, BEP tarafından bildirilen yürütmeleri kaydeder. Tam yürütme kapsamı `--build_event_publish_all_actions` gerektirir; yapıt teslimi en iyi çaba esasına göre yapılır, bu nedenle eksik gözlemler hiçbir işin çalışmadığına dair kanıt değildir. Kararlı kimliği veya yürütme başlangıcı olmayan eski Kura yükleri kabul edilmeye devam eder ancak indekslenmez. Eksik bitiş zamanı ölçümleri mevcut değil olarak kalır ve gerçek sıfır süreler sayılır.

Mix modül süreleri, bağımsız olarak ölçülen modül işini değil, kapsayan dosyanın derlenmesini ölçer. Once eylemleri, istemci hedef eşlemelerini bildirdiğinde bildirilen hedef/yetenek/dizin yuvalarını kullanır; yalnızca tanılama etiketleri kararlı kimlikler değildir. Mevcut istemciler ve çalıştırma düzeyi araçları değiştirilmeden desteklenmeye devam eder.

Cargo kasaları, tam olarak kaydedilen kasa kökü, adı ve türüne göre gruplanır. Checkout yolu değişiklikleri geçmişleri bölebilir ve derleme profilleri, özellikler ile hedef üçlüleri ayırt edilmez. Geçmiş, dosya başına işi veya önbellek isabetlerini değil, rustc çağrılarını ölçer; eksik işler kaldırmaları veya tam bir çalışma alanı envanterini belirlemez.

Analitik okumalarının bellek ve yürütme süresi sınırlıdır. Bir sorgu bu sınırları aşarsa, araç boş bir sonuç uydurmak yerine hata döndürür.

Yeni gözlemler dağıtımdan sonra indekslenir; bu özellik mevcut çalıştırma telemetrisini geriye dönük olarak doldurmaz. Kimlik meta verileri, <.localized_link href="/guides/server/data-retention">veri saklama politikası</.localized_link> kapsamında bireysel gözlemlerden daha uzun süre korunur.

#### Testler

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_test_runs` | Bir proje için test çalıştırmalarını listeler. `query` alanları `git_branch`, `scheme` ve `status`'dir: `field:"value"` tam eşleşir, `field~"value"` büyük/küçük harfe duyarlı olmayan bir alt dizeyle eşleşir ve baştaki `-` her iki operatörü de olumsuzlar. Örneğin, `-git_branch~"gh-readonly-queue"` birleştirme kuyruğu dallarını dışlar. Boşlukla ayrılmış sorgu filtreleri ve açık argümanlar AND mantığıyla birleşir. | `account_handle`, `project_handle` |
| `get_test_run` | Sonuç paketi (`.xcresult`) ve oturum arşivi için geçici indirme URL'leri dahil olmak üzere bir test çalıştırması için ayrıntılı metrikleri alır. | `test_run_id` |
| `list_test_module_runs` | Belirli bir test çalıştırması için test modülü çalıştırmalarını listeler. | `test_run_id` |
| `list_test_suite_runs` | Belirli bir test çalıştırması için test paketi çalıştırmalarını, isteğe bağlı olarak modüle göre filtrelenmiş şekilde listeler. | `test_run_id` |
| `list_test_cases` | Bir proje için test senaryolarını listeler (`flaky` gibi filtreleri destekler). | `account_handle`, `project_handle` |
| `get_test_case` | Güvenilirlik oranı, kararsızlık oranı ve çalıştırma sayıları dahil olmak üzere bir test senaryosu için ayrıntılı metrikleri alır. | `test_case_id` veya `identifier` + `account_handle` + `project_handle` |
| `list_test_case_runs` | Test senaryosu çalıştırmalarını, isteğe bağlı olarak test senaryosuna veya test çalıştırmasına göre filtrelenmiş şekilde listeler. | `account_handle`, `project_handle` |
| `get_test_case_run` | Belirli bir test senaryosu çalıştırması için hata ayrıntılarını ve tekrarları alır. | `test_case_run_id` |
| `list_test_case_run_attachments` | Bir test senaryosu çalıştırması için ekleri listeler. Her ek, geçici bir indirme URL'si içerir. | `test_case_run_id` |
| `list_test_case_events` | Bir test senaryosu için sessize alma veya atlama gibi durum değişikliklerini listeler. | `test_case_id` |
| `update_test_case` | Bir test senaryosunun durumunu veya kararsız sınıflandırmasını günceller. Bir değişiklik, harici hizmetler dahil olmak üzere yapılandırılmış webhook uç noktalarına bir olay gönderebilir. | `test_case_id` veya `identifier` + `account_handle` + `project_handle` |
| `list_xcode_test_targets` | Bir test çalıştırması için seçici test hedefi sonuçlarını listeler. | `test_run_id` |
| `get_coverage` | Bir projenin kod kapsamını hedefleriyle birlikte, bir commit'te veya bir dalın en son tamamlanan commit'inde alır. `git_commit_sha` veya `branch` olmadan, varsayılan dalı okur. | `account_handle`, `project_handle` |
| `list_coverage_files` | Bir commit'in kod kapsamının ölçtüğü dosyaları, satır kapsamlarıyla birlikte, bir commit'te veya bir dalın en son tamamlanan commit'inde listeler. `search`, sıralama ve sayfalandırmayı destekler. | `account_handle`, `project_handle` |
| `get_coverage_file` | Bir dosyanın kod kapsamını ve fonksiyonlarını, bir commit'te veya bir dalın en son tamamlanan commit'inde alır. Her satırın yürütme sayısını almak için `include_lines` ayarlayın. | `account_handle`, `project_handle`, `path` |

Kod kapsamı araçları, kod kapsamı etkinleştirilmiş hesaplara sunulur.

#### Paketler

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_bundles` | Bir proje için paketleri (uygulama ikili dosyaları) listeler. İsteğe bağlı olarak `git_branch` ve `tags` ile filtreler (tüm etiketler tam olarak eşleşmelidir). | `account_handle`, `project_handle` |
| `get_bundle` | Özel etiketler dahil olmak üzere belirli bir paket hakkında ayrıntılı bilgi alır. | `bundle_id` |
| `get_bundle_artifact_tree` | Bir paket için tam yapıt ağacını, yola göre sıralanmış düz bir liste olarak alır. | `bundle_id` |

`list_bundles`, derleme çeşitlerini veya ortamları ayırt etmek için `tags: ["paid", "production"]` kabul eder. Etiketler, harf, rakam, tire veya alt çizgi içeren, etiket başına en fazla 10 etiket ve 50 karakter olan büyük/küçük harfe duyarlı etiketlerdir. Liste ve ayrıntı sonuçları `custom_metadata.tags` içerir. Sayfalandırma sayıları ve dal filtreleri etiketli sonuçlara uygulanır; `tags` atlanması filtrelensiz davranışı korur. Geçersiz etiket filtreleri, sorguyu genişletmek yerine hata döndürür.

#### Oluşturmalar

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_generations` | Bir proje için oluşturma çalıştırmalarını listeler. | `account_handle`, `project_handle` |
| `get_generation` | Belirli bir oluşturma çalıştırması hakkında ayrıntılı bilgi alır. | `generation_id` |

#### Önbellek çalıştırmaları

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_cache_runs` | Bir proje için önbellek çalıştırmalarını listeler. | `account_handle`, `project_handle` |
| `get_cache_run` | Belirli bir önbellek çalıştırması hakkında ayrıntılı bilgi alır. | `cache_run_id` |
| `list_xcode_module_cache_targets` | Bir oluşturma veya önbellek çalıştırması için modül önbelleği hedeflerini listeler; hedef başına önbellek isabeti/ıska durumu ve ek karma girdileri dahil olmak üzere tanılama bileşeni karmalarını gösterir. | `run_id` |

#### Önizlemeler

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_previews` | Bir proje için paylaşılabilir uygulama önizlemelerini listeler. | `account_handle`, `project_handle` |
| `get_preview` | Bir önizlemeyi ve derlemeleri için geçici indirme URL'lerini alır. | `preview_id` |
| `get_latest_preview` | Çalışan bir uygulama ikili dosyası için en son önizlemeyi bulur. | `account_handle`, `project_handle`, `binary_id`, `build_version` |

#### Otomasyonlar

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_automation_alerts` | Bir proje için otomasyon uyarılarını listeler. | `account_handle`, `project_handle` |
| `get_automation_alert` | Bir otomasyon uyarısını alır. | `alert_id` |
| `list_automation_alert_revisions` | Bir otomasyon uyarısının revizyon geçmişini listeler. Eylem kimlik bilgileri gizlenmiştir. | `alert_id` |
| `list_project_notification_alerts` | Proje bildirim uyarısı kurallarını listeler. Kontrol paneli ayarları sayfasıyla aynı yönetici iznini gerektirir. Webhook adresleri gizlenmiştir. | `account_handle`, `project_handle` |

### Olaylar

Durumsuz `2026-07-28` Model Context Protocol yaşam döngüsünü kullanan istemciler, olayları ve yük şemalarını keşfetmek için `events/list` çağrısı yapabilir:

| Olay | Gönderilme zamanı | Abonelik filtresi |
|-------|-----------------|---------------------|
| `test_case.marked_flaky` | Bir test senaryosu kararsız olmayan durumdan kararsız duruma geçer. | `account_handle`, `project_handle` |
| `build.failed` | Yerel veya sürekli entegrasyon Xcode, Gradle ya da Bazel derlemesi başarısızlıkla sonlanır. | `account_handle`, `project_handle` |
| `test_run.failed` | Yerel veya sürekli entegrasyon test çalıştırması başarısızlıkla sonlanır; birleştirilmiş parçalı çalıştırma veya terk edilmiş çalıştırma dahildir. | `account_handle`, `project_handle` |
| `ci_job.failed` | Bir Tuist runner işi başarısızlıkla tamamlanır. | `account_handle` |

Abone olmak için istemci, olay adıyla, yukarıda `arguments` içinde listelenen tanıtıcılarla ve bir `https://` geri çağırma URL'si ile bir `whsec_` imzalama sırrı içeren bir `webhook` teslimatıyla `events/subscribe` çağrısı yapar. Proje olayları hesap üyeliği ve ilgili test veya derleme verilerine okuma erişimi gerektirir; runner işi olayları hesap üyeliği ve runner okuma erişimi gerektirir. Talep edilmiş [`auth.md`](https://workos.com/auth-md) erişim belirteçleri, talep edilmiş hesap belirteçleri ve tarayıcı yetkilendirme izinleri abonelik oluşturabilir; ilişkili kimlik bilgisi artık etkin olmadığında teslimat durur. Her kullanıcı en fazla 25 etkin abonelik tutabilir. Tuist, aboneliği kaydetmeden önce geri çağırmaya bir doğrulama sorgusu gönderir. Geri çağırma, aynı `challenge` değerini içeren bir nesne döndürmelidir. Abonelik varsayılan olarak yedi gün sürer, tekrar abone olunarak yenilenebilir ve kullanıcının erişimi veya kimlik bilgisi kaldırıldığında teslimat durur. İsteğe bağlı `ttlMs` bir saat ile 30 gün arasında sınırlıdır. Tuist zaman aşımına uğramış bir geri çağırmayı yeniden dener ve beş dakikayı kapsayan en az üç ardışık zaman aşımından sonra aboneliği iptal eder; geri çağırmayı restore ettikten sonra tekrar abone olun.

Bir olay gerçekleştiğinde, Tuist kaynak tanımlayıcısını ve kontrol paneli URL'sini geri çağırmaya gönderir. Derleme ve test çalıştırması hataları ayrıca `is_ci` ve `git_branch` içerir, böylece istemciler yerel hataları yok sayabilir veya dala göre filtreleyebilir. Derleme olayları `build_system` içerir; runner işi olayları hem `workflow_job_id` hem de `workflow_run_id` içerir. İstek, istemcinin kaynağını doğrulayabilmesi için bir abonelik tanımlayıcısı ve [Standard Webhooks](https://www.standardwebhooks.com/) imza başlıkları içerir. Tuist başarısız teslimatları yeniden dener, bu nedenle istemciler kopyaları atmak için kararlı `eventId` kullanmalıdır. Yük, test adlarını, günlükleri ve hata mesajlarını dışarıda bırakır; istemci bu ayrıntıları yukarıdaki araçlar aracılığıyla alabilir ve bir ekibi bilgilendirmeye veya hata ayıklamaya başlamaya karar verebilir. İstemciler teslimatı `events/unsubscribe` ile durdurabilir.

### İstemler

| İstem | Açıklama |
|--------|-------------|
| `fix_flaky_test` | Başarısızlık kalıplarını analiz ederek, kök nedeni belirleyerek ve hedefe yönelik bir düzeltme uygulayarak kararsız bir testi düzeltmenize rehberlik eder. |
| `compare_builds` | Performans gerilemelerini, önbellek değişikliklerini ve derleme sorunlarını belirlemek için derlemeleri karşılaştırmanıza rehberlik eder. Xcode, Gradle, Bazel ve Cargo projeleri için yerel araçları kullanır. Cargo karşılaştırmaları kısmi derleyici kapsamını korur ve tahmini derleyici işini geçen süreden tasarrufla ayırt eder. |
| `compare_test_runs` | Gerilemeleri, yeni hataları ve kararsız testleri belirlemek için iki test çalıştırmasını karşılaştırmanıza rehberlik eder. |
| `compare_bundles` | Yapı ağacındaki boyut değişikliklerini belirlemek için iki paketi karşılaştırmanıza rehberlik eder. |
| `compare_test_case` | Bir test senaryosunun davranışını iki dal veya zaman dilimi arasında karşılaştırmanıza rehberlik eder. |
| `compare_generations` | Performans gerilemelerini ve modül önbelleği değişikliklerini belirlemek için iki oluşturma çalıştırmasını karşılaştırmanıza rehberlik eder. |
| `compare_cache_runs` | Önbellek etkinliği değişikliklerini ve hedef düzeyindeki gerilemeleri belirlemek için iki önbellek çalıştırmasını karşılaştırmanıza rehberlik eder. |
| `integrate_gradle_project` | Tuist'i mevcut bir Gradle projesine entegre etmenize rehberlik eder. Ayrı araç ve Gradle kimlik doğrulaması, hesap keşfi, proje oluşturma, uzak önbellek ilkesi, derleme içgörileri ve geri okuma doğrulamasını içerir. |
| `integrate_bazel_project` | Bir Bazel projesi oluşturmanıza veya seçmenize, komut satırını kimlik doğrulamanıza, uzak önbelleği ve derleme içgörilerini yapılandırmanıza ve entegrasyonu Tuist derleme verileri aracılığıyla doğrulamanıza rehberlik eder. |
| `integrate_xcode_project` | Tuist'i mevcut bir Xcode projesine entegre etmenize rehberlik eder. Xcode önbelleğini, derleme içgörülerini, test içgörilerini ve test parçalama özelliğini destekler. |
| `ask_tuist` | Bağlam için genel materyalleri kullanarak ve mevcut davranışın doğruluk kaynağı olarak odaklanmış uygulama ve test kanıtlarını kullanarak bir Tuist sorusunu yanıtlar. Bir `question` gerektirir ve revizyon sabitli kanıtlara atıfta bulunur. |

Proje verisi istemleri, incelemeyi belirli bir projeyle sınırlamak için `account_handle` ve `project_handle` kabul eder. Karşılaştırma istemleri ayrıca karşılaştırılacak iki öğeyi (ID, kontrol paneli URL'si veya dal adına göre) belirtmek için `base` ve `head` bağımsız değişkenlerini kabul eder. `ask_tuist`, proje parametreleri yerine bir `question` kabul eder. `integrate_gradle_project` ayrıca uygulanacak Gradle entegrasyonlarının virgülle ayrılmış bir listesi olan `features` kabul eder: `remote_cache`, `build_insights`, `test_insights`, `flaky_tests` ve `test_sharding`. `integrate_bazel_project`, kendi kendine barındırılan veya yerel kurulumlar için isteğe bağlı bir `server_url` kabul eder. `integrate_xcode_project`, `xcode_cache`, `build_insights`, `test_insights` ve `test_sharding` ile `features` kabul eder.

#### Gradle entegrasyonu istemi özellikleri

`integrate_gradle_project` istemi ve `get_gradle_integration_guide` aracı, eksiksiz kurulum iş akışını belgeler. Araç ayrıca sunucunun başlatma talimatlarında da referans verilir; bu da istemleri listelemeyen ajanlar tarafından keşfedilmesini sağlar.

| Özellik | Ajanın yapılandırdığı şey |
|---------|---------------------------|
| `remote_cache` | Gradle'ın derleme önbelleğini etkinleştirir, Tuist uzak önbellek yükleme ilkesini yapılandırır ve yalnızca yerel salt okunur kullanıma sahip sürekli entegrasyon runner'larından yüklemeleri önerir. |
| `build_insights` | Tuist Gradle eklentisini uygular ve gerektiğinde derleme analitiği yükleme davranışını yapılandırır. |
| `test_insights` | Gradle `Test` görevi sonuçlarının otomatik olarak yüklenmesi için Tuist Gradle eklentisini uygular. |
| `flaky_tests` | Kararsız test algılama kurulumuna, isteğe bağlı Gradle Test Retry eklentisi kullanımına ve test karantina yapılandırmasına rehberlik eder. |
| `test_sharding` | `tuistPrepareTestShards` için sürekli entegrasyon iş akışını, parça matrisi oluşturmayı ve `TUIST_SHARD_INDEX` tabanlı test yürütmeyi ekler. |

`features` atlandığında, istem ajandan Gradle projesini düzenlemeden önce kullanıcının hangi entegrasyonları istediğini netleştirmesini veya istekten en küçük yararlı kümeyi çıkarmasını ister.

#### Xcode entegrasyonu istemi özellikleri

`integrate_xcode_project` istemi, Tuist'in desteklediği her Xcode entegrasyonunu belgeler:

| Özellik | Ajanın yapılandırdığı şey |
|---------|---------------------------|
| `xcode_cache` | `tuist setup cache`, oluşturulan proje önbelleği ayarlarını, manuel Xcode önbelleği derleme ayarlarını ve yalnızca sürekli entegrasyon runner'larıyla sınırlı bir yükleme ilkesini yapılandırır. |
| `build_insights` | `tuist inspect build`, `tuist xcodebuild`, `-resultBundlePath` ve `tuist setup insights` aracılığıyla isteğe bağlı makine metriklerini yapılandırır. |
| `test_insights` | `tuist inspect test`, şema test sonrası eylemlerini ve sürekli entegrasyon test çalıştırmaları için sonuç paketi oluşturmayı yapılandırır. |
| `test_sharding` | Xcode veya oluşturulan proje parça planlamasını ve `TUIST_SHARD_INDEX` ile parça yürütme iş akışını ekler. |

`features` atlandığında, istem ajandan Xcode projesini düzenlemeden önce kullanıcının hangi entegrasyonları istediğini netleştirmesini veya istekten en küçük yararlı kümeyi çıkarmasını ister.
