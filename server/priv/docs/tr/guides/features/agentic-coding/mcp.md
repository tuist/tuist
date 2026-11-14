---
{
  "title": "Model Context Protocol (MCP)",
  "titleTemplate": ":title · Ajan tabanlı kodlama · Özellikler · Kılavuzlar · Tuist",
  "description": "AI ajanlarına Tuist'in MCP uç noktası üzerinden test içgörülerine ve daha fazlasına erişim sağlayın."
}
---
# Model Context Protocol

[Model Context Protocol (MCP)](https://modelcontextprotocol.io/docs/getting-started/intro), yapay zeka ajanlarının harici hizmetler ve veri kaynaklarıyla etkileşime girmesini sağlayan açık bir standarttır. [Claude](https://claude.ai/), [Claude Code](https://docs.anthropic.com/en/docs/claude-code), [Codex](https://developers.openai.com/codex/) gibi uygulamaların ve [Zed](https://zed.dev), [Cursor](https://www.cursor.com) veya [Visual Studio Code](https://code.visualstudio.com) gibi editörlerin Tuist ile birlikte çalışabilir olmasını sağlar.

Tuist, sunucu tarafında bir Model Context Protocol uç noktasını `https://tuist.dev/mcp` adresinde barındırır. İstemcinizi bu uç noktaya bağlayarak ajanların test içgörileri, kararsız test analizleri ve daha fazlası dahil olmak üzere Tuist proje verilerinize erişmesini sağlayabilirsiniz. Çoğu araç salt okunurdur ve kimliği doğrulanmış Tuist proje verileriyle sınırlıdır. Hesap kurulum araçları, kimliği doğrulanmış kullanıcının gerekli izinlere sahip olması durumunda hesapları listeleyebilir, organizasyonlar oluşturabilir, projeler oluşturabilir ve mevcut kullanıcıları organizasyonlara ekleyebilir. Her araç; salt okunur olup olmadığını, geri alınması zor bir değişikliğe neden olup olmadığını ve genel İnternet durumunu değiştirip değiştiremeyeceğini belirten açıklamalar sunar. `update_runner_profile`, `update_notification_rule` ve `connect_claude_subscription`, mevcut yapılandırmayı veya kimlik bilgilerini değiştirebildikleri için `destructiveHint: true` bildirir. Hesap kurulum araçları kullanıcı kimlik doğrulaması gerektirir. Proje token’ları veya normal hesap token’ları ile kullanılamazlar. Bir kullanıcı tarayıcıda bir istemciyi yetkilendirdiğinde veya bir `auth.md` kaydını talep ettiğinde, Tuist bu kimlik bilgisini yalnızca Model Context Protocol uç noktasında kullanıcıyla ilişkilendirir; böylece kurulum araçları istenen iş akışını tamamlayabilir.

Tuist, [2026-07-28 protokolünü](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http) uygular. İstekler durumsuzdur: istemciler her istekle birlikte protokol meta verilerini gönderir ve başlatma olmadan araçları doğrudan çağırabilir. `server/discover`, sunucunun kimliğini, yeteneklerini, desteklenen sürümleri ve talimatları döndürür. Oturum tanımlayıcıları veya bağımsız olay akışları yoktur. 2025-06-18 veya 2025-03-26 başlatma akışını kullanan istemciler desteklenmeye devam eder; bunlar da sunucu oturumları olmadan çalışır.

## Model Context Protocol ile beceriler

Model Context Protocol araçları ve <.localized_link href="/guides/features/agentic-coding/skills">beceriler</.localized_link> yaptıkları işlevler açısından örtüşebilir. İkisi arasındaki mevcut örtüşme göz önüne alındığında, her iş akışı için tek bir yaklaşım seçin ve aynı akışta ikisini karıştırmak yerine tutarlı bir şekilde kullanın.

Eklenti yüklemeyi destekleyen istemciler için, her ikisini birlikte yüklemek amacıyla <.localized_link href="/guides/features/agentic-coding/plugins">Tuist eklentilerini</.localized_link> kullanın.

## Yapılandırma

İstemcinize uzak bir Model Context Protocol sunucusu olarak `https://tuist.dev/mcp` ekleyin. Sunucunun başlatma talimatları ve genel sunucu kartı, aracıların harici kimlik doğrulama belgelerini almasını veya takip etmesini istemeden, dinamik istemci kaydı ile OAuth 2.0’ı ve standart tarayıcı yetkilendirme akışını satır içinde açıklar. Bu sunucu çapındaki talimatlar, iş akışı rehberliğini genel tutar: araç kimlik doğrulaması, yerel komut satırı araçlarını veya derleme sistemi entegrasyonlarını kimlik doğrulamaz ve ajanlar istenen değişiklikleri ilgili Tuist araçları üzerinden doğrulamalıdır. Derleme sistemine özel kurulum ve kimlik doğrulama kontrolleri entegrasyon kılavuzlarında ve istemlerde belgelenmiştir. Tuist, hem [Open Authorization](https://oauth.net/2/) keşif meta verilerini hem de güncel [auth.md protokolünü](https://workos.com/auth-md) ayrı olarak `https://tuist.dev/auth.md` adresinde yayınlamaya devam eder.

Organizasyonlarınızdan biri tek oturum açmayı (SSO) zorunlu kılıyorsa, tarayıcıda bir istemciyi yetkilendirmek o organizasyon üzerinden oturum açılmış bir oturum gerektirir ve gerektiğinde Tuist sizi önce sağlayıcıya yönlendirir. Bkz. <.localized_link href="/guides/integrations/authentication/sso#choose-an-enrollment-policy">tek oturum açma</.localized_link>.

Uç nokta, daha eski oturum tabanlı yaşam döngüsünün yanı sıra durumsuz `2026-07-28` Model Context Protocol istek yaşam döngüsünü, `server/discover` dahil olmak üzere kabul eder. Mevcut istemciler mevcut bağlantı yöntemlerini kullanmaya devam edebilir.

Model Context Protocol olaylarını destekleyen istemciler proje olaylarına abone olabilir. Kullanılabilir olay ve teslimat gereksinimleri için bkz. [Olaylar](#events).

Zaten uzaktan tarayıcı kimlik doğrulamasını destekleyen istemciler, tarayıcıda kimlik doğrulamaya devam edebilir. `auth.md` destekleyen istemciler ve ajanlar anonim olarak kayıt olabilir, güvenilir bir sağlayıcı kimlik iddiası sunabilir veya hizmet tarafından kimliği doğrulanmış bir e-posta talebi başlatabilir. Kayıt, Tuist tarafından imzalanmış bir kimlik iddiası döndürür; ajan bu iddiayı standart token uç noktasında bir saatlik erişim token’ı ile değiştirir. Tuist genel imzalama anahtarını yayınlar ve standart token iptalini ile sağlayıcı güvenlik olayı teslimatını destekler.

Kimliği doğrulanmamış bir ajan, Model Context Protocol uç noktası tarafından döndürülen `WWW-Authenticate` üst bilgisini okumalı, korunan kaynak meta verilerini almalı, yetkilendirme sunucusu meta verilerini almalı ve `agent_auth.skill` URL’sini takip etmelidir. Tuist ayrıca yetkisiz yanıt gövdesinde aynı yerel `auth_md` URL’sini döndürür, böylece dil modeli odaklı istemciler yerel bir istemci entegrasyonuna güvenmeden akışı keşfedebilir. Dağıtım yerel belgesi; uç nokta adları, istek gövdeleri, talep yoklaması ve iddia değişimi için gerçek kaynaktır.

Bir ajan e-posta talebini başlatmadan önce, kullanıcının Tuist hesabına ait e-posta adresini onaylamasını istemelidir. Bu adresi bir sağlayıcı profilinden, Git yapılandırmasından, ortam değişkeninden veya oturum meta verisinden çıkarmamalıdır.

Uç nokta `mcp` kapsam grubunu kullanır. Anonim, talep öncesi bir kimlik bilgisi yetenekleri keşfedebilir ve genel entegrasyon rehberliğini okuyabilir ancak oturum açmış bir kullanıcı olarak değerlendirilmez. Tarayıcı yetkilendirmesi veya talepten sonra kimlik bilgisi kullanıcı kapsamlı hale gelir ve her araç, kontrol panelindekiyle aynı yetkilendirme kontrollerini uygular. Ayrıntılar için bkz. <.localized_link href="/guides/server/authentication#scope-groups">kapsam grupları belgeleri</.localized_link>.

Araçlar, kimliği doğrulanmış kullanıcının zaten okuma erişimine sahip olduğu projelere çözülür. Xcode ve Gradle derleme araçları bir derleme UUID’sini veya kontrol paneli URL’sini kabul eder. UUID tam olarak bir projeyi tanımlamalıdır; birden fazla projede görünüyorsa, araç başka bir projenin raporunu seçmek yerine bulunamadı yanıtı döndürür. Proje kapsamlı kontrol paneli ve API okumaları kullanılabilir durumda kalır. Bildirilen aktör tanımlayıcıları doğrulanmamış etiketlerdir; kimlik bilgileri veya ek erişim hakları değildir.

Derleme listesi ve ayrıntı araçları, isteğe bağlı `tuist_version` meta verilerini sunar: Xcode ve Cargo için raporlayan Tuist CLI, Gradle için Tuist Gradle eklentisi ve Mix için `tuist_ex` kütüphanesi. Xcode ayrıca, yükleyen CLI’dan farklı olabilen bağlantılı proje oluşturma olayından `tuist_generation_version` değerini de sunar. Eksik gözlemler null olarak işaretlenir; sunucudan veya başka bir rapordan çıkarılmaz. Bazel mevcut `bazel_version` değerini kullanır; Once çalıştırma ayrıntıları `once_version` değerini sunar. Bu alanlar bildirilen sürümleri tanımlar, doğrulanmış kimlik veya ağ sözleşmesi sürümlerini değil. REST derleme uç noktaları aynı meta verileri sunar. Mevcut entegrasyon ve kararsız test yetenekleri sürüm alanlarına bağlı değildir ve iş akışı değişikliği gerektirmez.

Bir müşterinin hesabını inceleyen Tuist operatörleri bunu, her çağrıyı kaydeden Tuist’in dahili operasyon araçlarıyla yapar; bu uç noktaya doğrudan bağlantı, kullanıcının kendi üyelikleri dışında hiçbir erişim sağlamaz.

### Pulse

Pulse, hesabın operasyonel metrikleri, günlükleri ve izleri için yalnızca okunabilir araçlar sunar; tümü `account_handle` ile adreslenir. İlk ikisi Pulse sayfalarını ve REST API’lerini yansıtır; diğer beşi bir ajanın telemetriyi doğrudan keşfetmesine olanak tanır ve REST eşdeğeri yoktur:

| Araç | Amaç | `/api/accounts/:account_handle/pulse` altındaki REST eşdeğeri |
| --- | --- | --- |
| `query_pulse` | Pulse sayfa tabloları | `GET /:signal` |
| `get_pulse_analytics` | Pulse sayfa widget’ları | `GET /:signal/analytics` |
| `query_pulse_metrics` | Anlık veya aralıklı PromQL | Yok |
| `list_pulse_labels` | Etiket adları veya bir etiketin değerleri | Yok |
| `search_pulse_logs` | Filtrelenmiş günlük girdileri | Yok |
| `search_pulse_traces` | Filtrelenmiş yayılmlar | Yok |
| `get_pulse_trace` | Bir izdeki tüm yayılmlar | Yok |

Pulse, hesap veya proje herkese açık olsa bile sunucu tarafından yapılandırılan organizasyonun mevcut üyeleriyle sınırlıdır. Kullanıcı kimlik doğrulaması veya kullanıcıyla ilişkili bir `mcp` kimlik bilgisi ve hesap okuma yetkisi gerektirir. Proje token’ları, normal hesap token’ları, anonim kayıtlar ve organizasyon üyeliği olmayan operatör erişimi Pulse erişimi sağlamaz. Kimlik bilgileri başka bir arka uç veya telemetri kiracısı seçemez ve yalnızca sunucu tarafından yapılandırılan hesap Pulse telemetrisine sahiptir, bu nedenle hiçbir araç başka bir hesabın verilerini okuyamaz. Tarayıcı ajanları bu araçları yalnızca Pulse sayfalarında, o sayfanın hesap kapsamı içinde alır.

REST bir kullanıcı kimlik bilgisi gerektirir. OAuth ve `auth.md` kullanıcı ilişkileri yalnızca `/mcp` uç noktasında kullanılabilir; ilişkili hesabın üyeliği veya görünürlüğünden bağımsız olarak, geçerli bir kullanıcı içermeyen bir hesap kimlik bilgisi reddedilir.

`query_pulse`, `signal` (`metrics`, `logs` veya `traces`), isteğe bağlı bir `query` ve `range` (`15m`, `1h`, `6h` veya `24h`, varsayılan `1h`) parametrelerini alır. Metrikler PromQL ifadelerini kabul eder. Günlükler ve izler, günlük gövdeleri ve yayılım adlarıyla eşleştirilen büyük/küçük harf duyarsız değişmez metni kabul eder; varsayılan olan `*` her şeyi seçer. İz satırları tekil yayılmlardır. Tablolar `search`, `page` (varsayılan `1`), `page_size` (`1`–`100`, varsayılan `20`), `sort_by` ve `sort_order` (`asc` veya `desc`) parametrelerini kabul eder. Sıralama sütunları sinyale bağlıdır ve araç şemasında listelenir. Filtreler `service` ve günlük `level` içerir. Filtre operatörleri karşılık gelen `_op` argümanını (`eq`, `contains` veya `not_contains`) kullanır; varsayılan olarak tam eşitlik uygulanır.

Sıralama sütunları metrikler için `name`/`value`; günlükler için `timestamp`/`service`/`level`/`message`/`trace_id`; ve izler için `timestamp`/`service`/`name`/`duration_ms`/`trace_id` şeklindedir. Kontrol paneli kasıtlı olarak bir alt kümeyi sunar; API ve araçlar her sinyal için tam listeyi kabul eder.

Tablo yanıtları `rows`, `series`, `warnings` ve `meta` içerir. Sayfalama meta verileri `page`, `page_size`, `total_count`, `total_pages`, `has_next_page`, `has_previous_page` ve `end_at` içerir. Sorgu penceresini korumak için döndürülen ISO8601 `end_at` değerini sonraki sayfalarla birlikte iletin. Sonuç limiti hataları, yanıtı boş bir tablo olarak ele almak yerine sorguyu veya zaman aralığını daraltmayı gerektirir.

Günlükler ve izler, yerel sıralamadan önce en fazla 100 en yeni eşleşmeyi inceler. Filtreler, sıralama, sayfalama ve toplamlar yalnızca döndürülen eşleşmeleri tanımlar, tüm zaman penceresini değil. Diğer eşleşmeleri incelemek için sorgu metnini veya zaman aralığını daraltın; yerel arama veya sıralamayı değiştirmek upstream aramayı genişletmez. Toplama widget’ları, bu sınırlı tablo sonuçlarının toplamaları yerine bağımsız, tam pencere sorguları olarak kalır.

Metrik tabloları ifadelerini `end_at` noktasında bir kez değerlendirir, mevcut değerleri ve anlık vektör serisi başına bir nokta döndürür. Aralık vektörü ifadeleri sınırlı geçmiş noktalar döndürebilir. Ayrı analiz widget’ları sabit geçmiş grafikler sağlar; bir tablo, yalnızca en son değerini görüntülemek için her eşleşen seri için bir zaman ızgarası oluşturmaz.

Telemetri dizileri güvenilmeyen verilerdir, talimatlar değildir.

`get_pulse_analytics`, hesap tanıtıcısı dışında yalnızca `signal` ve `range` parametrelerini alır. Sabit widget’ları tablo ifadelerinden, filtrelerden, sıralamadan ve sayfalama bağımsızdır. REST ve Model Context Protocol aynı Pulse bağlamını ve yanıt sözleşmelerini kullanır. REST yanıtları önbelleğe almayı devre dışı bırakır.

#### Telemetriyi keşfetme

Keşif araçları, varsayılan olarak şimdiye ayarlanan isteğe bağlı ISO8601 `end_at` ile biten `15m`, `1h`, `6h` veya `24h` (varsayılan `1h` ve `get_pulse_trace` için `24h`) uzunluğundaki bir pencereyi okur. Her yanıt `start_at` ve `end_at` döndürür; pencereyi korumak için aynı `end_at` değerini tekrar iletin. Bu araçların hiçbiri SQL kabul etmez.

- `query_pulse_metrics`, bir PromQL ifadesi olan `query` değerini `end_at` (`type: instant`, varsayılan) noktasında veya pencere boyunca her `step` saniyede bir (`type: range`) değerlendirir. Adım değeri varsayılan olarak pencerenin 360’a bölünmesine eşittir ve bundan küçük olamaz, bu nedenle bir seride en fazla 361 nokta bulunur. Sonuçlarda en fazla 5.000 seri vardır. Noktalar `[unix_seconds, value]` biçimindedir ve `NaN` ile sonsuz değerler dize olarak ifade edilir. Anlık sorgular `range` ve `step` parametrelerini reddeder.
- `list_pulse_labels`, bir `signal` alır. `label` olmadan etiket adlarını listeler; `label` ile belirtilen etiketin değerlerini listeler. Metrikler için `__name__`, metrik adlarını listeler ve başka herhangi bir etiketin değerleri `match` gerektirir; bu, `up` gibi bir seri seçicidir. Günlük ve iz etiketi değerleri `filters` kabul eder; iz etiket adları iz şemasından gelir ve bunu gerektirmez. Günlük ve iz değerleri, penceredeki giriş sayılarını içerir ve en sık olanlar önce gelir, bu nedenle hizmetlere göre hatalar gibi ayrıntılı dökümler olarak da kullanılabilirler. `search`, yalnızca değişmez metin içeren adları veya değerleri tutar ve `limit`, `1`–`1000` aralığını (varsayılan `100`) kabul eder. Günlük etiket adı keşfi, her türden en fazla 1.000 farklı öznitelik kümesini inceler ve yalnızca filtrelerin kabul ettiği anahtarları listeler.
- `search_pulse_logs`, gövdesi `text` içeren ve her filtreyi eşleyen, en fazla `limit` giriş (`1`–`100`, varsayılan `50`) döndürür; sıralama `newest` veya `oldest` olarak yapılabilir. Her giriş `severity_text`, `body`, `trace_id`, `span_id`, `scope_name` ve birleştirilmiş kaynak ile günlük `attributes` bilgilerini içerir. Kubernetes’ten toplanan günlükler için `span_id` ve `scope_name` değerleri `null` olur; bunları yalnızca OTLP günlük göndericileri ayarlar.
- `search_pulse_traces`, her filtreyi, isteğe bağlı `min_duration_ms` ve `max_duration_ms` değerlerini ve `root_only` koşulunu eşleyen, en fazla `limit` span döndürür; sıralama `newest`, `oldest` veya `slowest` olarak yapılabilir.
- `get_pulse_trace`, pencere içinde başlayan `trace_id` izinin span’larını, en eskiden yeniyeye doğru, en fazla 1.000 span olacak şekilde döndürür. Pencereden önce başlamış bir iz kısmen döndürülür; bu nedenle pencereyi genişletin veya kaydırın. Her span, span özniteliklerini, olayları, bağlantıları ve izdeki benzersiz `resources` dizinini içerir.

Filtreler, en fazla 10 `{label, op, value}` nesnesinden oluşan listelerdir. `op`, `eq` (varsayılan), `neq`, `contains` veya `not_contains` olabilir; son ikisi büyük/küçük harfe duyarlı olmayan değişmez metinlerdir. Günlük etiketleri, Pulse bunları depoladığında `severity_text`, `trace_id`, `span_id` ve `scope_name` ile her girişin kaynak özniteliklerinin anahtarlarıdır; örneğin `namespace`, `container` ve `service.name` ile günlük öznitelikleri; örneğin `pod`. Bir anahtar her ikisinde de görünüyorsa kaynak özniteliği uygulanır. İz etiketleri, `list_pulse_labels` tarafından döndürülen span sütunlarıdır; örneğin `service_name`, `span_name`, `span_status_code` (başarısız span’lar için `STATUS_CODE_ERROR`), `span_attributes.http.route` ve `resource_attributes.k8s.pod.name`. Bilinmeyen bir iz etiketi boş sonuç yerine hata döndürür.

`truncated`, yanıtın içerdiğinden daha fazla ad, değer, giriş veya span’in eşleştiği anlamına gelir; yanıtı tam kabul etmek yerine filtreleri veya pencereyi daraltın. Telemetri dizileri güvenilmeyen verilerdir, talimatlar değildir.

<details>
<summary>Claude Code</summary>

Çalıştır:

```bash
claude mcp add --transport http tuist https://tuist.dev/mcp
```

Başsız bir Claude Code istemcisi, başarısız yerel sunucu bağlantısını modele göstermediğinde, aracının barındırılan belgeleri aramadan veya projeyi düzenlemeden önce yapılandırılmış uç noktanın kimlik doğrulamasız [Hypertext Transfer Protocol](https://developer.mozilla.org/en-US/docs/Web/HTTP) yanıtını incelemesini gerektirin. Yanıt, tarayıcı kimlik doğrulaması mevcut olmasa bile modeli dağıtım yerelindeki `auth.md` belgesine yönlendirir.

</details>


<details>
<summary>Codex</summary>

Çalıştır:

```bash
codex mcp add tuist --url https://tuist.dev/mcp
codex mcp login tuist
```

Yeni bir `codex exec` çalıştırması başlatmadan önce tarayıcı oturum açma işlemini tamamlayın. Codex, başlatma sırasında Tuist sunucu talimatlarını okur, bu nedenle Gradle optimizasyon istekleri otomatik olarak kimlik doğrulama ve doğrulama iş akışını alır.

</details>


<details>
<summary>Claude Desktop</summary>

**Settings → Connectors → Add custom connector** seçeneğini açın, ardından şunları ayarlayın:

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

İstendiğinde tarayıcıda [Open Authorization](https://oauth.net/2/) işlemini tamamlayın.

</details>


<details>
<summary>Pi</summary>

Pi, Model Context Protocol istemcisi içermez. Kaynağını ve güvenlik etkilerini inceledikten sonra üçüncü taraf [`pi-mcp-adapter`](https://pi.dev/packages/pi-mcp-adapter) uzantısını yükleyebilirsiniz:

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

`auth` değerini `false` olarak ayarlamak, adaptörün tarayıcı kimlik doğrulama işleyicisinin Tuist’in yetkisiz yanıtını gizlemesini engeller. Başsız bir aracı daha sonra döndürülen `auth_md` URL’sini okuyabilir ve Tuist’in kayıt, kimlik iddiası değişimi ve talep yoklama akışını takip edebilir. Değiştirilen erişim belirtecini bearer belirteci olarak yapılandırın veya aracının doğrudan kimlik doğrulamalı Model Context Protocol çağrıları yapmasına izin verin.

Tarayıcı kimlik doğrulamasını tercih ediyorsanız `auth` değerini `"oauth"` olarak ayarlayın. Bu akış için, kimlik doğrulama tamamlanırken Pi’nin [remote procedure call mode](https://pi.dev/docs/latest/rpc) ile tek bir işlemi canlı tutun:

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

**Cursor Settings → Tools & Integrations → Model Context Protocol Tools** seçeneğini açın ve şunları ekleyin:

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>


<details>
<summary>Visual Studio Code</summary>

**Command Palette → MCP: Add Server** seçeneğini kullanın, ardından şu özelliklere sahip bir [Hypertext Transfer Protocol](https://developer.mozilla.org/en-US/docs/Web/HTTP) sunucusu yapılandırın:

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>


<details>
<summary>Zed</summary>

**Agent panel → Settings → Add Custom Server** seçeneğini açın, ardından şunları ayarlayın:

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>

Aracınız `auth.md` destekliyorsa, tarayıcı açmadan anonim olarak başlayabilir. Güvenilen sağlayıcı kimliği zaten bağlıysa, tarayıcı olmadan da tamamlanabilir. Hizmet kimlik doğrulamalı e-posta, anonim talep veya ilk sağlayıcı bağlantısı için aracı size bir Tuist doğrulama bağlantısı ve altı haneli kod gösterir. Bağlantıyı açın, oturum açın ve Tuist sayfasında aracının kodunu girin. Kodu asla aracıya geri göndermeyin. Tuist’in yetkilendirme sunucusu meta verileri, doğrudan dağıtımın kendi `/auth.md` adresine işaret eder; bu belge tam istek ve yoklama şekillerini içerir.

## Amp orb’larında ve Claude Code bulut oturumlarında çalışan ajanlar

Bir Tuist hesabına bağlı alan kutularında (sandbox) çalışan kodlama ajanları, tarayıcı veya kaydedilmiş bir Tuist kimlik bilgisi olmadan kendi kimlik belirteçleriyle uç noktaya kimlik doğrulayabilir:

- **Amp orbs** bir Amp çalışma alanının veya projesinin, hesap **Settings → Integrations → Amp** altında bağlıysa orb’un kimlik belirtecini gönderir. Amp’de sunucunun `Authorization` başlığını `Bearer ${amp:id-token}` olarak ayarlayın. Amp, sunucu URL’sinin kaynağı için belirteci basar; bu nedenle URL bu Tuist örneğinin kendi adresi olmalıdır ve süresi dolmadan önce yeniler. Başka bir kaynak için basılan belirteçler reddedilir.
- Bağlı bir Claude Code ortamının **Claude Code cloud sessions**, Tuist’in onlara `TUIST_OIDC_TOKEN` olarak ilettiği oturum belirtecini gönderir. Başlığı `Bearer ${TUIST_OIDC_TOKEN}` olarak ayarlayın.

Tuist’in Linux alan kutuları (sandbox) bununla birlikte gelir: Amp’in kullanıcı ayarlarında ve Claude Code’un kullanıcı yapılandırmasında her ikisi de `${TUIST_URL}/mcp` adresine işaret eden bir `tuist` sunucusu, Tuist CLI ve ajana sonuçlarını projenin geçmişine göre ne zaman kontrol etmesi gerektiğini söyleyen bir beceri. Başka yerlerde sunucuyu yukarıdaki başlıkla kendiniz ekleyin.

Bu belirteçler, bağlı hesabın her projesine salt okunur erişim sağlar: `mcp` grubunun okuma kapsamlarını taşırlar ve verileri oluşturan, değiştiren veya silen, testleri sessize alma veya atlatma gibi hiçbir kapsamı taşımazlar. Çalışma alanının veya ortamın bağlantısını kesmek, bir sonraki istekte erişimi durdurur ve erişim asla belirtecin kendisinden daha uzun sürmez. Birden fazla Tuist hesabına bağlı bir Amp çalışma alanı reddedilir çünkü belirteci tek bir hesabı adlandırmaz. Bir bağlantı eksik olduğunda, yetkisiz yanıtın `error_description` alanı bunu belirtir.

Bu salt okunur erişim yalnızca Model Context Protocol uç noktası için geçerlidir. Aynı alan kutusundaki komut satırı aracı ve derleme sistemi entegrasyonları, bağlantının CI erişimi için belirteci değiştirmeye devam eder.

## WebMCP

[WebMCP](https://webmachinelearning.github.io/webmcp) destekleyen tarayıcılarda, Tuist sayfaları araçları `document.modelContext` ile kaydeder, böylece tarayıcıya yerleşik ajanlar herhangi bir ek yapılandırma olmadan bunları çağırabilir. Çağrılar Tuist sunucusunda çalışır.

- **Website and documentation pages**, belgeleme ve kaynak araçlarını (`search_tuist`, `search_tuist_code`, `list_tuist_files` ve `read_tuist_file`) kaydeder. Oturum açmanıza gerek yoktur.
- **An account's dashboard pages**, oturum açtığınızda o hesap için Tuist’in salt okunur araçlarını kaydeder. Her sayfa yalnızca gösterdiği şeyler için, projenin derleme sistemine göre araçları kaydeder: bir Gradle projesinin derlemeler sayfası Gradle derleme araçlarını, test sayfaları test ve kapsam araçlarını, çalıştırıcı sayfaları çalıştırıcı araçlarını ve alan kutusu sayfaları alan kutusu araçlarını alır. Kişisel hesabınızın AI ayarları sayfasındaki Abonelikler bölümü `list_ai_subscriptions` alır; bu yalnızca kendi hesabınızda yanıt verir. Her sayfa ayrıca belgeleme araçlarını, `list_projects` ve `get_project` alır. Araçlar oturum açmış kullanıcı olarak çalışır, bu nedenle yalnızca panoda okuyabileceğiniz verilere ve yalnızca baktığınız hesaba erişirler. Başka bir sayfaya veya hesaba geçtiğinizde araçlar o sayfanın araçlarıyla değiştirilir.

Veri oluşturan, değiştiren veya silen araçlar WebMCP üzerinden kullanılamaz çünkü tarayıcı ajanı araçları sizin eklemeniz olmadan alır ve derlemeler ile testlerin ürettiği içeriği okur. Bu araçları kullanmak için bir MCP istemcisini `/mcp` uç noktasına bağlayın.

Kuruluş tek oturum açmayı (SSO) zorunlu kılıyorsa, araçlarını kullanmak için panoya sağlayıcısıyla oturum açın.

## Derleme sistemi entegrasyonları iki kimlik bilgisi kullanır

Model Context Protocol araçları için kullanılan kimlik bilgisi, Gradle eklentisini veya Bazel’in uzak hizmetlerini kimlik doğrulamaz. Bir ajan bir Gradle veya Bazel entegrasyonunu düzenlemeden veya doğrulamadan önce şunu çalıştırmalıdır:

```bash
tuist auth whoami --url https://tuist.dev
```

Bu komut kimlik doğrulanmamışsa, ajan durmalı ve kullanıcıdan şunu çalıştırmasını istemelidir:

```bash
tuist auth login --url https://tuist.dev
```

Yerel veya kendi kendine barındırılan bir dağıtım için, her iki komuttaki ve `tuist.toml` içindeki URL’yi değiştirin. Ana bilgisayar adının yazımını her yerde aynı tutun. Örneğin, `localhost` ve `127.0.0.1` ayrı saklanan kimlik bilgilerini kullanır.


## Yetenekler

### Araçlar

Aşağıdaki araçlar Tuist Model Context Protocol sunucusu üzerinden kullanılabilir:

Her araç, açık giriş ve çıkış şemalarıyla birlikte insan tarafından okunabilir bir açıklama yayımlar. Başarılı çağrılar, duyurulan çıkış şemasına uygun yapılandırılmış içerik döndürür ve ayrıca yapılandırılmış içeriği henüz tüketmeyen istemciler için metin olarak serileştirilmiş aynı sonucu döndürür.

`build_run_id`, `test_run_id`, `test_case_id`, `bundle_id`, `run_id`, `generation_id` veya `cache_run_id` gibi tek bir kaydın tanımlayıcısını alan araçlar, o kaydın Tuist pano URL’sini de kabul eder. Tanımlayıcıyı ayıklamak yerine URL’yi doğrudan tarayıcıdan yapıştırın.

`get_xcode_build`, `get_test_run`, `get_gradle_build` ve `get_project` `side_quests` içerebilir: projenin kullanmadığı ancak kaydın yardımcı olacağını gösterdiği Tuist yetenekleri. Her birinin bir `id`, dayandığı kanıtı belirten bir `tip` ve bir `docs` bağlantısı vardır. Ajanlardan önce kullanıcının isteğini tamamlamaları, geçerli yan görevlerden bahsetmeleri ve yalnızca kullanıcı onayladığında birini gerçekleştirmeleri istenir. Bunlar yalnızca projenin hesabının üyelerine, kullanıcı oturumu, bir MCP belirteci veya ajan kimliğiyle bağlansalar da döndürülür:

| ID | Araç | Ne zaman önerilir |
|----|------|----------------|
| `xcode_compilation_cache` | `get_xcode_build` | Xcode 26 veya sonraki sürümlerle işlenen temiz bir derleme, önbelleğe alınabilir derleme görevi çalıştırmadı. |
| `gradle_build_cache` | `get_gradle_build` | Bir derleme, Gradle’in derleme önbelleği bunlardan hiçbiri için bir anahtar hesaplamadan önbelleğe alınabilir görevleri yürüttü; bu, derleme önbelleğinin kapalı olduğu anlamına gelir. |
| `flaky_test_quarantine` | `get_test_run` | Bir çalıştırmada kararsız testler vardı ve projede etkinleştirilmiş hiçbir otomasyon bunları sessize almıyor veya atlamıyor. Once projeleri için önerilmez. |
| `test_sharding` | `get_test_run` | Tuist’in parçalayabileceği bir derleme sisteminde, parçalanmamış bir CI çalıştırması 10 dakika veya daha uzun sürdü. İpucu, seçici testin ne zaman kaç testi zaten atladığını söyler. |
| `tuist_runners` | `get_xcode_build`, `get_test_run` | Bir CI çalıştırması GitHub Actions, Bitrise, GitLab CI veya Buildkite makinelerini kullandı ve hesap Tuist Runners üzerinde hiçbir zaman bir iş çalıştırmadı. Yalnızca tuist.dev üzerinde. |
| `pull_request_comments` | `get_xcode_build`, `get_test_run` | Bir GitHub Actions çalıştırması, GitHub deposuna bağlı olmayan bir projeye aittir. |
| `other_build_systems` | `get_project` | Hesap, Tuist’i desteklenen her derleme sistemiyle kullanmıyor. İpucu, diğerlerini tanımlayan dosyaları listeler, böylece ajan depoyu kontrol edebilir. |

#### Belgeleme ve topluluk araması

Bu salt okunur araç, Tuist’in belgelerini, [uygulama programlama arabirimi](https://en.wikipedia.org/wiki/API) referansını, GitHub sürümlerini, topluluk forumunu ve GitHub sorunlarını, belgeleme web sitesini destekleyen aynı arama motoru üzerinden arar. Sürüm sonuçları ürünü, sürümü, yayın tarihini ve ön sürüm durumunu içerir. Varsayılan olarak kararlı sürümler aranır ve ön sürümler `include_prereleases` ile dahil edilebilir. Araç yalnızca `https://tuist.dev/mcp` adresindeki Tuist tarafından barındırılan sunucuda kullanılabilir.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `search_tuist` | Herkese açık Tuist belgelerini, uygulama programlama arabirimi referansını, GitHub sürümlerini, topluluk tartışmalarını ve GitHub sorunlarını arayın. İsteğe bağlı olarak tek bir `source` ile sınırlayın (`docs`, `api_reference`, `releases`, `forum`, `issues`). | `query` |

#### Geri bildirim

Ajanlar, bir Tuist aracının veya isteminin bekledikleri gibi çalışmadığını (kafa karıştırıcı bir sonuç, hata, eksik veri veya eksik bir yetenek gibi durumlarda) Tuist ekibine bildirebilir. Ajanlardan bir rapor önermeleri ve bunu yalnızca siz onayladığınızda göndermeleri istenir. Her rapor, Tuist desteğiyle bir konuşma başlatır; destek ekibi size e-posta yoluyla yanıt verebilir. Bir rapor; ajanın ne beklediğini, ne olduğunu, isteğe bağlı bir öneriyi, Tuist kullanıcı kimliğinizi, kullanıcı adınızı ve e-postanızı ile ait olduğunuz organizasyonları içerir. Ajanlar ayrıca sorunun yaşandığı hesabı ve projeyi belirtebilir, böylece ekip hangi organizasyonla iletişime geçeceğini bilir; yalnızca ait olduğunuz hesaplar kabul edilir. Raporları yalnızca Tuist kullanıcısı olarak oturum açmış ajanlar gönderebilir ve her kullanıcı saatte en fazla 10 rapor açabilir. Araç yalnızca `https://tuist.dev/mcp` adresindeki Tuist tarafından barındırılan sunucuda kullanılabilir.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `report_feedback` | Bir Tuist aracı veya istemiyle ilgili bir sorunu bildirin. İsteğe bağlı olarak `tool_name`, sorunun gerçekleştiği `account_handle` ve `project_handle` adlarını belirtin ve bir `suggestion` ekleyin. | `category`, `expected`, `actual` |

#### Kaynak destekli yanıtlar

Bu salt okunur araçlar, ajanların mevcut davranışa dayalı yanıtlar için gerçek kaynak olarak barındırılan sunucuyla birlikte dağıtılan tam Tuist açık kaynak revizyonunu kullanmasına olanak tanır. Yalnızca `https://tuist.dev/mcp` adresinde kullanılabilirler.

Uyumlu istemciler, başlatma sırasında satır içi OAuth kimlik doğrulama bilgilerinin yanı sıra araçların kaynak revizyonu, bağlantılar ve sonuç limitleri hakkında olgusal açıklamalar alır. Bu açıklamalar yanıt stilini veya bir doğrulama iş akışını dikte etmez. Kullanıcılar, önce `ask_tuist` istemini çağırmadan doğrudan soru sorabilir; istem, açıkça kaynak destekli bir iş akışı için kullanılmaya devam eder.

Her işlem için eşzamanlılık, süre, gezinme, okunan bayt sayısı ve yanıt boyutu açısından sabit limitler vardır. Arama ve listeleme sonuçları `truncated` ve `truncation_reason` alanlarını içerir. Bir sonuç kısaltıldığında, sonucu kapsamlı olarak değerlendirmek yerine yolu, dosya desenini veya arama terimini daraltın.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `search_tuist_code` | Kaynak dosyaları arayarak mevcut davranış, varsayılanlar, yapılandırma, özellik kapıları, hata yönetimi veya belgelenmemiş ayrıntılar hakkındaki soruları yanıtlayın. Sonuçlar çevredeki satırları, revizyon sabitlenmiş kaynak bağlantılarını ve tarama istatistiklerini içerir. | `pattern` |
| `list_tuist_files` | İlgili yol bilinmediğinde bir kaynak alt sistemini veya yakındaki testleri keşfedin. Listelemelerin derinliği ve sonuç sayıları sınırlıdır. | Yok |
| `read_tuist_file` | İlgili yolu bulduktan sonra bir uygulama dosyasındaki, çağrı noktasındaki veya testteki belirli bir satır aralığını inceleyin. Kısaltılmış yanıtlar, devam etmek için `next_start_line` sağlar. | `path` |

#### Projeler

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_accounts` | Kimliği doğrulanmış kullanıcı için kullanılabilen kişisel ve organizasyon hesap adlarını, her hesabın proje oluşturup oluşturamayacağı dahil olmak üzere listeler. | Yok |
| `get_organization` | Bir organizasyonun üye dizinini alın. Bekleyen davetler, panodakiyle aynı yönetici iznini gerektirir; davet kabul belirteçleri asla döndürülmez. | `account_handle` |
| `create_organization` | Kimliği doğrulanmış kullanıcı için bir Tuist organizasyonu oluşturun. | `handle` |
| `create_project` | Kimliği doğrulanmış kullanıcının erişebileceği bir hesap altında bir Tuist projesi oluşturun. | `account_handle`, `project_handle` |
| `add_organization_member` | Mevcut bir Tuist kullanıcısını bir organizasyona ekleyin veya mevcut bir üyenin rolünü güncelleyin. `user` (varsayılan), `admin` veya `viewer` kabul eder; burada görüntüleyici panoları ve çalıştırmaları okuyabilir ancak hiçbir şeyi değiştiremez. | `organization_handle`, `email` |
| `invite_organization_member` | Bir e-posta adresini, mevcut bir Tuist kullanıcısına ait olup olmadığına bakmaksızın bir organizasyona davet edin. Tuist, 14 gün sonra sona eren bir kabul bağlantısı e-postası gönderir; sunucu e-posta gönderemediğinde `email_sent` değeri `false` olur ve bağlantı panodan kopyalanmalıdır. `user` (varsayılan), `admin` veya `viewer` kabul eder. Organizasyon yöneticisi izni gerektirir. | `organization_handle`, `email` |
| `cancel_organization_invitation` | Bekleyen bir organizasyon davetini iptal edin, böylece bağlantısı artık kabul edilemez. Organizasyon yöneticisi izni gerektirir. | `organization_handle`, `email` |
| `list_projects` | Kimliği doğrulanmış kullanıcının erişebileceği tüm projeleri listeler. | Yok |
| `get_project` | Bir projenin yapılandırmasını ve bağlı depo URL’sini alın. | `account_handle`, `project_handle` |
| `connect_project_repository` | Bir projeyi, hesabın GitHub Uygulaması kurulumunun erişebileceği bir GitHub deposuna bağlayın. Proje, deponun varsayılan dalını benimser. Proje yöneticisi izni gerektirir. | `account_handle`, `project_handle`, `repository_full_handle` |
| `disconnect_project_repository` | Bir projenin GitHub deposuna olan bağlantısını kaldırın. Proje yöneticisi izni gerektirir. | `account_handle`, `project_handle` |

#### Hesap belirteçleri

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_account_tokens` | Belirteç değerlerini açığa çıkarmadan hesap belirteci meta verilerini listeler. | `account_handle` |
| `get_account_token` | Değerini açığa çıkarmadan hesap belirteci meta verilerini alın. | `account_handle`, `token_id` |
| `list_project_tokens` | Belirteç değerlerini açığa çıkarmadan proje belirteci meta verilerini listeler. | `account_handle`, `project_handle` |

#### AI abonelikleri

Bu araçlar, kimliği doğrulanmış kullanıcının kendi Claude ve ChatGPT aboneliklerini, iş parçacıkları gibi AI özellikleri için yönetir. Kullanıcı kimlik doğrulaması ve AI özelliklerine erişim gerektirirler; yalnızca bağlantı meta verilerini döndürürler, asla kimlik bilgilerini döndürmezler. Bağlantıyı kesmek kaydedilen kimlik bilgilerini siler ancak sağlayıcıdaki yetkilendirmeyi iptal etmez.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_ai_subscriptions` | Her aboneliğin bağlı olup olmadığını ve sunucunun onu bağlayıp bağlayamayacağını listeler. | Yok |
| `connect_claude_subscription` | `claude setup-token` tarafından yazdırılan abonelik belirtecini kaydedin. Belirteç, istemci ve model üzerinden geçen bir sırdır, bu nedenle yalnızca açıkça sağlayın; panonun AI ayarlarına yapıştırmak, konuşma dışında tutar. | `token` |
| `start_chatgpt_subscription_login` | Bir OpenAI cihaz oturum açma işlemini başlatın ve kullanıcının oraya gireceği doğrulama URL’sini ve kodunu, artı bir `login_id` döndürün. 15 dakika sonra sona erer. | Yok |
| `poll_chatgpt_subscription_login` | Bekleyen bir oturum açmayı kontrol edin: kullanıcı kodu onaylayana kadar `pending`, ardından `connected`. | `login_id` |
| `cancel_chatgpt_subscription_login` | Bekleyen bir oturum açmayı iptal edin. Bağlı bir abonelik bağlı kalır. | `login_id` |
| `disconnect_ai_subscription` | Bir aboneliğin kaydedilen kimlik bilgilerini ve varsa bekleyen herhangi bir oturum açmayı silin. | `provider` |

#### Bildirim kuralları

Bu araçlar, kimliği doğrulanmış kullanıcının kendi bildirim kurallarını yönetir: kuralın projelerinde (veya hiçbirini listelemediğinde hakkında bildirim alabileceğiniz herhangi bir projede) yeni bir önizleme gibi bir olay gerçekleştiğinde ve koşulları karşıladığında, Tuist uygulama cihazlarınıza push bildirimi gibi eylemlerini çalıştırır. Kurallar olmadan bildirim almazsınız. Kullanıcı kimlik doğrulaması gerektirirler, yalnızca kendi kurallarınız üzerinde işlem yaparlar ve yalnızca ait olduğunuz hesaplara ait projeleri kabul ederler. Kurallar tüm hesaplarınızı kapsadığından pano sayfalarına sunulmazlar.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_notification_events` | Kuralların abone olabileceği olay türlerini, her biri için koşullarına ait bir JSON Şeması ile birlikte listeler. | Yok |
| `list_notification_condition_options` | Bir projedeki bir olay için koşul değerleri önerin, örneğin son önizlemelerinin izleri ve dalları. | `event`, `account_handle`, `project_handle` |
| `list_notification_rules` | Kurallarınızı listeler. | Yok |
| `create_notification_rule` | Bir olaydan, isteğe bağlı projelerden ve koşullardan ve en az bir eylemden oluşan bir kural oluşturun. | `event`, `actions` |
| `update_notification_rule` | Bir kuralın etkin durumunu, projelerini, koşullarını veya eylemlerini değiştirin. | `rule_id` |
| `delete_notification_rule` | Bir kuralı silin. | `rule_id` |

#### Sürekli entegrasyon çalıştırıcıları

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_runner_jobs` | Bir hesap için sürekli entegrasyon çalıştırıcı işlerini listeler. | `account_handle` |
| `get_runner_job` | Bir sürekli entegrasyon çalıştırıcı işini alın; makinesinin belleğinin dolup dolmadığı, neyi durdurduğu ve neyin değiştirileceği dahil. | `account_handle`, `workflow_job_id` |
| `list_runner_job_steps` | Bir sürekli entegrasyon çalıştırıcı işi için kaydedilen adımları listeler. | `account_handle`, `workflow_job_id` |
| `list_runner_job_metrics` | Bir sürekli entegrasyon çalıştırıcı işi için kaydedilen makine metriklerini listeler. | `account_handle`, `workflow_job_id` |
| `list_runner_job_logs` | Bir sürekli entegrasyon çalıştırıcı işi için yakalanan en fazla 500 günlük satırını listeler. | `account_handle`, `workflow_job_id` |
| `list_runner_workflows` | Bir hesap için sürekli entegrasyon iş akışı özetlerini listeler. | `account_handle` |
| `list_runner_profiles` | Bir hesap için sürekli entegrasyon çalıştırıcı profillerini, her birinin `runs-on` etiketiyle birlikte listeler. | `account_handle` |
| `get_runner_catalog` | Bir çalıştırıcı profilinin kullanabileceği makine şekillerini ve Xcode sürümlerini listeler. | `account_handle` |
| `create_runner_profile` | Bir platform, bir makine şekli ve macOS'ta bir Xcode sürümü ile bir çalıştırıcı profili oluşturun. İsteğe bağlı olarak hangi dalların önbellek birimlerini kaydedeceğini ayarlayın. Hesap yöneticiliği veya `account:runners:write` kapsamı gerektirir. | `account_handle`, `name`, `platform`, `vcpus`, `memory_gb` |
| `update_runner_profile` | Bir çalıştırıcı profilinin makine şeklini, Xcode sürümünü veya özel önbellek birimi değişikliklerini hangi dalların kaydedeceğini değiştirin. Atlanmış alanlar değerlerini korur. Hesap yöneticiliği veya `account:runners:write` kapsamı gerektirir. | `account_handle`, `profile_name` |
| `delete_runner_profile` | Kullanıcı onayından sonra bir çalıştırıcı profilini silin. Varsayılan profiller silinemez. Hesap yöneticiliği veya `account:runners:write` kapsamı gerektirir. | `account_handle`, `profile_name` |

Çalıştırıcı birimi araçları, Birimler panosuyla aynı verileri gösterir. Okuma araçları çalıştırıcı erişimi gerektirir; temizleme işlemi hesap yöneticiliği veya `account:runners:write` kapsamı ve kullanıcı onayı gerektirir.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_runner_volumes` | Ada ve depoya göre filtreleyin, birimleri sıralayın ve sayfalara bölün. | `account_handle` |
| `get_runner_volume` | Depo, platform, kapasite, kullanılan alan ve son kullanım. | `account_handle`, `volume_id` |
| `list_runner_volume_jobs` | Sayfalanmış iş ve iş akışı referansları, önbellek durumu, isabet sonucu ve bağlama süresi. | `account_handle`, `volume_id` |
| `list_runner_job_volumes` | Bir iş tarafından bağlanan birimler. | `account_handle`, `workflow_job_id` |
| `get_runner_volume_analytics` | Depolama serileri, iş çalıştırmaları, isabet oranı ve eğilimler. İsteğe bağlı `volume_id`, `start` ve `end` (ISO 8601); varsayılan yedi gün, maksimum 90. | `account_handle` |
| `delete_runner_volume` | Bir birimi ve kaydedilen içeriğini silin. Çalışan işler özel kopyalarını tutar ancak bunları kaydedemez; aynı anahtara sahip sonraki işler boş başlar. | `account_handle`, `volume_id` |

Listeler `page` ve `page_size` (en fazla 100) kabul eder. Birim envanteri ayrıca `name` ve `repository` (tam eşleşmeler, AND ile birleştirilmiş), `sort_by` (`volume`, `repository`, `used_space`, `capacity`, `last_used`) ve `sort_order` (`asc`, `desc`) kabul eder. Bilinmeyen ölçümler ve isabet sonuçları `null` olarak kalır. Önbellek durumu, birim değişikliklerinin kaydedilip kaydedilmediğini açıklar, iş başarısını değil.

#### Sandbox'lar

Sandbox araçları, Sandbox'lar panosuyla aynı verileri ve eylemleri, [API](https://tuist.dev/api/docs) ile aynı erişimle sunar: hesap üyeleri sandbox'ları listeleyebilir, alabilir, oluşturabilir, duraklatabilir, devam ettirebilir ve silebilir, ancak bir ajan ortamı, Amp veya uzak yürütme sunan sandbox'lar ile analiz ve arşiv araçları hesap yöneticiliği gerektirir. Salt okunur görüntüleyiciler bunları kullanamaz. Hesabın sandbox'ların etkinleştirilmiş olması gerekir. Panonun sandbox sayfaları salt okunur araçları kaydeder.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_sandboxes` | Sandbox'ları durumları, şekilleri ve zaman damgalarıyla sayfalandırın. İsteğe bağlı `search` (sandbox'taki metin, Amp Orb veya Anthropic oturum kimliği), `status`, `vcpus`, `sort_by` (`created`, `last_active`, `identifier`) ve `sort_order`. | `account_handle` |
| `get_sandbox` | Bir sandbox'ın durumu, şekli, düğümü, arşivi ve zaman damgaları. | `account_handle`, `sandbox_id` |
| `get_sandbox_analytics` | vCPU-saatleri, oluşturulan sandbox'lar, oturum, kurulum ve başlatma süreleri ve hesabın limitlerine karşı tepe vCPU'lar, bellek ve disk, eğilimlerle birlikte. İsteğe bağlı `start` ve `end` (ISO 8601); varsayılan 30 gün, maksimum 90. | `account_handle` |
| `create_sandbox` | Boş bir sandbox'ı başlatın ve çalıştığında döndürün. İsteğe bağlı `platform` (`linux` veya `darwin`), `template`, `vcpus` ile `memory_mb` (Linux: 2x4096, 4x8192 veya 8x16384, varsayılan 2x4096; macOS: 8x8192, 8x16384 veya 8x24576, varsayılan 8x8192) ve `workspace_gb`. | `account_handle` |
| `pause_sandbox` | Çalışan bir sandbox'ın anlık görüntüsünü düğümünün diskine alın. | `account_handle`, `sandbox_id` |
| `resume_sandbox` | Duraklatılmış veya arşivlenmiş bir sandbox'ı devam ettirin. | `account_handle`, `sandbox_id` |
| `archive_sandbox` | Duraklatılmış bir sandbox'ın disklerini nesne depolamaya taşımayı sıraya alın. | `account_handle`, `sandbox_id` |
| `delete_sandbox` | Kullanıcı onayından sonra bir sandbox'ı ve disklerini silin. | `account_handle`, `sandbox_id` |

#### Amp çalışma alanları

Bu araçlar, orb'ların token olmadan Tuist'e oturum açmasına olanak tanıyan <.localized_link href="/guides/server/authentication#amp-orbs">Amp çalışma alanı bağlantılarını</.localized_link> yönetir. Panonun Entegrasyonlar sayfasıyla aynı yalnızca yönetici iznini kullanırlar. Bir orb'daki bir ajan kendi kimliklerini `$AMP_WORKSPACE_ID` ve `$AMP_PROJECT_ID` üzerinden okuyabilir. Bir bağlantının kabul ettiği her orb, hesaptaki tüm projelere CI erişimi kazanır, bu nedenle ajanlar bağlanmadan önce kullanıcıyla onaylamalıdır.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_amp_workspace_connections` | Hesabın bağlı Amp çalışma alanlarını ve her birinin sınırlandırıldığı projeyi, varsa listeler. | `account_handle` |
| `connect_amp_workspace` | Bir Amp çalışma alanını bağlayın. İsteğe bağlı `project_id`, oturum açmayı tek bir Amp projesinin orb'larıyla sınırlar. | `account_handle`, `workspace_id` |
| `disconnect_amp_workspace` | Bir çalışma alanının bağlantısını kesin. Orb'larının zaten sahip olduğu oturumlar sona erene kadar geçerli kalır. | `account_handle`, `connection_id` |

#### Claude ortamları

Bu araçlar, Claude Managed Agents'ın kendi barındırdığı ortamlarını bağlayarak oturumlarının Tuist sandbox'larında çalışmasını sağlar; tıpkı Ayarlar → Entegrasyonlar → Claude bölümünde olduğu gibi. Hesap yönetimi ve sandbox'ların etkinleştirilmesini gerektirirler. Bir ajan, Anthropic'in API'si ile ortamı oluşturabilir ancak ortam anahtarını yalnızca Claude Console üretir, bu nedenle ajan kullanıcıdan bu anahtarı ister. Tuist, oturumları bir Anthropic API anahtarı veya iş yükü kimlik federasyonu ile başlatır ve kaydetmeden önce ortamı bu kimlik bilgisiyle getirir. Anthropic tarafındaki kurulum kullanıcının kendi Anthropic kimlik bilgilerini kullanır; Tuist bunları asla almaz. Anahtarlar istemci ve model üzerinden geçtiği için bunları yalnızca açıkça sağlayın.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_claude_environments` | Bağlı ortamları ve her birinin kullandığı kimlik bilgisini listeler; ayrıca bir federasyon kuralının güvenmesi gereken yayıncı URL'sini ve konu önekini içerir. | `account_handle` |
| `connect_claude_environment` | Bir ortamı `api_key` ile veya `organization_id`, `workspace_id`, `service_account_id` ve `federation_rule_id` kullanarak bağlayın. İsteğe bağlı `platform`, `vcpus` ve `memory_mb` sandbox şeklini belirler. | `account_handle`, `environment_id`, `environment_key` |

#### Webhook'lar

Webhook araçları, panodakiyle aynı yalnızca yönetici iznini kullanır. Teslimat denemeleri, uç nokta için kaydedilen istek ve yanıt verilerini içerir ancak uç nokta imzalama gizli anahtarını asla içermez.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_webhook_endpoints` | Bir hesap için webhook uç noktalarını listeler. | `account_handle` |
| `get_webhook_endpoint` | Bir webhook uç noktasını alır. | `account_handle`, `webhook_endpoint_id` |
| `list_webhook_delivery_attempts` | Bir uç nokta için teslimat denemelerini listeler. | `account_handle`, `webhook_endpoint_id` |
| `get_webhook_delivery_attempt` | Bir teslimat denemesini alır. | `account_handle`, `webhook_endpoint_id`, `delivery_attempt_id` |

#### Xcode derlemeleri

Xcode, Gradle, Bazel, Mix ve Cargo için derleme ayrıntısı araçları, mevcut `custom_metadata: {tags, values}` yapısını, raporlandığında altyapı gözlemleri dahil olmak üzere ortaya çıkarır. Değerler dize olarak kalır ve bilinmeyen anahtarlar korunur. Örneğin, `tuist.cpu.available_processors` çalışma zamanında kullanılabilen mantıksal işlemcileri tanımlarken, `tuist.gradle.max_workers` bir Gradle çalışan sınırıdır ve `tuist.jvm.max_heap_bytes` bir JVM yığın sınırıdır, ana makine belleği değil. Bunlar güvenilmeyen istemci gözlemleridir, doğrulanmış çalıştırıcı kimlikleri değildir. Eksik gözlemler eksik kalır; içe aktarılan günlükler ve eski istemcilerde altyapı meta verileri olmayabilir. Meta veri, koordineli bir istemci/protokol güncellemesini beklemektedir.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_xcode_builds` | Bir proje için Xcode derleme çalıştırmalarını listeler. | `account_handle`, `project_handle` |
| `get_xcode_build` | Belirli bir Xcode derleme çalıştırması hakkında, ham `.xcactivitylog` dosyasını içeren arşiv için geçici bir indirme URL'si dahil olmak üzere ayrıntılı bilgi alır. | `build_run_id` |
| `list_xcode_build_targets` | Belirli bir Xcode derleme çalıştırması için derleme hedeflerini listeler. | `build_run_id` |
| `list_xcode_build_files` | Belirli bir Xcode derleme çalıştırması için derlenmiş dosyaları listeler. | `build_run_id` |
| `list_xcode_build_steps` | Günlük metni olmadan, zamanlamalar ve sonuçlarla birlikte kaydedilmiş derleme adımlarını listeler. | `build_run_id` |
| `get_xcode_build_step` | Günlüğü ve kırpma bayrağı dahil olmak üzere tek bir kaydedilmiş derleme adımını alır. | `build_run_id`, `step_id` |
| `list_xcode_build_issues` | Belirli bir derleme çalıştırması için derleme sorunlarını (uyarılar ve hatalar) listeler. | `build_run_id` |
| `list_xcode_build_cache_tasks` | Belirli bir Xcode derleme çalıştırması için önbelleklenebilir görevleri (önbellek isabetleri/kaçırılanlar) listeler. | `build_run_id` |
| `list_xcode_build_cas_outputs` | Belirli bir Xcode derleme çalıştırması için [içerik adreslenebilir depolama](https://en.wikipedia.org/wiki/Content-addressable_storage) çıktılarını listeler. | `build_run_id` |

`list_xcode_build_steps`, varsayılan olarak 20 adımdan oluşan sayfalar döndürür (`page_size` aracılığıyla maksimum 100), gezinme için `page` ve `pagination_metadata` ile birlikte. Başlıklar, projeler veya hedeflerle eşleşmek veya tam `project`, `target`, `category` (örneğin, `swiftCompilation`) ve `status` (`success` veya `failure`) filtrelemek için `search` kullanın. En yavaş olanı önce getirmek için `duration_ms` ile veya kronolojik sıra için `start_ms` ile sıralayın. Adım kimlikleri beraberlikleri bozar ve tam 64 bit hassasiyetlerini korumak için ondalık dizeler olarak döndürülür. Kimlikler bir derleme kapsamındadır ve derlemeler arasında eşleştirilmemelidir.

İsteğe bağlı `start_ms` ve `end_ms`, derleme başlangıcından itibaren milisaniye cinsinden bir zaman aralığıyla örtüşen adımları seçer; bitiş hariçtir. Her iki araç da `build_run_id` olarak bir derleme UUID'sini veya pano URL'sini kabul eder. Döndürülen adım `id` değerini, günlüğünü almak için `step_id` olarak değişmeden iletin. Günlükler adım başına en fazla 64 KiB tutar ve `log_truncated` atlanan çıktıyı belirtir.

Adımlar, Xcode derlemeleri işlendiğinde varsayılan olarak toplanır. Kaydedilmiş adım verileri 90 gün boyunca saklanır. Liste yanıtı `availability` içerir: Filtreler hiçbirini eşleştirmese bile kaydedilmiş adımlar varsa `available`; derleme hala işleniyorsa ve henüz adımı yoksa `processing`; veya adımlar kaydedilmediyse veya süresi dolduysa `unavailable`.

Aynı işlemler, aynı filtreler ve sayfalama ile HTTP API üzerinde `GET /api/projects/{account_handle}/{project_handle}/xcode/builds/{build_id}/steps` ve `GET /api/projects/{account_handle}/{project_handle}/xcode/builds/{build_id}/steps/{step_id}` adreslerinde mevcuttur. Her ikisi de derlemenin projesine okuma erişimi gerektirir.

#### Gradle derlemeleri

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `get_gradle_integration_guide` | Tam kimlik doğrulama, proje kurulumu, Gradle eklentisi, önbellek politikası ve iki derlemeli doğrulama iş akışını döndürür. Ajanlar, mevcut bir Android veya Gradle projesini düzenlemeden önce bunu çağırmalıdır. | Yok |
| `list_gradle_builds` | Özel meta veriler dahil olmak üzere bir proje için Gradle derleme çalıştırmalarını listeler. İsteğe bağlı `tag` parametresi ile özel bir etikete göre filtreleyin. | `account_handle`, `project_handle` |
| `get_gradle_build` | Derleme meta verilerini, görev/önbellek sayılarını ve `failures` değerlerini alın: başarısız olan her görevin ve yapılandırma adımının hata mesajı. | `build_run_id` |
| `list_gradle_build_tasks` | Görev sonuçlarını, bileşik derleme kimliğini, önbelleklenebilirliği, artımlı durumu ve hata mesajlarını listeler. | `build_run_id` |
| `list_gradle_build_steps` | Arama, meta veri ve örtüşen zaman filtreleriyle zamanlanmış görevleri, yapılandırmayı ve dönüşümleri listeler. | `build_run_id` |
| `get_gradle_build_step` | Kaydedilmiş adım meta verilerini opak kimliğe göre inceleyin; başarısız bir görevin veya yapılandırma adımının `log` değeri, onun hata mesajıdır. | `build_run_id`, `step_id` |

Gradle ve Bazel adım listeleri varsayılan olarak 20 sonuç döndürür (maksimum 100), `search`, tam `project`, `target`, `category` ve `status` eşleşmelerini, örtüşen `start_ms` / `end_ms` filtrelerini (bitiş hariç) ve `duration_ms` veya `start_ms` sıralamasını destekler. Döndürülen kimlikleri değişmeden iletin; bunlar kendi derlemeleri kapsamındadır. Listeler `time_origin` ve `coverage` gösterir. Eski Gradle raporları, derleme başlangıcı yüklenmediği için `first_recorded_timestamp` kullanır. Bazel profilleri, `trace_profile` kapsama alanı ve zaman kaynağı olarak `profile_start` ile tüm kaydedilen aralıkları gösterir. Eski derlemeler, saklanan BEP özetlerine geri döner. Kaynak kayıtlar 90 gün sonra sona erer. Bazel ayrıntıları, yayınlandığında temizlenmiş eylem günlüklerini içerir. Başarısız bir görevin veya yapılandırma adımının Gradle ayrıntıları, Tuist Gradle eklentisinin `log` olarak bildirdiği hata mesajını içerir: istisna mesajı ve neden zinciri, Gradle konsolunun yazdırdığı gibi, yığın izleri veya görev çıktısı olmadan, proje içindeki yollar göreceli hale getirilerek ve kimlik bilgileri ile diğer yerel yollar sansürlenerek, adım başına en fazla 16 KiB ve derleme başına 32 başarısız adım. Diğer Gradle adımları, eski eklenti sürümleri tarafından bildirilen derlemeler ve kimlik bilgisi içermeyen raporlar null `log` değerine sahiptir. Yapılandırma adımları, başarısız olduklarında `failure` ve aksi takdirde `unknown` bildirir. `compare_builds` istemi, tam Bazel izlerini saklanan özetlerden ayırt etmek için bu kapsama alanını kullanır ve ajanları, daha geniş çağrı çıktısını kontrol etmeden önce eylem sonuçları ve günlükler için adım ayrıntılarına yönlendirir.

Tek adımlı araçlar `get_gradle_build_step` ve `get_bazel_build_step`, bir adımı kimliğine göre alır ve zaman filtrelerini kabul etmez; adımları zaman aralığına göre filtrelemek için ilgili liste araçlarını kullanın.

Saklanan özetlerden döndürülen Bazel adım kimlikleri, bir adım listelenip alınırken tam bir profil gelirse okunabilir kalır. Adım verilerinin süresi dolmuş indekslenmiş bir profil, kullanılamıyor olarak bildirilir. Gradle adım listeleri, sıfır süreli önbelleğe alınmış ve atlanmış işlemleri içerir.

#### Bazel çağrıları

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `get_bazel_integration_guide` | Kimlik doğrulama, proje kurulumu, Bazel yapılandırması ve doğrulama iş akışını döndürür. | Yok |
| `list_bazel_invocations` | Tamamlanmış [Bazel Build Event Protocol](https://bazel.build/remote/bep) çağrılarını en yeniden eskiye doğru, derleme metrikleri, sınırlı bir yürütme zaman çizelgesi, kritik yol tanılama ve bir proje için ilişkili uzak önbellek toplamlarıyla listeler. `status`, `git_branch`, `git_commit_sha`, `is_ci` ve `command` ile filtreleyin. | `account_handle`, `project_handle` |
| `get_bazel_invocation` | Derleme metrikleri, sınırlı bir yürütme zaman çizelgesi, kritik yol tanılama ve ilişkili uzak önbellek toplamlarıyla tamamlanmış tek bir Bazel çağrısını alın. | `account_handle`, `project_handle`, `invocation_id` |
| `list_bazel_build_steps` | Filtreler ve açık kapsama alanı ile kaydedilmiş Bazel profil aralıklarını listeler. | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_build_step` | Kaydedilmiş bir Bazel adımını ve bunun yayınlanan eylem sonucunu ve temizlenmiş günlüğünü inceleyin. | `account_handle`, `project_handle`, `invocation_id`, `step_id` |
| `list_bazel_invocation_logs` | Bir Bazel çağrısı için yakalanan temizlenmiş günlükleri yürütme sırasına göre listeler: Bazel'in ilerleme çıktısının sınırlı kuyruğu ve `test.log` yapıtları. İsteğe bağlı `stream` (`stdout` veya `stderr`), `source` (`progress` veya `test_log`), `target_label` ve `errors` filtreleri sonuçları daraltır. | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_invocation_log` | Bir Bazel çağrısı için yakalanan tek bir temizlenmiş günlük parçasını alın. | `account_handle`, `project_handle`, `invocation_id`, `invocation_log_id` |
| `list_bazel_cache_events` | İşlemi, uç noktası ve gözlem zamanı ile ham Bazel uzak önbellek gözlemlerini listeler; isteğe bağlı olarak bir çağrı, sonuç veya işlemle daraltılabilir. | `account_handle`, `project_handle` |
| `get_bazel_cache_event` | Tek bir ham Bazel uzak önbellek gözlemini alın. | `account_handle`, `project_handle`, `cache_event_id` |

`list_bazel_invocations` filtreleri tam eşleşmelerdir ve aynı saniyede biten çağrılar çağrı kimliğine göre sıralanır. Bir dal üzerindeki en son başarısız çağrıyı bulmak için bunu `status: "failure"`, `git_branch` ve `page_size: 1` ile çağırın. REST uç noktası `GET /api/projects/{account_handle}/{project_handle}/bazel/invocations` aynı filtreleri kabul eder.

Test günlükleri, geldikleri test sonucunun `target_label` ve deneme `status` değerlerini taşır, bu nedenle `target_label: "//foo:bar_test"` yalnızca o hedefin test günlüklerini döndürür. `errors: true`, başarısız denemelerin test günlüklerini ve Bazel raporlayıcısının `ERROR:`, `FAIL:` veya `TIMEOUT:` ile başladığı bir satır içeren stderr ilerleme parçalarını döndürür. İlerleme çıktısı hedeflere atanmaz ve atama kaydedilmeden önce yazılan günlükler boş alanlara sahiptir. Başarısız eylemler ve kendi çıktıları `list_bazel_build_steps` üzerinden hedef başına ve test çalıştırması araçlarından test senaryosu başına başarısızlıklar olarak mevcuttur.

#### Cargo derlemeleri

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_cargo_builds` | Bir proje için Cargo derlemelerini en yeniden eskiye doğru listeler. `git_branch`, `status`, `is_ci` veya `command` ile filtreleyin. Cargo test yürütme sonuçları bu derleme listesi üzerinden değil, test araçları üzerinden mevcuttur. | `account_handle`, `project_handle` |
| `get_cargo_build` | Derleme meta verilerini, toplam önbellek sayaçlarını ve tanılama bilgileriyle birlikte en fazla 500 kaydedilmiş derleyici işini alın. `compilations_truncated`, atlanan işleri belirtir; tanılama bilgileri yalnızca döndürülen işleri kapsar. | `account_handle`, `project_handle`, `build_id` |

Doğrulanmış görev kararlarını ve CAS işlemlerini almak için `get_cargo_build` üzerinde `include_cache_inspection: true` ayarlayın; bu 4 MB ile sınırlıdır. Varsayılan olarak ve kayıtlar eksik veya geçersiz olduğunda `cache_inspection` null değerindedir. Kısmi yakalama `truncated` bayrağına saygı gösterin; aktarımlar her görev isabetinin yerel/uzak kökenini belirlemez. HTTP ayrıntı uç noktası aynı sorgu parametresini kabul eder.

#### Mix derlemeleri

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_mix_builds` | Özel meta veriler dahil olmak üzere bir proje için Mix (Elixir) derleme derlemelerini en yeniden eskiye doğru listeler. `git_branch`, `status`, `is_ci` veya `mix_env` ile filtreleyin. | `account_handle`, `project_handle` |
| `get_mix_build` | Derleme meta verilerini, tanılama sayılarını ve bağımlılık önbellek özetini alın. | `account_handle`, `project_handle`, `build_id` |

#### Derleme izleri

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `get_build_trace` | Bir Xcode, Gradle, Bazel veya Mix derlemesinin zaman çizelgesini [Perfetto](https://ui.perfetto.dev) içinde açabileceğiniz bir iz dosyası olarak indirmek için bir bağlantı alın. | `account_handle`, `project_handle`, `build_id` |

`build_id`, derleme çalıştırma kimliğidir (Bazel için çağrı kimliği) veya derlemenin kontrol paneli URL'sidir. Döndürülen `trace_url`, bir [Chrome Trace Event](https://docs.google.com/document/d/1CvAClvFfyA5R-PhYUmn5OOQtYMH4h6I0nSsKchNAySU) JSON dosyası sunar. Bağlantıya sahip olan herkes, aramadan bir saat sonra gelen `expires_at` tarihine kadar başka kimlik bilgisi olmadan o derlemenin izini indirebilir. Ajanlar bunu `curl` ile indirebilir, Perfetto'da açmanız için size verebilir veya Perfetto'nun `trace_processor` özelliğiyle sorgulayabilir. İz, paralellik tarafından şeritlere paketlenmiş kaydedilmiş adımları, tüm derlemeyi kapsayan bir parçayı ve derleme makine ölçümlerini kaydettiğinde CPU ve bellek sayaçlarını içerir. Günlükler hariç, yukarıdaki adım araçlarıyla aynı verileri tutar. Kontrol paneli, her derlemenin Zaman Çizelgesi sekmesinden aynı dosyayı sunar.

#### Once çalıştırmaları

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_once_runs` | Bir proje için Once çalıştırmalarını en yeniden eskiye doğru listeler. `kind` (`build`, `test` veya `generic`), `status`, `is_ci` veya `git_branch` ile filtreleyin. Tamamlanmamış çalıştırmaların durumu `in_progress` olur. | `account_handle`, `project_handle` |
| `get_once_run` | Eylem toplamları, önbellek özeti ve test çalıştırmaları için test toplamlarıyla birlikte bir çalıştırmayı alın. | `account_handle`, `project_handle`, `run_id` |

Cargo derleme, Mix derleme ve Once çalıştırma kimlikleri bir proje içinde benzersizdir. Aynı okumalar HTTP API üzerinden `GET /api/projects/{account_handle}/{project_handle}/cargo/builds`, `.../mix/builds` ve `.../once/runs` adreslerinde mevcuttur; her biri tek bir kimlik için bir ayrıntı uç noktasına sahiptir.

#### Görevler, eylemler, modüller ve dosyalar

Bu proje kapsamındaki araçlar, çalıştırmalar arasındaki kalıcı derleme kimliklerini inceler. `list_build_entities` ile başlayın, ardından döndürülen sabit `id` değerini aynı `kind` ile birlikte `get_build_entity` veya `list_build_entity_history` öğesine, `account_handle` ve `project_handle` ile birlikte iletin. Derleme veya çağrı tanımlayıcısı gerekmez.

| Araç | Açıklama | Gerekli parametreler |
| --- | --- | --- |
| `list_build_entities` | Bir projenin derlemeleri arasında görülen tek bir türdeki görevleri, modülleri, eylemleri veya dosyaları listeler. | `account_handle`, `project_handle`, `kind` |
| `get_build_entity` | Seçilen dönem için yerel kimliği ve analitik verileriyle birlikte tek bir derleme varlığını alın. | `account_handle`, `project_handle`, `kind`, `id` |
| `list_build_entity_history` | Tek bir derleme varlığının kaydedilmiş yürütmelerini, derlemelerini veya önbellek olaylarını en yeniden eskiye doğru listeler. | `account_handle`, `project_handle`, `kind`, `id` |

| `kind` | Araç zinciri | Geçmiş listeleri |
| --- | --- | --- |
| `bazel_actions` | Bazel eylemleri | BEP tarafından bildirilen eylem yürütmeleri |
| `gradle_tasks` | Gradle görevleri | Görev yürütmeleri |
| `xcode_modules` | Xcode modülleri | Derlemeler ve modül önbellek olayları |
| `once_actions` | Once eylemleri | Yürütmeler |
| `mix_files` | Mix derlenmiş dosyalar | Derlemeler |
| `mix_modules` | Mix derlenmiş modüller | Derlemeler |
| `cargo_crates` | Cargo kasaları | Kaydedilmiş rustc çağrıları |

Bu araçlar kademeli olarak sunulmaktadır ve yalnızca etkinleştirildikleri projeler için veri döndürür; diğer projeler için boş sonuç yerine hata döndürür. Bir tür, yalnızca ilgili derleme araç zincirini kullanan projeler için kullanılabilir. Araçlar, sınırlı `start_at`/`end_at` filtrelerini, `environment` (`any`, `ci` veya `local`) ve tam eşleşen bir `branch` kabul eder. `list_build_entities`, `q` kabul eder; `list_build_entity_history` şeffaf olmayan `after`/`before` imleçlerini destekler. Bilinmeyen zamanlama veya önbellek gözlemleri sıfır veya isabetsizlik haline gelmek yerine kullanılamaz durumda kalır. Geçmiş, mevcut çalıştırma araçlarını kullanarak detaylı inceleme için kaydedilen üst öğeye ve yerel yürütmeye başvurur.

`get_build_entity` ölçümleri, kaydedilmiş zamanlamaya sahip gözlem sayısını içeren `duration_samples` değerini içerir: gerçek sıfır süreler sayılır, eksik zamanlama sayılmaz. Bu sayı, gözlem sayısından daha düşük olabilir; kullanılamayan süre istatistikleri null olarak kalır.

Xcode modül süreleri, derleme günlüklerindeki ölçülen hedef derlemelerden gelir. Modül önbelleği çözümlemeleri ve derleme işi olmayan hedefler süre örneklerine katkıda bulunmaz. Derleme gözlemleri Xcode derlemesine başvurur; önbellek olayları oluşturma veya önbellek komutuna başvurur.

Bazel eylemleri, hedef etiketi, anımsatıcı ve yapılandırılmış birincil çıktı ile tanımlanır; girdiye bağımlı önbellek özetlerine güvenmeden ayrı eylemleri ve yapılandırmaları distinct tutar. Geçmiş, BEP tarafından bildirilen yürütmeleri kaydeder, önbellek aramalarını veya iz profili aşamalarını değil. Tam yürütme kapsamı `--build_event_publish_all_actions` gerektirir; yapıt teslimi en iyi çabayla yapılır, bu nedenle eksik gözlemler hiçbir işin çalışmadığına dair kanıt değildir. Kararlı kimliği veya yürütme başlangıcı olmayan eski Kura yükleri kabul edilmeye devam eder ancak indekslenmez. Eksik bitiş zamanı ölçümleri kullanılamaz durumda kalır ve gerçek sıfır süreler sayılır.

Mix modül süreleri, bağımsız olarak ölçülen modül işini değil, içeren dosyanın derlenmesini ölçer. Once eylemleri, istemci hedef eşlemelerini bildirdiğinde bildirilen hedef/yetenek/dizin yuvalarını kullanır; yalnızca tanılama etiketleri kararlı kimlikler değildir. Mevcut istemciler ve çalıştırma düzeyi araçları değişmeden desteklenmeye devam eder.

Cargo kasaları, tam olarak kaydedilen kasa kökü, adı ve türüne göre gruplanır. Checkout yolu değişiklikleri geçmişleri bölebilir ve derleme profilleri, özellikler ve hedef üçlüleri ayırt edilmez. Geçmiş, dosya başına işi veya önbellek isabetlerini değil, rustc çağrılarını ölçer; eksik işler kaldırmaları veya eksiksiz bir çalışma alanı envanterini belirlemez.

Analitik okumalarının sınırlı bellek ve yürütme süresi vardır. Bir sorgu bu sınırları aşarsa, araç boş bir sonuç uydurmak yerine hata döndürür.

Yeni gözlemler dağıtımdan sonra indekslenir; bu özellik mevcut çalıştırma telemetrisini geriye dönük olarak doldurmaz. Kimlik meta verileri, <.localized_link href="/guides/server/data-retention">veri saklama politikası</.localized_link> kapsamında bireysel gözlemlerden daha uzun süre saklanır.

#### Testler

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_test_runs` | Bir proje için test çalıştırmalarını listeler. `query` alanları `git_branch`, `scheme` ve `status`'dür: `field:"value"` tam eşleşme yapar, `field~"value"` büyük/küçük harf duyarsız alt dize eşleşmesi yapar ve başındaki `-` her iki operatörü de olumsuzlar. Örneğin, `-git_branch~"gh-readonly-queue"` birleştirme kuyruğu dallarını hariç tutar. Boşlukla ayrılmış sorgu filtreleri ve açık argümanlar AND mantığıyla birleştirilir. | `account_handle`, `project_handle` |
| `get_test_run` | Sonuç paketi (`.xcresult`) ve oturum arşivi için geçici indirme URL'leri dahil olmak üzere bir test çalıştırması için ayrıntılı ölçümleri alır. | `test_run_id` |
| `list_test_module_runs` | Belirli bir test çalıştırması için test modülü çalıştırmalarını listeler. | `test_run_id` |
| `list_test_suite_runs` | Belirli bir test çalıştırması için test paketi çalıştırmalarını listeler; isteğe bağlı olarak modüle göre filtrelenebilir. | `test_run_id` |
| `list_test_cases` | Bir proje için test senaryolarını listeler (`flaky` gibi filtreleri destekler). | `account_handle`, `project_handle` |
| `get_test_case` | Güvenilirlik oranı, kararsızlık oranı ve çalıştırma sayıları dahil olmak üzere bir test senaryosu için ayrıntılı ölçümleri alır. | `test_case_id` veya `identifier` + `account_handle` + `project_handle` |
| `list_test_case_runs` | Test senaryosu çalıştırmalarını listeler; isteğe bağlı olarak test senaryosuna veya test çalıştırmasına göre filtrelenebilir. | `account_handle`, `project_handle` |
| `get_test_case_run` | Belirli bir test senaryosu çalıştırması için hata ayrıntılarını ve tekrarlamaları alır. | `test_case_run_id` |
| `list_test_case_run_attachments` | Bir test senaryosu çalıştırması için ekleri listeler. Her ek, geçici bir indirme URL'si içerir. | `test_case_run_id` |
| `list_test_case_events` | Bir test senaryosunun sessize alınması veya atlanması gibi durum değişikliklerini listeler. | `test_case_id` |
| `update_test_case` | Bir test senaryosunun durumunu veya kararsız sınıflandırmasını günceller. Bir değişiklik, harici hizmetler dahil yapılandırılmış webhook uç noktalarına bir olay gönderebilir. | `test_case_id` veya `identifier` + `account_handle` + `project_handle` |
| `list_xcode_test_targets` | Bir test çalıştırması için seçici test hedefi sonuçlarını listeler. | `test_run_id` |
| `get_coverage` | Bir projenin kod kapsamını hedefleriyle birlikte, bir commit'te veya bir dalın en son tamamlanan commit'inde alır. `git_commit_sha` veya `branch` olmadan varsayılan dalı okur. | `account_handle`, `project_handle` |
| `list_coverage_files` | Bir commit'in kod kapsamının ölçtüğü dosyaları, satır kapsamlarıyla birlikte, bir commit'te veya bir dalın en son tamamlanan commit'inde listeler. `search`, sıralama ve sayfalamayı destekler. | `account_handle`, `project_handle` |
| `get_coverage_file` | Bir dosyanın kod kapsamını ve işlevlerini bir commit'te veya bir dalın en son tamamlanan commit'inde alır. Her satırın yürütme sayısını almak için `include_lines` ayarlayın. | `account_handle`, `project_handle`, `path` |

Kod kapsamı araçları, kod kapsamı etkinleştirilmiş hesaplara sunulur.

#### Paketler

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_bundles` | Bir proje için paketleri (uygulama ikili dosyalarını) listeler. İsteğe bağlı olarak `git_branch` ve `tags` ile filtreleyin (tüm etiketler tam olarak eşleşmelidir). | `account_handle`, `project_handle` |
| `get_bundle` | Özel etiketler dahil olmak üzere belirli bir paket hakkında ayrıntılı bilgi alır. | `bundle_id` |
| `get_bundle_artifact_tree` | Bir paketin tam yapıt ağacını yola göre sıralanmış düz bir liste olarak alır. | `bundle_id` |

`list_bundles`, derleme çeşitlerini veya ortamları ayırt etmek için `tags: ["paid", "production"]` kabul eder. Etiketler, büyük/küçük harfe duyarlı, harf, rakam, tire veya alt çizgi içeren etiketlerdir; etiket başına en fazla 10 etiket ve 50 karakter bulunur. Liste ve ayrıntı sonuçları `custom_metadata.tags` içerir. Sayfalama sayıları ve dal filtreleri etiketlenmiş sonuçlara uygulanır; `tags` bırakıldığında filtrelenmemiş davranış korunur. Geçersiz etiket filtreleri sorguyu genişletmek yerine hata döndürür.

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
| `list_project_notification_alerts` | Proje bildirim uyarısı kurallarını listeler. Pano ayarları sayfasıyla aynı yönetici iznini gerektirir. Webhook adresleri gizlenmiştir. | `account_handle`, `project_handle` |

### Olaylar

Durumsuz `2026-07-28` Model Bağlam Protokolü yaşam döngüsünü kullanan istemciler, olayları ve yük şemalarını keşfetmek için `events/list` çağrısı yapabilir:

| Olay | Ne zaman gönderilir | Abonelik filtresi |
|-------|-----------------|---------------------|
| `test_case.marked_flaky` | Bir test senaryosu kararsız olmayan durumdan kararsız duruma geçer. | `account_handle`, `project_handle` |
| `build.failed` | Yerel veya sürekli entegrasyon Xcode, Gradle ya da Bazel derlemesi bir başarısızlıkla sonlanır. | `account_handle`, `project_handle` |
| `test_run.failed` | Yerel veya sürekli entegrasyon test çalıştırması bir başarısızlıkla sonlanır; birleştirilmiş parçalı çalıştırma veya terk edilmiş çalıştırma dahildir. | `account_handle`, `project_handle` |
| `ci_job.failed` | Bir Tuist çalıştırıcı işi bir başarısızlıkla tamamlanır. | `account_handle` |

Abone olmak için istemci, olay adını, yukarıda `arguments` içinde listelenen tanıtıcıları ve bir `https://` geri çağırma URL'si ile bir `whsec_` imzalama sırrı içeren bir `webhook` teslimatıyla `events/subscribe` çağrısı yapar. Proje olayları hesap üyeliği ve ilgili test veya derleme verilerine okuma erişimi gerektirir; çalıştırıcı işi olayları hesap üyeliği ve çalıştırıcı okuma erişimi gerektirir. Talep edilen [`auth.md`](https://workos.com/auth-md) erişim belirteçleri, talep edilen hesap belirteçleri ve tarayıcı yetkilendirme izinleri abonelik oluşturabilir; ilişkili kimlik bilgisi artık etkin olmadığında teslimat durur. Her kullanıcı en fazla 25 etkin abonelik tutabilir. Tuist, aboneliği kaydetmeden önce geri çağırmaya bir doğrulama sorgusu gönderir. Geri çağırma, aynı `challenge` değerini içeren bir nesne döndürmelidir. Abonelik varsayılan olarak yedi gün sürer, yeniden abone olunarak yenilenebilir ve kullanıcının erişimi veya kimlik bilgisi kaldırıldığında teslimatı durdurur. İsteğe bağlı `ttlMs` bir saat ile 30 gün arasında sınırlıdır. Tuist zaman aşımına uğramış bir geri çağırmayı yeniden dener ve beş dakikayı kapsayan en az üç ardışık zaman aşımından sonra aboneliği iptal eder; geri çağırmayı restore ettikten sonra yeniden abone olun.

Bir olay gerçekleştiğinde Tuist, kaynak tanımlayıcısını ve pano URL'sini geri çağırmaya gönderir. Derleme ve test çalıştırması hataları ayrıca `is_ci` ve `git_branch` içerir, böylece istemciler yerel hataları yok sayabilir veya dala göre filtreleyebilir. Derleme olayları `build_system` içerir; çalıştırıcı işi olayları hem `workflow_job_id` hem de `workflow_run_id` içerir. İstek, istemcinin kaynağını doğrulayabilmesi için bir abonelik tanımlayıcısı ve [Standard Webhooks](https://www.standardwebhooks.com/) imza üstbilgilerini içerir. Tuist başarısız teslimatları yeniden dener, bu nedenle istemciler yinelenenleri atmak için kararlı `eventId` kullanmalıdır. Yük, test adlarını, günlükleri ve hata mesajlarını dışlar; istemci bu ayrıntıları yukarıdaki araçlarla alabilir ve bir ekibi bilgilendirmeye veya hata ayıklamaya başlamaya karar verebilir. İstemciler teslimatı `events/unsubscribe` ile durdurabilir.

### İstemler

| İstem | Açıklama |
|--------|-------------|
| `fix_flaky_test` | Başarısızlık kalıplarını analiz ederek, kök nedeni belirleyerek ve hedefe yönelik bir düzeltme uygulayarak kararsız bir testi düzeltmeniz konusunda size rehberlik eder. |
| `compare_builds` | Performans gerilemelerini, önbellek değişikliklerini ve derleme sorunlarını belirlemek için derlemeleri karşılaştırmanız konusunda size rehberlik eder. Xcode, Gradle, Bazel ve Cargo projeleri için yerel araçları kullanır. Cargo karşılaştırmaları kısmi derleyici kapsamını korur ve tahmini derleyici işini geçen süre tasarrufundan ayırt eder. |
| `compare_test_runs` | Gerilemeleri, yeni hataları ve kararsız testleri belirlemek için iki test çalıştırmasını karşılaştırmanız konusunda size rehberlik eder. |
| `compare_bundles` | Yapıt ağacındaki boyut değişikliklerini belirlemek için iki paketi karşılaştırmanız konusunda size rehberlik eder. |
| `compare_test_case` | Bir test senaryosunun davranışını iki dal veya zaman dilimi arasında karşılaştırmanız konusunda size rehberlik eder. |
| `compare_generations` | Performans gerilemelerini ve modül önbelleği değişikliklerini belirlemek için iki oluşturma çalıştırmasını karşılaştırmanız konusunda size rehberlik eder. |
| `compare_cache_runs` | Önbellek etkinliği değişikliklerini ve hedef düzeyindeki gerilemeleri belirlemek için iki önbellek çalıştırmasını karşılaştırmanız konusunda size rehberlik eder. |
| `integrate_gradle_project` | Tuist'i mevcut bir Gradle projesine entegre etmeniz konusunda size rehberlik eder. Ayrı araç ve Gradle kimlik doğrulaması, hesap keşfi, proje oluşturma, uzak önbellek politikası, derleme içgörileri ve geri okuma doğrulamasını içerir. |
| `integrate_bazel_project` | Bir Bazel projesi oluşturmanız veya seçmeniz, komut satırını kimlik doğrulamanız, uzak önbelleği ve derleme içgörülerini yapılandırmanız ve entegrasyonu Tuist derleme verileri aracılığıyla doğrulamanız konusunda size rehberlik eder. |
| `integrate_xcode_project` | Tuist'i mevcut bir Xcode projesine entegre etmeniz konusunda size rehberlik eder. Xcode önbelleği, derleme içgörileri, test içgörileri ve test parçalama desteği sunar. |
| `ask_tuist` | Bağlam için genel materyalleri kullanarak ve geçerli davranışın doğruluk kaynağı olarak odaklanmış uygulama ve test kanıtlarını kullanarak bir Tuist sorusunu yanıtlar. Bir `question` gerektirir ve revizyon sabitli kanıtlara atıfta bulunur. |

Proje verisi istemleri, araştırmayı belirli bir projeye daraltmak için `account_handle` ve `project_handle` kabul eder. Karşılaştırma istemleri ayrıca karşılaştırılacak iki öğeyi (ID, pano URL'si veya dal adı ile) belirtmek için `base` ve `head` bağımsız değişkenlerini kabul eder. `ask_tuist`, proje parametreleri yerine bir `question` kabul eder. `integrate_gradle_project` ayrıca uygulanacak Gradle entegrasyonlarının virgülle ayrılmış bir listesi olan `features` kabul eder: `remote_cache`, `build_insights`, `test_insights`, `flaky_tests` ve `test_sharding`. `integrate_bazel_project`, kendi kendine barındırılan veya yerel kurulumlar için isteğe bağlı bir `server_url` kabul eder. `integrate_xcode_project`, `xcode_cache`, `build_insights`, `test_insights` ve `test_sharding` ile `features` kabul eder.

#### Gradle entegrasyonu istemi özellikleri

`integrate_gradle_project` istemi ve `get_gradle_integration_guide` aracı eksiksiz kurulum iş akışını belgeler. Araç ayrıca sunucunun başlatma talimatları tarafından referans alınır; bu da istemleri listelemeyen ajanlar tarafından keşfedilmesini sağlar.

| Özellik | Ajanın yapılandırdığı şey |
|---------|---------------------------|
| `remote_cache` | Gradle'ın derleme önbelleğini etkinleştirir, Tuist uzak önbellek yükleme politikasını yapılandırır ve yalnızca yerel salt okunur kullanıma sahip sürekli entegrasyon çalıştırıcılarından yüklemeleri önerir. |
| `build_insights` | Tuist Gradle eklentisini uygular ve gerektiğinde derleme analitiği yükleme davranışını yapılandırır. |
| `test_insights` | Gradle `Test` görev sonuçlarının otomatik olarak yüklenmesi için Tuist Gradle eklentisini uygular. |
| `flaky_tests` | Kararsız test algılama kurulumunu, isteğe bağlı Gradle Test Yeniden Deneme eklentisi kullanımını ve test karantina yapılandırmasını kılavuzlar. |
| `test_sharding` | `tuistPrepareTestShards` için sürekli entegrasyon iş akışını, parça matrisi oluşturmayı ve `TUIST_SHARD_INDEX` tabanlı test yürütmeyi ekler. |

`features` atlandığında, istem ajandan Gradle projesini düzenlemeden önce kullanıcının hangi entegrasyonları istediğini netleştirmesini veya istekten en küçük kullanışlı seti çıkarmasını ister.

#### Xcode entegrasyonu istemi özellikleri

`integrate_xcode_project` istemi, Tuist'in desteklediği her Xcode entegrasyonunu belgeler:

| Özellik | Ajanın yapılandırdığı şey |
|---------|---------------------------|
| `xcode_cache` | `tuist setup cache`, oluşturulan proje önbellek ayarlarını, manuel Xcode önbellek derleme ayarlarını ve yalnızca sürekli entegrasyon çalıştırıcılarıyla sınırlı bir yükleme politikasını yapılandırır. |
| `build_insights` | `tuist inspect build`, `tuist xcodebuild`, `-resultBundlePath` ve `tuist setup insights` aracılığıyla isteğe bağlı makine metriklerini yapılandırır. |
| `test_insights` | `tuist inspect test`, şema test sonrası eylemlerini ve sürekli entegrasyon test çalıştırmaları için sonuç paketi oluşturmayı yapılandırır. |
| `test_sharding` | `TUIST_SHARD_INDEX` ile Xcode veya oluşturulan proje parça planlamasını ve parça yürütme iş akışını ekler. |

`features` atlandığında, istem ajandan Xcode projesini düzenlemeden önce kullanıcının hangi entegrasyonları istediğini netleştirmesini veya istekten en küçük kullanışlı seti çıkarmasını ister.
