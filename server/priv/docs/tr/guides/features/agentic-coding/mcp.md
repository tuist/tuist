---
{
  "title": "Model Context Protocol (MCP)",
  "titleTemplate": ":title · Ajan tabanlı kodlama · Özellikler · Kılavuzlar · Tuist",
  "description": "Yapay zeka ajanlarına Tuist'in MCP uç noktası üzerinden test içgörülerine ve daha fazlasına erişim sağlayın."
}
---
# Model Context Protocol

[Model Context Protocol (MCP)](https://modelcontextprotocol.io/docs/getting-started/intro), yapay zeka ajanlarının harici hizmetler ve veri kaynaklarıyla etkileşime girmesini sağlayan açık bir standarttır. [Claude](https://claude.ai/), [Claude Code](https://docs.anthropic.com/en/docs/claude-code), [Codex](https://developers.openai.com/codex/) gibi uygulamaların ve [Zed](https://zed.dev), [Cursor](https://www.cursor.com) veya [Visual Studio Code](https://code.visualstudio.com) gibi editörlerin Tuist ile birlikte çalışabilir olmasını sağlar.

Tuist, sunucu tarafında bir Model Context Protocol uç noktasını `https://tuist.dev/mcp` adresinde barındırır. İstemcinizi bu uç noktaya bağlayarak ajanların test içgörleri, kararsız test analizi ve daha fazlası dahil olmak üzere Tuist proje verilerinize erişmesini sağlayabilirsiniz. Çoğu araç, kimliği doğrulanmış kullanıcının panoda zaten görebildiği Tuist verilerini okur. Her araç; salt okunur olup olmadığını, geri alınması zor bir değişikliğe neden olup olmadığını (`destructiveHint`) ve Tuist dışına erişip erişmediğini (`openWorldHint`) belirten açıklamalar sunar. Durumu değiştiren araçlar, her biri hesabın veya projedeki kullanıcının izinleriyle sınırlı olmak üzere şunlardır:

- **Kuruluşlar ve üyeler**: `create_organization`, `add_organization_member` (mevcut bir kullanıcı ekler veya bir üyenin rolünü değiştirir), `invite_organization_member` (herhangi bir adrese davetiye e-postası gönderir) ve `cancel_organization_invitation`.
- **Projeler**: `create_project`, `start_project_logo_upload` ve `complete_project_logo_upload` (logoyu değiştirir), `connect_project_repository` ve `disconnect_project_repository` (GitHub depo bağlantıları).
- **Testler**: `update_test_case` (bir test senaryosunu sessize alır, atlar, yeniden etkinleştirir veya kararsız olarak işaretler; değişiklik hesabın webhook uç noktalarına ulaşabilir).
- **Bildirim kuralları**: `create_notification_rule`, `update_notification_rule` ve `delete_notification_rule`.
- **Sürekli entegrasyon çalıştırıcıları**: `create_runner_profile`, `update_runner_profile` (hangi işlerin önbellek birimlerini kaydettiğini daraltmak bekleyen kayıtları iptal eder), `delete_runner_profile` ve `delete_runner_volume` (birimin kaydedilen içeriğini siler).
- **Sandbox'lar**: `create_sandbox`, `pause_sandbox`, `resume_sandbox`, `archive_sandbox` ve `delete_sandbox` (disklerini siler).
- **Ajan entegrasyonları**: `connect_amp_workspace` (çalışma alanının orb'larına hesaba CI erişimi verir), `disconnect_amp_workspace` ve `connect_claude_environment` (Claude Managed Agents ortamının Tuist sandbox'larında oturumlar çalıştırmasına olanak tanır).

`add_organization_member`, `cancel_organization_invitation`, `complete_project_logo_upload`, `disconnect_project_repository`, `update_test_case`, `update_notification_rule`, `delete_notification_rule`, `update_runner_profile`, `delete_runner_profile`, `delete_runner_volume`, `delete_sandbox` ve `disconnect_amp_workspace` mevcut durumu değiştirdiği veya kaldırdığı için `destructiveHint: true` bildirir. `invite_organization_member`, `update_test_case` ve `connect_claude_environment` e-posta gönderdiği, harici webhook uç noktalarını bildirdiği veya Anthropic'i çağırdığı için `openWorldHint: true` bildirir.

Kişisel Claude ve ChatGPT abonelikleri yalnızca panonun AI ayarlarında bağlanır, bu nedenle abonelik jetonları ve oturum açma işlemleri asla bir Model Context Protocol istemcisinden geçmez. Hesap kurulum araçları kullanıcı kimlik doğrulaması gerektirir. Proje jetonları veya normal hesap jetonları tarafından kullanılamazlar. Bir kullanıcı tarayıcıda bir istemciyi yetkilendirdiğinde veya bir `auth.md` kaydını talep ettiğinde, Tuist bu kimlik bilgisini yalnızca Model Context Protocol uç noktasında kullanıcıyla ilişkilendirir, böylece kurulum araçları istenen iş akışını tamamlayabilir.

Tuist, [2026-07-28 protokolünü](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http) uygular. İstekler durumsuzdur: istemciler her istekle birlikte protokol meta verilerini gönderir ve araçları başlatma olmadan doğrudan çağırabilir. `server/discover` sunucunun kimliğini, yeteneklerini, desteklenen sürümleri ve talimatlarını döndürür. Oturum tanımlayıcıları veya bağımsız olay akışları yoktur. 2025-06-18 veya 2025-03-26 başlatma akışını kullanan istemciler desteklenmeye devam eder; bunlar da sunucu oturumları olmadan çalışır.

## Model Context Protocol ile beceriler

Model Context Protocol araçları ve <.localized_link href="/guides/features/agentic-coding/skills">beceriler</.localized_link> yaptıkları iş açısından örtüşebilir. İkisi arasındaki mevcut örtüşme göz önüne alındığında, her iş akışı için tek bir yaklaşım seçin ve aynı akışta ikisini karıştırmak yerine tutarlı bir şekilde kullanın.

Eklenti yüklemeyi destekleyen istemciler için, ikisini birlikte yüklemek amacıyla <.localized_link href="/guides/features/agentic-coding/plugins">Tuist eklentilerini</.localized_link> kullanın.

## Yapılandırma

İstemcinize uzak bir Model Context Protocol sunucusu olarak `https://tuist.dev/mcp` ekleyin. Sunucunun başlatma talimatları ve genel sunucu kartı, ajanlardan harici kimlik doğrulama belgelerini getirmelerini veya takip etmelerini istemeden, dinamik istemci kaydı ve standart tarayıcı yetkilendirme akışı ile OAuth 2.0'ı satır içinde açıklar. Bu sunucu genelindeki talimatlar iş akışı rehberliğini genel tutar: araç kimlik doğrulaması yerel komut satırı araçlarını veya derleme sistemi entegrasyonlarını kimlik doğrulamaz ve ajanlar istenen değişiklikleri ilgili Tuist araçları aracılığıyla doğrulamalıdır. Derleme sistemine özel kurulum ve kimlik doğrulama kontrolleri entegrasyon kılavuzlarında ve istemlerde belgelenmiştir. Tuist ayrıca hem [Open Authorization](https://oauth.net/2/) keşif meta verilerini hem de güncel [auth.md protokolünü](https://workos.com/auth-md) `https://tuist.dev/auth.md` adresinde ayrı ayrı duyurmaya devam eder.

Kuruluşlarınızdan biri tek oturum açmayı (SSO) zorunlu kılıyorsa, tarayıcıda bir istemciyi yetkilendirmek o kuruluş üzerinden oturum açılmış bir oturum gerektirir ve Tuist gerektiğinde sizi önce sağlayıcıya yönlendirir. Bkz. <.localized_link href="/guides/integrations/authentication/sso#choose-an-enrollment-policy">tek oturum açma</.localized_link>.

Uç nokta, eski oturum tabanlı yaşam döngüsünün yanı sıra, `server/discover` dahil olmak üzere durumsuz `2026-07-28` Model Context Protocol istek yaşam döngüsünü kabul eder. Mevcut istemciler mevcut bağlantı yöntemlerini kullanmaya devam edebilir.

Model Context Protocol olaylarını destekleyen istemciler proje olaylarına abone olabilir. Mevcut olay ve teslimat gereksinimleri için bkz. [Olaylar](#events).

Zaten uzak tarayıcı kimlik doğrulamasını destekleyen istemciler tarayıcıda kimlik doğrulamaya devam edebilir. `auth.md` destekleyen istemciler ve ajanlar anonim olarak kayıt olabilir, güvenilir bir sağlayıcı kimlik iddiası sunabilir veya hizmet tarafından kimliği doğrulanmış bir e-posta talebi başlatabilir. Kayıt, Tuist tarafından imzalanmış bir kimlik iddiası döndürür; ajan bunu standart jeton uç noktasında bir saatlik erişim jetonu ile takas eder. Tuist genel imzalama anahtarını yayınlar ve standart jeton iptalini ve sağlayıcı güvenlik olayı teslimatını destekler.

Kimliği doğrulanmamış bir ajan, Model Context Protocol uç noktası tarafından döndürülen `WWW-Authenticate` üst bilgisini okumalı, korunan kaynak meta verilerini getirmeli, yetkilendirme sunucusu meta verilerini getirmeli ve `agent_auth.skill` URL'sini takip etmelidir. Tuist ayrıca yetkisiz yanıt gövdesinde aynı yerel `auth_md` URL'sini döndürür, böylece dil modeli odaklı istemciler yerel bir istemci entegrasyonuna güvenmeden akışı keşfedebilir. Dağıtım yerel belgesi, uç nokta adları, istek gövdeleri, talep yoklaması ve iddia takası için gerçek kaynaktır.

Bir ajan bir e-posta talebini başlatmadan önce, kullanıcının Tuist hesabı için e-posta adresini onaylamasını istemelidir. Bu adresi bir sağlayıcı profilinden, Git yapılandırmasından, ortam değişkeninden veya oturum meta verilerinden çıkarmamalıdır.

Uç nokta `mcp` kapsam grubunu kullanır. Anonim bir talep öncesi kimlik bilgisi yetenekleri keşfedebilir ve genel entegrasyon rehberlerini okuyabilir, ancak oturum açmış bir kullanıcı olarak değerlendirilmez. Tarayıcı yetkilendirmesinden veya talepten sonra, kimlik bilgisi kullanıcı kapsamına alınır ve her araç, gösterge panelindekiyle aynı yetkilendirme kontrollerini uygular. Ayrıntılar için bkz. <.localized_link href="/guides/server/authentication#scope-groups">kapsam grupları belgeleri</.localized_link>.

Araçlar, kimliği doğrulanmış kullanıcının zaten okuyabildiği projelere çözümlenir. Xcode ve Gradle derleme araçları bir derleme UUID'si veya gösterge paneli URL'si kabul eder. UUID tam olarak bir projeyi tanımlamalıdır; birden fazla projede görünürse, araç başka bir projenin raporunu seçmek yerine bulunamadı döndürür. Proje kapsamındaki gösterge paneli ve API okumaları kullanılabilir durumda kalır. Bildirilen aktör tanımlayıcıları doğrulanmamış etiketlerdir, kimlik bilgileri veya ek erişim hakları değildir.

Derleme listesi ve ayrıntı araçları isteğe bağlı `tuist_version` meta verilerini sunar: Xcode ve Cargo için raporlayan Tuist CLI, Gradle için Tuist Gradle eklentisi ve Mix için `tuist_ex` kitaplığı. Xcode ayrıca, yükleyen CLI'dan farklı olabilen bağlantılı proje oluşturma olayından `tuist_generation_version` değerini de sunar. Eksik gözlemler null olarak bildirilir, sunucudan veya başka bir rapordan çıkarılmaz. Bazel mevcut `bazel_version` değerini kullanır; Once çalıştırma ayrıntıları `once_version` değerini sunar. Bu alanlar bildirilen sürümleri açıklar, doğrulanmış kimliği veya ağ sözleşmesi sürümlerini değil. REST derleme uç noktaları aynı meta verileri sunar. Mevcut entegrasyon ve kararsız test becerileri sürüm alanlarına bağlı değildir ve iş akışı değişikliği gerektirmez.

Bir müşterinin hesabını inceleyen Tuist operatörleri bunu, her çağrıyı kaydeden Tuist'in dahili operasyon araçları aracılığıyla yapar; bu uç noktaya doğrudan bağlantı, kullanıcının kendi üyelikleri dışında hiçbir erişim sağlamaz.

### Pulse

Pulse, hesabın operasyonel metrikleri, günlükleri, izlemeleri ve hataları için salt okunur araçlar sunar; tümü `account_handle` ile adreslenir. İlk üçü Pulse sayfalarını ve bunların REST API'sini yansıtır; diğer beşi bir ajanın telemetriyi doğrudan keşfetmesine olanak tanır ve REST eşdeğeri yoktur:

| Araç | Amaç | `/api/accounts/:account_handle/pulse` altındaki REST eşdeğeri |
| --- | --- | --- |
| `query_pulse` | Pulse sayfası tabloları | `GET /:signal` |
| `get_pulse_analytics` | Pulse sayfası widget'ları | `GET /:signal/analytics` |
| `get_pulse_error_issue` | Bir hata sorunu ve olayları | `GET /errors/issues/:fingerprint` |
| `query_pulse_metrics` | Anlık veya aralıklı PromQL | Yok |
| `list_pulse_labels` | Etiket adları veya bir etiketin değerleri | Yok |
| `search_pulse_logs` | Filtrelenmiş günlük girdileri | Yok |
| `search_pulse_traces` | Filtrelenmiş kapsamlar | Yok |
| `get_pulse_trace` | Bir izlemedeki her kapsam | Yok |

Pulse, bir hesap veya proje herkese açık olsa bile, sunucu tarafından yapılandırılmış kuruluşun mevcut üyeleriyle sınırlıdır. Kullanıcı kimlik doğrulaması veya kullanıcıyla ilişkili bir `mcp` kimlik bilgisi ve hesap okuma yetkisi gerektirir. Proje jetonları, normal hesap jetonları, anonim kayıtlar ve kuruluş üyeliği olmayan operatör erişimi Pulse erişimi sağlamaz. Kimlik bilgileri başka bir arka uç veya telemetri kiracısı seçemez ve yalnızca sunucu tarafından yapılandırılmış hesap Pulse telemetrisine sahiptir, bu nedenle hiçbir araç başka bir hesabın verilerini okuyamaz. Tarayıcı ajanları bu araçları yalnızca Pulse sayfalarında, o sayfanın hesap kapsamında alır.

REST bir kullanıcı kimlik bilgisi gerektirir. OAuth ve `auth.md` kullanıcı ilişkileri yalnızca `/mcp` uç noktasında mevcuttur; ilişkili hesabın üyeliği veya görünürlüğünden bağımsız olarak, mevcut kullanıcı içermeyen bir hesap kimlik bilgisi reddedilir.

`query_pulse`, `signal` (`metrics`, `logs`, `traces` veya `errors`), isteğe bağlı `query` ve `range` (`15m`, `1h`, `6h` veya `24h`, varsayılan `1h`) parametrelerini alır. Metrikler PromQL ifadelerini kabul eder. Günlükler, izlemeler ve hatalar, günlük gövdeleri, kapsam adları ve hata sorun başlıklarıyla eşleştirilen büyük/küçük harf duyarlı olmayan değişmez metni kabul eder; varsayılan olan `*` her şeyi seçer. İzleme satırları bireysel kapsamlardır. Hata satırları sorunlardır: hizmete ve parmak izine göre gruplandırılmış olaylar, olay sayıları, etkilenen hesaplar, penceredeki ilk ve son oluşumlar ve en son olaylarının başlığı, sorumlusu, düzeyi ve platformu ile birlikte. Tablolar `search`, `page` (varsayılan `1`), `page_size` (`1`–`100`, varsayılan `20`), `sort_by` ve `sort_order` (`asc` veya `desc`) parametrelerini kabul eder. Sıralama sütunları sinyale bağlıdır ve araç şemasında listelenir. Filtreler arasında `service` ve günlükler ile hatalar için `level` bulunur. Filtre operatörleri karşılık gelen `_op` argümanını (`eq`, `contains` veya `not_contains`) kullanır; varsayılan olarak tam eşitlik uygulanır.

Sıralama sütunları metrikler için `name`/`value`; günlükler için `timestamp`/`service`/`level`/`message`/`trace_id`; izlemeler için `timestamp`/`service`/`name`/`duration_ms`/`trace_id`; ve hatalar için `last_seen`/`first_seen`/`events`/`accounts`/`title`/`service`/`level` şeklindedir. Gösterge paneli kasıtlı olarak bir alt küme sunar; API ve araçlar her sinyal için tam listeyi kabul eder.

Tablo yanıtları `rows`, `series`, `warnings` ve `meta` içerir. Sayfalama meta verileri `page`, `page_size`, `total_count`, `total_pages`, `has_next_page`, `has_previous_page` ve `end_at` içerir. Sorgu penceresini korumak için sonraki sayfalarla döndürülen ISO8601 `end_at` değerini iletin. Sonuç sınırı hataları, yanıtı boş bir tablo olarak değerlendirmek yerine sorgunun veya zaman aralığının daraltılmasını gerektirir.

Günlükler ve izlemeler yerel sıralamadan önce en fazla 100 en yeni eşleşmeyi inceler ve hatalar en son görülen 100 sorunu inceler. Filtreler, sıralama, sayfalama ve toplamlar yalnızca döndürülen eşleşmeleri açıklar, tüm zaman penceresini değil. Diğer eşleşmeleri incelemek için sorgu metnini veya zaman aralığını daraltın; yerel arama veya sıralamayı değiştirmek upstream aramayı genişletmez. Toplama widget'ları, bu sınırlı tablo sonuçlarının toplamaları yerine bağımsız, tam pencere sorguları olarak kalır.

Metrik tabloları ifadelerini `end_at` tarihinde bir kez değerlendirir, mevcut değerleri ve anlık vektör serisi başına bir nokta döndürür. Aralık vektörü ifadeleri sınırlı geçmiş noktalar döndürebilir. Ayrı analiz widget'ları sabit geçmiş grafikler sağlar; bir tablo, yalnızca en son değerini görüntülemek için her eşleşen seri için bir zaman ızgarası oluşturmaz.

Telemetri dizileri güvenilmeyen verilerdir, talimatlar değildir.

`get_pulse_analytics`, hesap tanıtıcısı dışında yalnızca `signal` ve `range` parametrelerini alır. Sabit widget'ları tablo ifadelerinden, filtrelerden, sıralamadan ve sayfalama işleminden bağımsızdır.

`get_pulse_error_issue`, bir hata satırından bir sorunun `fingerprint` ve `service` değerlerini alır; buna ek olarak isteğe bağlı `range`, `end_at`, `page` ve `page_size` parametrelerini kabul eder. Sorun özetini, 60 eşit oluşum grubunu, istisna zinciri, yığın çerçeveleri, iz sürme bilgileri (breadcrumbs), etiketler, bağlamlar, ek veriler, istek yöntemi ve sorgu dizesi hariç URL ile birlikte en son olayı ve tablolarla aynı sayfalama `meta` bilgisine sahip, en yeniden eskiye sıralı bir olay sayfasını döndürür. Hata satırları ayrıca her sorunun 60 gruplu `occurrence_series` serisini taşır. Olaylar depolamadan önce kişisel verilerden arındırılır, bu nedenle filtrelenmiş değerler `[Filtered]` veya `[REDACTED]` olarak görünür. Pencere içinde olayı olmayan bir sorun bulunamadı olarak raporlanır. REST ve Model Context Protocol aynı Pulse bağlamını ve yanıt sözleşmelerini kullanır. REST yanıtları önbelleği devre dışı bırakır.

#### Telemetriyi keşfetme

Keşif araçları, isteğe bağlı ISO8601 `end_at` tarihinde (varsayılan olarak şu an) sona eren `15m`, `1h`, `6h` veya `24h` uzunluğunda bir pencereyi okur (varsayılan `1h` ve `get_pulse_trace` için `24h`). Her yanıt `start_at` ve `end_at` döndürür; pencereyi korumak için aynı `end_at` değerini tekrar iletin. Bu araçların hiçbiri SQL kabul etmez.

- `query_pulse_metrics`, bir PromQL ifadesi olan `query` değerini `end_at` tarihinde (`type: instant`, varsayılan) veya pencere boyunca her `step` saniyede bir (`type: range`) değerlendirir. Adım değeri varsayılan olarak pencerenin 360'a bölümüne eşittir ve bundan küçük olamaz; bu nedenle bir seride en fazla 361 nokta bulunur. Sonuçlarda en fazla 5.000 seri yer alır. Noktalar `[unix_seconds, value]` şeklindedir ve `NaN` ile sonsuz değerler dizge olarak ifade edilir. Anlık sorgular `range` ve `step` parametrelerini reddeder.
- `list_pulse_labels`, bir `signal` parametresi alır. `label` olmadan etiket adlarını listeler; `label` ile belirtilen etiketin değerlerini listeler. Metrikler için `__name__` metrik adlarını listeler ve diğer herhangi bir etiketin değerleri, `up` gibi bir seri seçici olan `match` gerektirir. Günlük ve izleme etiketi değerleri `filters` kabul eder; izleme etiketi adları izleme şemasından gelir ve bunu yapmaz. Günlük ve izleme değerleri, penceredeki giriş sayılarını içerir ve en sık kullanılanlar önce gelir, bu nedenle hizmetlere göre hatalar gibi dökümler olarak da hizmet ederler. `search` yalnızca değişmez metin içeren adları veya değerleri tutar ve `limit` `1`–`1000` aralığını (varsayılan `100`) kabul eder. Günlük etiket adı keşfi, her türden en fazla 1.000 farklı öznitelik kümesini inceler ve yalnızca filtrelerin kabul ettiği anahtarları listeler.
- `search_pulse_logs`, gövdesi `text` içeren ve her filtreye uyan en fazla `limit` girişi (`1`–`100`, varsayılan `50`), `newest` veya `oldest` sırasına göre döndürür. Her giriş `severity_text`, `body`, `trace_id`, `span_id`, `scope_name` ve birleştirilmiş kaynak ile günlük `attributes` bilgilerini içerir. `span_id` ve `scope_name`, yalnızca OTLP günlük göndericilerinin ayarladığı Kubernetes'ten toplanan günlükler için `null` değerindedir.
- `search_pulse_traces`, her filtreye, isteğe bağlı `min_duration_ms` ve `max_duration_ms` değerlerine ve `root_only` koşuluna uyan en fazla `limit` span'i, `newest`, `oldest` veya `slowest` sırasına göre döndürür.
- `get_pulse_trace`, pencere içinde başlayan `trace_id` izlemesinin span'lerini, en eskiden en yeniye doğru, en fazla 1.000 span olacak şekilde döndürür. Pencereden önce başlayan bir izleme kısmen döndürülür; bu nedenle pencereyi genişletin veya kaydırın. Her span, span özelliklerini, olayları, bağlantıları ve izlemenin farklı `resources` kaynaklarına yönelik bir indeksi içerir.

Filtreler, en fazla 10 `{label, op, value}` nesnesinden oluşan listelerdir. `op` değeri `eq` (varsayılan), `neq`, `contains` veya `not_contains` olabilir; son ikisi büyük/küçük harfe duyarlı olmayan değişmez metinlerdir. Günlük etiketleri, Pulse bunları depoladığında `severity_text`, `trace_id`, `span_id` ve `scope_name` ile her girişin kaynak özelliklerinin anahtarlarıdır (örneğin `namespace`, `container` ve `service.name`) ve günlük özellikleri (örneğin `pod`). Bir anahtar her ikisinde de göründüğünde kaynak özelliği geçerli olur. İzleme etiketleri, `list_pulse_labels` tarafından döndürülen span sütunlarıdır; örneğin `service_name`, `span_name`, `span_status_code` (başarısız span'ler için `STATUS_CODE_ERROR`), `span_attributes.http.route` ve `resource_attributes.k8s.pod.name`. Bilinmeyen bir izleme etiketi boş sonuç yerine hata olarak bildirilir.

`truncated`, yanıtın içerdiğinden daha fazla ad, değer, giriş veya span'in eşleştiği anlamına gelir; yanıtı tam olarak değerlendirmek yerine filtreleri veya pencereyi daraltın. Telemetri dizileri güvenilmeyen verilerdir, talimatlar değildir.

<details>
<summary>Claude Code</summary>

Çalıştır:

```bash
claude mcp add --transport http tuist https://tuist.dev/mcp
```

Headless bir Claude Code istemcisi, başarısız yerel sunucu bağlantısını modele göstermediğinde, aracının barındırılan belgeleri aramadan veya projeyi düzenlemeden önce yapılandırılmış uç noktanın kimliği doğrulanmamış [Hipertext Transfer Protokolü](https://developer.mozilla.org/en-US/docs/Web/HTTP) yanıtını incelemesini sağlayın. Yanıt, tarayıcı kimlik doğrulaması mevcut olmasa bile modeli dağıtım yerelindeki `auth.md` belgesine yönlendirir.

</details>


<details>
<summary>Codex</summary>

Çalıştır:

```bash
codex mcp add tuist --url https://tuist.dev/mcp
codex mcp login tuist
```

Yeni bir `codex exec` çalıştırması başlatmadan önce tarayıcıda oturum açma işlemini tamamlayın. Codex, başlatma sırasında Tuist sunucu talimatlarını okur, bu nedenle Gradle optimizasyon istekleri otomatik olarak kimlik doğrulama ve doğrulama iş akışını alır.

</details>


<details>
<summary>Claude Desktop</summary>

**Ayarlar → Bağlayıcılar → Özel bağlayıcı ekle** seçeneğini açın, ardından şunları ayarlayın:

- **Ad:** `tuist`
- **URL:** `https://tuist.dev/mcp`

İstendiğinde tarayıcıda [Açık Yetkilendirme](https://oauth.net/2/) işlemini tamamlayın.

</details>


<details>
<summary>Pi</summary>

Pi, bir Model Context Protocol istemcisi içermez. Kaynak kodunu ve güvenlik etkilerini inceledikten sonra üçüncü taraf [`pi-mcp-adapter`](https://pi.dev/packages/pi-mcp-adapter) uzantısını yükleyebilirsiniz:

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

`auth` değerini `false` olarak ayarlamak, adaptörün tarayıcı kimlik doğrulama işleyicisinin Tuist'in yetkisiz yanıtını gizlemesini engeller. Headless bir ajan daha sonra döndürülen `auth_md` URL'sini okuyabilir ve Tuist'in kayıt, kimlik iddiası değişimi ve talep yoklama akışını takip edebilir. Değiştirilen erişim belirtecini bir bearer belirteci olarak yapılandırın veya ajanın doğrudan kimliği doğrulanmış Model Context Protocol çağrıları yapmasına izin verin.

Tarayıcı kimlik doğrulamasını tercih ediyorsanız, `auth` değerini `"oauth"` olarak ayarlayın. Bu akış için, kimlik doğrulama tamamlanırken Pi'nin [uzak yordam çağrısı modu](https://pi.dev/docs/latest/rpc) ile bir işlemi canlı tutun:

```bash
pi --mode rpc
```

Bekleyen bir tarayıcı kimlik doğrulamasını ayrı `pi --print` çağrılarına bölmeyin çünkü geri arama durumuna sahip olan işlem sonlandırılmıştır.

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

**Cursor Ayarları → Araçlar ve Entegrasyonlar → Model Context Protocol Araçları** seçeneğini açın ve şunları ekleyin:

- **Ad:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>


<details>
<summary>Visual Studio Code</summary>

**Komut Paleti → MCP: Sunucu Ekle** seçeneğini kullanın, ardından aşağıdaki ayarlarla bir [Hipertext Transfer Protokolü](https://developer.mozilla.org/en-US/docs/Web/HTTP) sunucusu yapılandırın:

- **Ad:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>


<details>
<summary>Zed</summary>

**Ajan paneli → Ayarlar → Özel Sunucu Ekle** seçeneğini açın, ardından şunları ayarlayın:

- **Ad:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>

Ajanınız `auth.md` destekliyorsa, tarayıcı açmadan anonim olarak başlayabilir. Sağlayıcı kimliği zaten bağlıysa, güvenilir bir sağlayıcı kimliği de tarayıcı olmadan tamamlanabilir. Hizmetle kimliği doğrulanmış e-posta, anonim talep veya ilk sağlayıcı bağlantısı için ajan size bir Tuist doğrulama bağlantısı ve altı haneli bir kod gösterir. Bağlantıyı açın, oturum açın ve Tuist sayfasında ajanın kodunu girin. Kodu asla ajana geri göndermeyin. Tuist'in yetkilendirme sunucusu meta verileri doğrudan dağıtımın kendi `/auth.md` adresine işaret eder; bu adres kesin istek ve yoklama yapılarını içerir.

## Amp orbs ve Claude Code bulut oturumlarında ajanlar

Bir Tuist hesabına bağlı alan kutularında (sandbox) çalışan kodlama ajanları, tarayıcıya veya kaydedilmiş bir Tuist kimlik bilgisine ihtiyaç duymadan uç noktaya kendi kimlik belirteçleriyle kimlik doğrulaması yapabilir:

- Hesabın **Ayarlar → Entegrasyonlar → Amp** altında bağladığı bir Amp çalışma alanının veya projesinin **Amp orbs**, orb'un kimlik belirtecini gönderir. Amp'te sunucunun `Authorization` başlığını `Bearer ${amp:id-token}` olarak ayarlayın. Amp, sunucu URL'sinin kökeni için belirteci basar, bu nedenle URL bu Tuist örneğinin kendi adresi olmalıdır ve süresi dolmadan önce yeniler. Başka bir köken için basılan belirteçler reddedilir.
- Bağlı bir Claude Code ortamının **Claude Code bulut oturumları**, Tuist'in kendilerine `TUIST_OIDC_TOKEN` olarak ilettiği oturum belirtecini gönderir. Başlığı `Bearer ${TUIST_OIDC_TOKEN}` olarak ayarlayın.

Tuist'in Linux alan kutuları bununla birlikte gelir: Amp'in kullanıcı ayarlarında ve Claude Code'un kullanıcı yapılandırmasında, her ikisi de `${TUIST_URL}/mcp` adresine yönlendirilmiş bir `tuist` sunucusu; ayrıca Tuist CLI ve ajana sonuçlarını projenin geçmişine göre ne zaman kontrol etmesi gerektiğini söyleyen bir beceri. Diğer yerlerde, sunucuyu yukarıdaki başlıkla kendiniz ekleyin.

Bu belirteçler, bağlı hesabın her projesine salt okunur erişim sağlar: `mcp` grubunun okuma kapsamlarını taşırlar ve verileri oluşturan, değiştiren veya silen (testleri sessize alma veya atlama gibi) hiçbir kapsamı taşımazlar. Çalışma alanının veya ortamın bağlantısını kesmek, bir sonraki istekte erişimi durdurur ve erişim asla belirtecin kendisinden daha uzun sürmez. Birden fazla Tuist hesabına bağlı bir Amp çalışma alanı reddedilir çünkü belirteci tek bir hesabı adlandırmaz. Bir bağlantı eksik olduğunda, yetkisiz yanıtın `error_description` alanı bunu belirtir.

Bu salt okunur erişim yalnızca Model Context Protocol uç noktası için geçerlidir. Aynı alan kutusundaki komut satırı aracı ve derleme sistemi entegrasyonları, bağlantının CI erişimi için belirteci yine de değiştirir.

## WebMCP

[WebMCP](https://webmachinelearning.github.io/webmcp) destekleyen tarayıcılarda, Tuist sayfaları araçları `document.modelContext` ile kaydeder, böylece tarayıcıya yerleşik ajanlar herhangi bir ek yapılandırma olmadan bunları çağırabilir. Çağrılar Tuist sunucusunda çalışır.

- **Web sitesi ve belgelendirme sayfaları**, belgeleme ve kaynak araçlarını (`search_tuist`, `search_tuist_code`, `list_tuist_files` ve `read_tuist_file`) kaydeder. Oturum açmanıza gerek yoktur.
- Oturum açtığınızda, **bir hesabın pano sayfaları** o hesap için Tuist'in salt okunur araçlarını kaydeder. Her sayfa yalnızca gösterdiği şeyler için, projenin derleme sistemine göre araçları kaydeder: bir Gradle projesinin derlemeler sayfası Gradle derleme araçlarını, test sayfaları test ve kapsam araçlarını, çalıştırıcılar sayfaları çalıştırıcı araçlarını ve alan kutuları sayfaları alan kutusu araçlarını alır. Her sayfa ayrıca belgeleme araçlarını, `list_projects` ve `get_project` araçlarını da alır. Araçlar oturum açmış kullanıcı olarak çalışır, bu nedenle yalnızca panoda okuyabileceğiniz verilere ve yalnızca baktığınız hesaba erişirler. Başka bir sayfaya veya hesaba geçtiğinizde, araçlar o sayfanın araçlarıyla değiştirilir.

Veri oluşturan, değiştiren veya silen araçlar WebMCP üzerinden kullanılamaz, çünkü bir tarayıcı ajanı araçları sizin eklemenize gerek kalmadan alır ve derlemeler ile testlerin ürettiği içeriği okur. Bu araçları kullanmak için bir MCP istemcisini `/mcp` uç noktasına bağlayın.

Kuruluş tek oturum açmayı zorunlu kılıyorsa, araçlarını kullanmak için panoya sağlayıcısıyla oturum açın.

## Derleme sistemi entegrasyonları iki kimlik bilgisi kullanır

Model Context Protocol araçları için kullanılan kimlik bilgisi, Gradle eklentisini veya Bazel'in uzak hizmetlerini kimlik doğrulamaz. Bir ajan bir Gradle veya Bazel entegrasyonunu düzenlemeden veya doğrulamadan önce şunu çalıştırmalıdır:

```bash
tuist auth whoami --url https://tuist.dev
```

Bu komut kimlik doğrulanmamışsa, ajan durmalı ve kullanıcıdan şunu çalıştırmasını istemelidir:

```bash
tuist auth login --url https://tuist.dev
```

Yerel veya kendi kendine barındırılan bir dağıtım için, her iki komuttaki ve `tuist.toml` dosyasındaki URL'yi değiştirin. Ana bilgisayar adının yazımını her yerde aynı tutun. Örneğin, `localhost` ve `127.0.0.1` ayrı saklanan kimlik bilgilerini kullanır.


## Yetenekler

### Araçlar

Aşağıdaki araçlar Tuist Model Context Protocol sunucusu üzerinden kullanılabilir:

Her araç, açık giriş ve çıkış şemalarıyla birlikte insan tarafından okunabilir bir açıklama yayımlar. Başarılı çağrılar, ilan edilen çıkış şemasına uyan yapılandırılmış içerik döndürür; ayrıca yapılandırılmış içeriği henüz tüketmeyen istemciler için metin olarak serileştirilmiş aynı sonucu döndürür.

Tek bir kaydın tanımlayıcısını alan araçlar, örneğin `build_run_id`, `test_run_id`, `test_case_id`, `bundle_id`, `run_id`, `generation_id` veya `cache_run_id`, o kaydın Tuist pano URL'sini de kabul eder. Tanımlayıcıyı URL'den çıkarmak yerine URL'yi doğrudan tarayıcıdan yapıştırın.

`get_xcode_build`, `get_test_run`, `get_gradle_build` ve `get_project` `side_quests` içerebilir: projenin kullanmadığı ancak kaydın faydalı olacağını gösterdiği Tuist yetenekleri. Her birinin bir `id`, dayandığı kanıtı belirten bir `tip` ve bir `docs` bağlantısı vardır. Ajanlardan önce kullanıcının isteğini tamamlamaları, geçerli yan görevlerden bahsetmeleri ve yalnızca kullanıcı onay verdiğinde birini uygulamaları istenir. Bunlar yalnızca projenin hesabının üyelerine döndürülür; ister kullanıcı oturumu, ister MCP belirteci, ister ajan kimliğiyle bağlansınlar:

| Kimlik | Araç | Ne zaman önerilir |
|----|------|----------------|
| `xcode_compilation_cache` | `get_xcode_build` | Xcode 26 veya üzeriyle işlenen temiz bir derleme, önbelleğe alınabilir derleme görevi çalıştırmadı. |
| `gradle_build_cache` | `get_gradle_build` | Bir derleme, Gradle'ın derleme önbelleği bunlardan hiçbiri için bir anahtar hesaplamadan önbelleğe alınabilir görevleri yürüttü; bu, derleme önbelleğinin kapalı olduğu anlamına gelir. |
| `flaky_test_quarantine` | `get_test_run` | Bir çalıştırmada kararsız testler vardı ve projede etkinleştirilmiş otomasyon bunları sessize almıyor veya atlamıyor. Once projeleri için önerilmez. |
| `test_sharding` | `get_test_run` | Tuist'in parçalayabileceği bir derleme sisteminde, parçalanmamış bir CI çalıştırması 10 dakika veya daha fazla sürdü. İpucu, seçici testin ne zaman yaptığını ve kaç testi zaten atladığını söyler. |
| `tuist_runners` | `get_xcode_build`, `get_test_run` | Bir CI çalıştırması GitHub Actions, Bitrise, GitLab CI veya Buildkite makinelerini kullandı ve hesap Tuist Runners üzerinde hiçbir zaman bir iş çalıştırmadı. Yalnızca tuist.dev'de. |
| `pull_request_comments` | `get_xcode_build`, `get_test_run` | Bir GitHub Actions çalıştırması, GitHub deposuna bağlı olmayan bir projeye aittir. |
| `other_build_systems` | `get_project` | Hesap, desteklenen her derleme sistemiyle Tuist'i kullanmıyor. İpucu, diğerlerini tanımlayan dosyaları listeler, böylece ajan depoyu kontrol edebilir. |

#### Belgeler ve topluluk araması

Bu salt okunur araç, belgeler web sitesini destekleyen aynı arama motoru aracılığıyla Tuist'in belgelerini, [uygulama programlama arayüzü](https://en.wikipedia.org/wiki/API) referansını, GitHub sürümlerini, topluluk forumunu ve GitHub sorunlarını arar. Sürüm sonuçları ürünü, sürümü, yayın tarihini ve ön sürüm durumunu içerir. Varsayılan olarak kararlı sürümler aranır ve ön sürümler `include_prereleases` ile dahil edilebilir. Araç yalnızca `https://tuist.dev/mcp` adresindeki Tuist tarafından barındırılan sunucuda kullanılabilir.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `search_tuist` | Genel Tuist belgelerini, uygulama programlama arayüzü referansını, GitHub sürümlerini, topluluk tartışmalarını ve GitHub sorunlarını arayın. İsteğe bağlı olarak tek bir `source` ile sınırlayın (`docs`, `api_reference`, `releases`, `forum`, `issues`). | `query` |

#### Geri bildirim

Ajanlar, bir Tuist aracının veya isteminin bekledikleri gibi çalışmadığında (örneğin kafa karıştırıcı bir sonuç, hata, eksik veri veya eksik bir yetenek) Tuist ekibine bildirebilir. Ajanlardan bir rapor önermeleri ve bunu yalnızca siz onay verdikten sonra göndermeleri istenir. Her rapor, Tuist desteği ile bir konuşma başlatır; destek ekibi size e-posta ile yanıt verebilir. Bir rapor, ajanın ne beklediğini, ne olduğunu, isteğe bağlı bir öneriyi, Tuist kullanıcı kimliğinizi, kullanıcı adınızı ve e-postanızı ile ait olduğunuz organizasyonları içerir. Ajanlar ayrıca sorunun yaşandığı hesabı ve projeyi belirtebilir, böylece ekip hangi organizasyonla iletişime geçeceğini bilir; yalnızca ait olduğunuz hesaplar kabul edilir. Raporları yalnızca Tuist kullanıcısı olarak oturum açmış ajanlar gönderebilir ve her kullanıcı saatte en fazla 10 rapor açabilir. Araç yalnızca `https://tuist.dev/mcp` adresindeki Tuist tarafından barındırılan sunucuda kullanılabilir.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `report_feedback` | Bir Tuist aracı veya istemiyle ilgili bir sorunu bildirin. İsteğe bağlı olarak `tool_name`, gerçekleştiği `account_handle` ve `project_handle` belirtin ve bir `suggestion` ekleyin. | `category`, `expected`, `actual` |

#### Kaynak destekli yanıtlar

Bu salt okunur araçlar, ajanların mevcut davranışa dayalı yanıtlar için gerçek kaynağı olarak barındırılan sunucuyla birlikte dağıtılan tam Tuist kaynak revizyonunu kullanmasına olanak tanır. Yalnızca `https://tuist.dev/mcp` adresinde kullanılabilirler.

Uyumlu istemciler, başlatma sırasında satır içi OAuth kimlik doğrulama bilgilerinin yanı sıra araçların kaynak revizyonu, bağlantıları ve sonuç sınırları hakkında olgusal açıklamalar alır. Bu açıklamalar yanıt stilini veya bir doğrulama iş akışını dayatmaz. Kullanıcılar, önce `ask_tuist` istemini çağırmadan doğrudan bir soru sorabilir; istem, açık kaynak destekli bir iş akışı için kullanılmaya devam eder.

Her işlem için eşzamanlılık, süre, gezinme, okunan bayt ve yanıt boyutu açısından sabit sınırlar vardır. Arama ve listeleme sonuçları `truncated` ve `truncation_reason` alanlarını içerir. Bir sonuç kesildiğinde, sonucu kapsamlı olarak değerlendirmek yerine yolu, dosya desenini veya arama terimini daraltın.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `search_tuist_code` | Kaynak dosyaları arayarak mevcut davranış, varsayılanlar, yapılandırma, özellik kapıları, hata yönetimi veya belgelenmemiş ayrıntılar hakkındaki soruları yanıtlayın. Sonuçlar çevreleyen satırları, revizyonla sabitlenmiş kaynak bağlantılarını ve tarama istatistiklerini içerir. | `pattern` |
| `list_tuist_files` | İlgili yol bilinmediğinde bir kaynak alt sistemini veya yakındaki testleri keşfedin. Listelemelerin derinliği ve sonuç sayıları sınırlıdır. | Yok |
| `read_tuist_file` | İlgili yolu bulduktan sonra bir uygulama dosyasındaki, çağrı noktasındaki veya testteki belirli bir satır aralığını inceleyin. Kesilmiş yanıtlar, devam etmek için `next_start_line` sağlar. | `path` |

#### Projeler

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_accounts` | Kimliği doğrulanmış kullanıcı için可用的 kişisel ve organizasyon hesap kullanıcı adlarını, her hesabın proje oluşturup oluşturamayacağı dahil olmak üzere listeleyin. | Yok |
| `get_organization` | Bir organizasyonun üye dizinini alın. Bekleyen davetler, panodakiyle aynı yönetici iznini gerektirir; davet kabul belirteçleri asla döndürülmez. | `account_handle` |
| `create_organization` | Kimliği doğrulanmış kullanıcı için bir Tuist organizasyonu oluşturun. | `handle` |
| `create_project` | Kimliği doğrulanmış kullanıcının erişebileceği bir hesap altında bir Tuist projesi oluşturun. | `account_handle`, `project_handle` |
| `add_organization_member` | Mevcut bir Tuist kullanıcısını bir organizasyona ekleyin veya mevcut bir üyenin rolünü güncelleyin. `user` (varsayılan), `admin` veya `viewer` kabul eder; burada görüntüleyici panoları ve çalıştırmaları okuyabilir ancak hiçbir şeyi değiştiremez. | `organization_handle`, `email` |
| `invite_organization_member` | Mevcut bir Tuist kullanıcısına ait olup olmadığına bakılmaksızın bir e-posta adresini bir organizasyona davet edin. Tuist, 14 gün sonra süresi dolan bir kabul bağlantısı e-postası gönderir; sunucu e-posta gönderemediğinde `email_sent` değeri `false` olur ve bağlantı panodan kopyalanmalıdır. `user` (varsayılan), `admin` veya `viewer` kabul eder. Organizasyon yöneticisi izni gerektirir. | `organization_handle`, `email` |
| `cancel_organization_invitation` | Bekleyen bir organizasyon davetini iptal edin, böylece bağlantısı artık kabul edilemez. Organizasyon yöneticisi izni gerektirir. | `organization_handle`, `email` |
| `list_projects` | Kimliği doğrulanmış kullanıcının erişebileceği tüm projeleri listeleyin. | Yok |
| `get_project` | Bir projenin yapılandırmasını ve bağlı depo URL'sini alın. | `account_handle`, `project_handle` |
| `connect_project_repository` | Bir projeyi, hesabın GitHub Uygulaması kurulumunun erişebileceği bir GitHub deposuna bağlayın. Proje, deponun varsayılan dalını benimser. Proje yöneticisi izni gerektirir. | `account_handle`, `project_handle`, `repository_full_handle` |
| `disconnect_project_repository` | Bir projenin GitHub deposuna olan bağlantısını kaldırın. Proje yöneticisi izni gerektirir. | `account_handle`, `project_handle` |

#### Hesap belirteçleri

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_account_tokens` | Belirteç değerlerini açığa çıkarmadan hesap belirteci meta verilerini listeleyin. | `account_handle` |
| `get_account_token` | Değerini açığa çıkarmadan hesap belirteci meta verilerini alın. | `account_handle`, `token_id` |
| `list_project_tokens` | Belirteç değerlerini açığa çıkarmadan proje belirteci meta verilerini listeleyin. | `account_handle`, `project_handle` |

#### Bildirim kuralları

Bu araçlar, kimliği doğrulanmış kullanıcının kendi bildirim kurallarını yönetir: Kuralın projelerinde (veya hiçbirini listelemediğinde bildirim alabileceğiniz herhangi bir projede) yeni bir önizleme gibi bir olay gerçekleştiğinde ve koşulları karşıladığında, Tuist uygulama cihazlarınıza push bildirimi göndermek gibi eylemlerini çalıştırır. Kurallar olmadan bildirim almazsınız. Kullanıcı kimlik doğrulaması gerektirirler, yalnızca kendi kurallarınız üzerinde işlem yaparlar ve yalnızca ait olduğunuz hesaplara ait projeleri kabul ederler. Kurallar tüm hesaplarınızı kapsadığı için pano sayfalarında sunulmazlar.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_notification_events` | Kuralların abone olabileceği olay türlerini, her biri için koşullarına ait bir JSON Şeması ile birlikte listeleyin. | Yok |
| `list_notification_condition_options` | Bir projedeki bir olay için koşul değerlerini önerin; örneğin, son önizlemelerinin dalları ve branch'leri. | `event`, `account_handle`, `project_handle` |
| `list_notification_rules` | Kurallarınızı listeleyin. | Yok |
| `create_notification_rule` | Bir olaydan, isteğe bağlı projelerden ve koşullardan ve en az bir eylemden oluşan bir kural oluşturun. | `event`, `actions` |
| `update_notification_rule` | Bir kuralın etkin durumunu, projelerini, koşullarını veya eylemlerini değiştirin. | `rule_id` |
| `delete_notification_rule` | Bir kuralı silin. | `rule_id` |

#### Sürekli entegrasyon çalıştırıcıları

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_runner_jobs` | Bir hesap için sürekli entegrasyon çalıştırıcı işlerini listeleyin. | `account_handle` |
| `get_runner_job` | Bir sürekli entegrasyon çalıştırıcı işini alın; makinesinin belleğinin dolup dolmadığı, neyi durdurduğu ve neyin değiştirileceği dahil. | `account_handle`, `workflow_job_id` |
| `list_runner_job_steps` | Bir sürekli entegrasyon çalıştırıcı işi için kaydedilen adımları listeleyin. | `account_handle`, `workflow_job_id` |
| `list_runner_job_metrics` | Bir sürekli entegrasyon çalıştırıcı işi için kaydedilen makine metriklerini listeleyin. | `account_handle`, `workflow_job_id` |
| `list_runner_job_logs` | Bir sürekli entegrasyon çalıştırıcı işi için yakalanan en fazla 500 günlük satırını listeleyin. | `account_handle`, `workflow_job_id` |
| `list_runner_workflows` | Bir hesap için sürekli entegrasyon iş akışı özetlerini listeleyin. | `account_handle` |
| `list_runner_profiles` | Bir hesap için sürekli entegrasyon çalıştırıcı profillerini, her birinin `runs-on` etiketiyle birlikte listeleyin. | `account_handle` |
| `get_runner_catalog` | Bir çalıştırıcı profilinin kullanabileceği makine şekillerini ve Xcode sürümlerini listeleyin. | `account_handle` |
| `create_runner_profile` | Bir platform, bir makine şekli ve macOS'ta bir Xcode sürümü ile bir çalıştırıcı profili oluşturun. İsteğe bağlı olarak hangi dalların önbellek birimlerini kaydedeceğini ayarlayın. Hesap yöneticiliği veya `account:runners:write` kapsamı gerektirir. | `account_handle`, `name`, `platform`, `vcpus`, `memory_gb` |
| `update_runner_profile` | Bir çalıştırıcı profilinin makine şeklini, Xcode sürümünü veya özel önbellek birimi değişikliklerini hangi dalların kaydedeceğini değiştirin. Atlanmış alanlar değerlerini korur. Hesap yöneticiliği veya `account:runners:write` kapsamı gerektirir. | `account_handle`, `profile_name` |
| `delete_runner_profile` | Kullanıcı onayından sonra bir çalıştırıcı profilini silin. Varsayılan profiller silinemez. Hesap yöneticiliği veya `account:runners:write` kapsamı gerektirir. | `account_handle`, `profile_name` |

Çalıştırıcı birim araçları, Birimler panosuyla aynı verileri ortaya çıkarır. Okuma araçları çalıştırıcı erişimi gerektirir; temizleme işlemi hesap yöneticiliği veya `account:runners:write` kapsamı ve kullanıcı onayı gerektirir.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_runner_volumes` | Birimleri ada ve depoya göre filtreleyin, sıralayın ve sayfalandırın. | `account_handle` |
| `get_runner_volume` | Depo, platform, kapasite, kullanılan alan ve son kullanım. | `account_handle`, `volume_id` |
| `list_runner_volume_jobs` | Sayfalandırılmış iş ve iş akışı referansları, önbellek durumu, isabet sonucu ve bağlama süresi. | `account_handle`, `volume_id` |
| `list_runner_job_volumes` | Bir iş tarafından bağlanan birimler. | `account_handle`, `workflow_job_id` |
| `get_runner_volume_analytics` | Depolama serileri, iş çalıştırmaları, isabet oranı ve eğilimler. İsteğe bağlı `volume_id`, `start` ve `end` (ISO 8601); varsayılan yedi gün, en fazla 90. | `account_handle` |
| `delete_runner_volume` | Bir birimi ve kaydedilen içeriğini silin. Çalışan işler özel kopyalarını korur ancak bunları kaydedemez; aynı anahtara sahip sonraki işler boş başlar. | `account_handle`, `volume_id` |

Listeler `page` ve `page_size` (en fazla 100) kabul eder. Birim envanteri ayrıca `name` ve `repository` (tam eşleşmeler, AND ile birleştirilir), `sort_by` (`volume`, `repository`, `used_space`, `capacity`, `last_used`) ve `sort_order` (`asc`, `desc`) kabul eder. Bilinmeyen ölçümler ve isabet sonuçları `null` olarak kalır. Önbellek durumu, birim değişikliklerinin kaydedilip kaydedilmediğini açıklar, iş başarısını değil.

#### Sandbox'lar

Sandbox araçları, Sandbox'lar panosuyla aynı verileri ve eylemleri ortaya çıkarır ve [API](https://tuist.dev/api/docs) ile aynı erişime sahiptir: hesap üyeleri sandbox'ları listeleyebilir, alabilir, oluşturabilir, duraklatabilir, devam ettirebilir ve silebilir; ancak bir aracı ortamına, Amp'a veya uzak yürütmeye hizmet veren sandbox'lar ile analiz ve arşivleme araçları hesap yöneticiliği gerektirir. Salt okunur görüntüleyiciler bunları kullanamaz. Hesabın sandbox'ların etkinleştirilmiş olması gerekir. Panonun sandbox sayfaları salt okunur araçları kaydeder.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_sandboxes` | Sandbox'ları durumları, şekilleri ve zaman damgalarıyla sayfalandırın. İsteğe bağlı `search` (sandbox'taki metin, Amp Orb veya Anthropic oturum kimliği), `status`, `vcpus`, `sort_by` (`created`, `last_active`, `identifier`) ve `sort_order`. | `account_handle` |
| `get_sandbox` | Bir sandbox'ın durumu, şekli, düğümü, arşivi ve zaman damgaları. | `account_handle`, `sandbox_id` |
| `get_sandbox_analytics` | vCPU-saatleri, oluşturulan sandbox'lar, oturum, kurulum ve başlatma süreleri ve hesabın limitlerine göre tepe vCPU, bellek ve disk kullanımı, eğilimlerle birlikte. İsteğe bağlı `start` ve `end` (ISO 8601); varsayılan 30 gün, en fazla 90. | `account_handle` |
| `create_sandbox` | Boş bir sandbox'ı başlatın ve çalıştığında döndürün. İsteğe bağlı `platform` (`linux` veya `darwin`), `template`, `vcpus` ile `memory_mb` (Linux: 2x4096, 4x8192 veya 8x16384, varsayılan 2x4096; macOS: 8x8192, 8x16384 veya 8x24576, varsayılan 8x8192) ve `workspace_gb`. | `account_handle` |
| `pause_sandbox` | Çalışan bir sandbox'ın anlık görüntüsünü düğümünün diskine alın. | `account_handle`, `sandbox_id` |
| `resume_sandbox` | Duraklatılmış veya arşivlenmiş bir sandbox'ı devam ettirin. | `account_handle`, `sandbox_id` |
| `archive_sandbox` | Duraklatılmış bir sandbox'ın disklerini nesne depolamaya taşımayı sıraya alın. | `account_handle`, `sandbox_id` |
| `delete_sandbox` | Kullanıcı onayından sonra bir sandbox'ı ve disklerini silin. | `account_handle`, `sandbox_id` |

#### Amp çalışma alanları

Bu araçlar, orb'ların jeton olmadan Tuist'te oturum açmasına olanak tanıyan <.localized_link href="/guides/server/authentication#amp-orbs">Amp çalışma alanı bağlantılarını</.localized_link> yönetir. Panonun Entegrasyonlar sayfasıyla aynı yöneticiye özel izni kullanırlar. Bir orb'daki bir aracı, kendi kimliklerini `$AMP_WORKSPACE_ID` ve `$AMP_PROJECT_ID` üzerinden okuyabilir. Bir bağlantının kabul ettiği her orb, hesaptaki tüm projelere CI erişimi kazanır; bu nedenle aracılardan bağlanmadan önce kullanıcıyla onaylamaları istenir.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_amp_workspace_connections` | Hesabın bağlı Amp çalışma alanlarını ve her birinin sınırlandırıldığı projeyi (varsa) listeleyin. | `account_handle` |
| `connect_amp_workspace` | Bir Amp çalışma alanını bağlayın. İsteğe bağlı `project_id`, oturum açmayı tek bir Amp projesinin orb'larıyla sınırlar. | `account_handle`, `workspace_id` |
| `disconnect_amp_workspace` | Bir çalışma alanının bağlantısını kesin. Orb'larının zaten sahip olduğu oturumlar, süresi dolana kadar geçerli kalır. | `account_handle`, `connection_id` |

#### Claude ortamları

Bu araçlar, Claude Yönetilen Aracıların kendi kendine barındırılan ortamlarını bağlar, böylece oturumları Ayarlar → Entegrasyonlar → Claude'da olduğu gibi Tuist sandbox'larında çalışır. Hesap yöneticiliği ve etkinleştirilmiş sandbox'lar gerektirirler. Bir aracı, Anthropic'in API'si ile ortamı oluşturabilir, ancak yalnızca Claude Konsolu ortam anahtarını oluşturur; bu nedenle aracı kullanıcıdan bunu ister. Tuist, oturumları bir Anthropic API anahtarı veya iş yükü kimlik federasyonu ile başlatır ve kaydetmeden önce o kimlik bilgisiyle ortamı getirir. Anthropic tarafındaki kurulum, kullanıcının kendi Anthropic kimlik bilgilerini kullanır; Tuist bunları asla almaz. Anahtarlar istemci ve model üzerinden geçtiği için bunları yalnızca açıkça sağlayın.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_claude_environments` | Bağlı ortamları ve her birinin kullandığı kimlik bilgisini, ayrıca bir federasyon kuralının güvenmesi gereken yayıncı URL'sini ve konu ön ekini listeleyin. | `account_handle` |
| `connect_claude_environment` | Bir ortamı `api_key` ile veya `organization_id`, `workspace_id`, `service_account_id` ve `federation_rule_id` ile bağlayın. İsteğe bağlı `platform`, `vcpus` ve `memory_mb` sandbox şeklini belirler. | `account_handle`, `environment_id`, `environment_key` |

#### Webhook'lar

Webhook araçları, pano ile aynı yöneticiye özel izni kullanır. Teslimat denemeleri, uç nokta için kaydedilen istek ve yanıt verilerini içerir, ancak uç nokta imzalama gizli anahtarını asla içermez.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_webhook_endpoints` | Bir hesabın webhook uç noktalarını listeleyin. | `account_handle` |
| `get_webhook_endpoint` | Bir webhook uç noktası alın. | `account_handle`, `webhook_endpoint_id` |
| `list_webhook_delivery_attempts` | Bir uç nokta için teslimat denemelerini listeleyin. | `account_handle`, `webhook_endpoint_id` |
| `get_webhook_delivery_attempt` | Bir teslimat denemesi alın. | `account_handle`, `webhook_endpoint_id`, `delivery_attempt_id` |

#### Xcode derlemeleri

Xcode, Gradle, Bazel, Mix ve Cargo için derleme ayrıntısı araçları, mevcut `custom_metadata: {tags, values}` yapısını, raporlandığında altyapı gözlemleri dahil olmak üzere ortaya çıkarır. Değerler dize olarak kalır ve bilinmeyen anahtarlar korunur. Örneğin, `tuist.cpu.available_processors` çalışma zamanında kullanılabilir mantıksal işlemcileri tanımlar; `tuist.gradle.max_workers` bir Gradle işçi sınırıdır ve `tuist.jvm.max_heap_bytes` bir JVM yığın sınırıdır, ana makine belleği değildir. Bunlar güvenilmeyen istemci gözlemleridir, doğrulanmış çalıştırıcı kimlikleri değildir. Eksik gözlemler eksik kalır; içe aktarılan günlükler ve eski istemcilerde altyapı meta verileri olmayabilir. Meta veri güncellemesi, eşgüdümlü bir istemci/protokol güncellemesini beklemektedir.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_xcode_builds` | Bir proje için Xcode derleme çalıştırmalarını listeleyin. | `account_handle`, `project_handle` |
| `get_xcode_build` | Belirli bir Xcode derleme çalıştırması hakkında, ham `.xcactivitylog` dosyasını içeren arşiv için geçici bir indirme URL'si dahil olmak üzere ayrıntılı bilgi alın. | `build_run_id` |
| `list_xcode_build_targets` | Belirli bir Xcode derleme çalıştırması için derleme hedeflerini listeleyin. | `build_run_id` |
| `list_xcode_build_files` | Belirli bir Xcode derleme çalıştırması için derlenmiş dosyaları listeleyin. | `build_run_id` |
| `list_xcode_build_steps` | Günlük metni olmadan, zamanlamalar ve sonuçlarla birlikte kaydedilmiş derleme adımlarını listeleyin. | `build_run_id` |
| `get_xcode_build_step` | Günlüğü ve kırpma bayrağı dahil olmak üzere tek bir kaydedilmiş derleme adımı alın. | `build_run_id`, `step_id` |
| `list_xcode_build_issues` | Belirli bir derleme çalıştırması için derleme sorunlarını (uyarılar ve hatalar) listeleyin. | `build_run_id` |
| `list_xcode_build_cache_tasks` | Belirli bir Xcode derleme çalıştırması için önbelleklenebilir görevleri (önbellek isabetleri/kaçırmaları) listeleyin. | `build_run_id` |
| `list_xcode_build_cas_outputs` | Belirli bir Xcode derleme çalıştırması için [content-addressable storage](https://en.wikipedia.org/wiki/Content-addressable_storage) çıktılarını listeleyin. | `build_run_id` |

`list_xcode_build_steps`, varsayılan olarak 20 adımdan oluşan sayfalar döndürür (`page_size` ile en fazla 100); gezinme için `page` ve `pagination_metadata` kullanılır. Başlıklar, projeler veya hedeflerle eşleşmek için `search` kullanın ya da tam `project`, `target`, `category` (örneğin, `swiftCompilation`) ve `status` (`success` veya `failure`) filtrelerini uygulayın. En yavaş olanı önce getirmek için `duration_ms` ile (varsayılan) veya kronolojik sıra için `start_ms` ile sıralayın. Adım kimlikleri beraberlikleri bozar ve 64 bit hassasiyetlerini korumak için ondalık dizeler olarak döndürülür. Kimlikler bir derlemeyle sınırlıdır ve derlemeler arasında eşleştirilmemelidir.

İsteğe bağlı `start_ms` ve `end_ms`, derleme başlangıcından itibaren milisaniye cinsinden bir zaman aralığıyla kesişen adımları seçer; bitiş hariçtir. Her iki araç da `build_run_id` olarak bir derleme UUID'sini veya pano URL'sini kabul eder. Günlüğünü almak için döndürülen adım `id` değerini `step_id` olarak değiştirilmeden iletin. Günlükler adım başına en fazla 64 KiB tutar; `log_truncated` atlanan çıktıyı gösterir.

Adımlar, Xcode derlemeleri işlendiğinde varsayılan olarak toplanır. Kaydedilen adım verileri 90 gün boyunca saklanır. Liste yanıtı `availability` içerir: Filtreler hiçbirini eşleştirmese bile kaydedilmiş adımlar varsa `available`; derleme hala işleniyorsa ve henüz adım yoksa `processing`; veya adımlar kaydedilmediyse ya da süresi dolduysa `unavailable`.

Aynı işlemler, aynı filtreler ve sayfalama ile HTTP API üzerinden `GET /api/projects/{account_handle}/{project_handle}/xcode/builds/{build_id}/steps` ve `GET /api/projects/{account_handle}/{project_handle}/xcode/builds/{build_id}/steps/{step_id}` adreslerinde mevcuttur. Her ikisi de derlemenin projesine okuma erişimi gerektirir.

#### Gradle derlemeleri

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `get_gradle_integration_guide` | Tam kimlik doğrulama, proje kurulumu, Gradle eklentisi, önbellek politikası ve iki derlemeli doğrulama iş akışını döndürün. Aracılar, mevcut bir Android veya Gradle projesini düzenlemeden önce bunu çağırmalıdır. | Yok |
| `list_gradle_builds` | Bir proje için özel meta veriler dahil Gradle derleme çalıştırmalarını listeleyin. İsteğe bağlı `tag` parametresiyle özel bir etikete göre filtreleyin. | `account_handle`, `project_handle` |
| `get_gradle_build` | Derleme meta verilerini, görev/önbellek sayılarını ve `failures` öğesini alın: başarısız olan her görevin ve yapılandırma adımının hata mesajı. | `build_run_id` |
| `list_gradle_build_tasks` | Görev sonuçlarını, bileşik derleme kimliğini, önbelleklenebilirliği, artımlı durumu ve hata mesajlarını listeleyin. | `build_run_id` |
| `list_gradle_build_steps` | Arama, meta veri ve örtüşen zaman filtreleriyle zamanlanmış görevleri, yapılandırmayı ve dönüşümleri listeleyin. | `build_run_id` |
| `get_gradle_build_step` | Opak kimliğe göre kaydedilmiş adım meta verilerini inceleyin; başarısız bir görevin veya yapılandırma adımının `log` değeri, onun hata mesajıdır. | `build_run_id`, `step_id` |

Gradle ve Bazel adım listeleri varsayılan olarak 20 sonuç döndürür (en fazla 100), `search`, tam `project`, `target`, `category` ve `status` desteği sunar; örtüşen `start_ms` / `end_ms` filtreleri (bitiş hariç) ve `duration_ms` veya `start_ms` sıralaması desteklenir. Döndürülen kimlikleri değiştirilmeden iletin; bunlar kendi derlemeleriyle sınırlıdır. Listeler `time_origin` ve `coverage` sunar. Eski Gradle raporları, derleme başlangıcı yüklenmediği için `first_recorded_timestamp` kullanır. Bazel profilleri, tüm kaydedilmiş aralıkları `trace_profile` kapsamıyla ve zaman kökeni olarak `profile_start` ile ortaya çıkarır. Eski derlemeler, saklanan BEP özetlerine geri döner. Kaynak kayıtlar 90 gün sonra sona erer. Bazel ayrıntıları, yayınlandığında temizlenmiş eylem günlüklerini içerir. Başarısız bir görevin veya yapılandırma adımının Gradle ayrıntıları, Tuist Gradle eklentisinin `log` olarak bildirdiği hata mesajını içerir: Gradle konsolunun yazdırdığı şekilde istisna mesajı ve neden zinciri, yığın izleri veya görev çıktısı olmadan, proje içindeki yollar göreceli hale getirilmiş ve kimlik bilgileri ile diğer yerel yollar sansürlenmiş olarak, adım başına en fazla 16 KiB ve derleme başına 32 başarısız adım. Diğer Gradle adımları, eski eklenti sürümleri tarafından bildirilen derlemeler ve kimlik bilgisiz raporlar null `log` değerine sahiptir. Yapılandırma adımları, başarısız olduklarında `failure` ve aksi halde `unknown` bildirir. `compare_builds` istemi, bu kapsamı tam Bazel izlerini saklanan özetlerden ayırt etmek için kullanır ve daha geniş çağrı çıktısını kontrol etmeden önce eylem sonuçları ve günlükler için adım ayrıntılarına aracıları yönlendirir.

Tek adımlı araçlar `get_gradle_build_step` ve `get_bazel_build_step`, bir adımı kimliğine göre alır ve zaman filtrelerini kabul etmez; adımları zaman aralığına göre filtrelemek için karşılık gelen liste araçlarını kullanın.

Saklanan özetlerden döndürülen Bazel adım kimlikleri, bir adım listelenip alınana kadar tam bir profil gelirse okunabilir kalır. Adım verilerinin süresi dolmuş indekslenmiş bir profil, kullanılamadığını bildirir. Gradle adım listeleri, sıfır süreli önbelleklenmiş ve atlanmış işlemleri içerir.

#### Bazel çağrıları

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `get_bazel_integration_guide` | Kimlik doğrulama, proje kurulumu, Bazel yapılandırması ve doğrulama iş akışını döndürür. | Yok |
| `list_bazel_invocations` | Tamamlanmış [Bazel Build Event Protocol](https://bazel.build/remote/bep) çağrılarını en yeniden eskiye sıralayarak listeler; yapı metrikleri, sınırlı bir yürütme zaman çizelgesi, kritik yol tanılama bilgileri ve bir proje için ilişkilendirilmiş uzak önbellek toplamlarını içerir. `status`, `git_branch`, `git_commit_sha`, `is_ci` ve `command` ile filtreleyin. | `account_handle`, `project_handle` |
| `get_bazel_invocation` | Yapı metrikleri, sınırlı bir yürütme zaman çizelgesi, kritik yol tanılama bilgileri ve ilişkilendirilmiş uzak önbellek toplamlarıyla tek bir tamamlanmış Bazel çağrısını alın. | `account_handle`, `project_handle`, `invocation_id` |
| `list_bazel_build_steps` | Filtreler ve açık kapsam bilgisiyle kaydedilmiş Bazel profil aralıklarını listeler. | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_build_step` | Kaydedilmiş bir Bazel adımını, yayımlanan eylem sonucunu ve sansürlenmiş günlüğünü inceleyin. | `account_handle`, `project_handle`, `invocation_id`, `step_id` |
| `list_bazel_invocation_logs` | Bir Bazel çağrısı için yakalanan sansürlenmiş günlükleri yürütme sırasına göre listeler: Bazel'in ilerleme çıktısının sınırlı kuyruk kısmı ve `test.log` yapıtları. İsteğe bağlı `stream` (`stdout` veya `stderr`), `source` (`progress` veya `test_log`), `target_label` ve `errors` filtreleri sonuçları daraltır. | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_invocation_log` | Bir Bazel çağrısı için yakalanan tek bir sansürlenmiş günlük parçasını alın. | `account_handle`, `project_handle`, `invocation_id`, `invocation_log_id` |
| `list_bazel_cache_events` | İşlem, uç nokta ve gözlem zamanıyla birlikte ham Bazel uzak önbellek gözlemlerini listeler; isteğe bağlı olarak bir çağrı, sonuç veya işlemle daraltılabilir. | `account_handle`, `project_handle` |
| `get_bazel_cache_event` | Tek bir ham Bazel uzak önbellek gözlemini alın. | `account_handle`, `project_handle`, `cache_event_id` |

`list_bazel_invocations` filtreleri tam eşleşmedir ve aynı saniyede biten çağrılar çağrı kimliğine göre sıralanır. Bir dalda en son başarısız olan çağrıyı bulmak için `status: "failure"`, `git_branch` ve `page_size: 1` ile çağırın. REST uç noktası `GET /api/projects/{account_handle}/{project_handle}/bazel/invocations` aynı filtreleri kabul eder.

Test günlükleri, geldikleri test sonucunun `target_label` ve deneme `status` bilgisini taşır; bu nedenle `target_label: "//foo:bar_test"` yalnızca o hedefin test günlüklerini döndürür. `errors: true`, başarısız denemelerin test günlüklerini ve Bazel raporlayıcısının `ERROR:`, `FAIL:` veya `TIMEOUT:` ile başladığı bir satır içeren stderr ilerleme parçalarını döndürür. İlerleme çıktısı hedeflere atanmaz ve atama kaydedilmeden önce yazılan günlüklerin alanları boştur. Başarısız eylemler ve bunların kendi çıktıları hedef bazında `list_bazel_build_steps` üzerinden, test senaryosu bazındaki hatalar ise test çalıştırması araçlarından edinilebilir.

#### Cargo derlemeleri

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_cargo_builds` | Bir proje için Cargo derlemelerini en yeniden eskiye sıralayarak listeler. `git_branch`, `status`, `is_ci` veya `command` ile filtreleyin. Cargo test yürütme sonuçları bu derleme listesi üzerinden değil, test araçları aracılığıyla kullanılabilir. | `account_handle`, `project_handle` |
| `get_cargo_build` | Derleme meta verilerini, toplam önbellek sayaçlarını ve tanılama bilgileriyle birlikte en fazla 500 kaydedilmiş derleyici işini alın. `compilations_truncated` dışlanan işleri gösterir; tanılama bilgileri yalnızca döndürülen işleri kapsar. | `account_handle`, `project_handle`, `build_id` |

Doğrulanmış görev kararlarını ve CAS işlemlerini almak için `get_cargo_build` üzerinde `include_cache_inspection: true` ayarlayın; boyut 4 MB ile sınırlıdır. Varsayılan olarak ve kayıtlar eksik veya geçersiz olduğunda `cache_inspection` null değerindedir. Kısmi yakalamanın `truncated` bayrağına uyun; aktarımlar her görev isabetinin yerel/uzak kökenini belirlemez. HTTP ayrıntı uç noktası aynı sorgu parametresini kabul eder.

#### Mix derlemeleri

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_mix_builds` | Bir proje için Mix (Elixir) derleme işlerini, özel meta veriler dahil, en yeniden eskiye sıralayarak listeler. `git_branch`, `status`, `is_ci` veya `mix_env` ile filtreleyin. | `account_handle`, `project_handle` |
| `get_mix_build` | Derleme meta verilerini, tanılama sayılarını ve bağımlılık önbelleği özetini alın. | `account_handle`, `project_handle`, `build_id` |

#### Derleme izleri

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `get_build_trace` | [Perfetto](https://ui.perfetto.dev) içinde açabileceğiniz bir iz dosyası olarak bir Xcode, Gradle, Bazel veya Mix derlemesinin zaman çizelgesi için bir indirme bağlantısı alın. | `account_handle`, `project_handle`, `build_id` |

`build_id`, derleme çalıştırma kimliğidir (Bazel için çağrı kimliği) veya derlemenin kontrol paneli URL'sidir. Döndürülen `trace_url`, bir [Chrome Trace Event](https://docs.google.com/document/d/1CvAClvFfyA5R-PhYUmn5OOQtYMH4h6I0nSsKchNAySU) JSON dosyası sunar. Bağlantıya sahip olan herkes, başka kimlik bilgileri olmadan, çağrıdan bir saat sonra gelen `expires_at` tarihine kadar o derlemenin izini indirebilir. Ajanlar bunu `curl` ile indirebilir, Perfetto'da açmanız için size iletebilir veya Perfetto'nun `trace_processor` özelliğiyle sorgulayabilir. İz, paralellik açısından şeritlere paketlenmiş kaydedilmiş adımları, tüm derlemeyi kapsayan bir yolu ve derleme makine metriklerini kaydettiğinde CPU ve bellek sayaçlarını içerir. Günlükler hariç, yukarıdaki adım araçlarıyla aynı veriyi tutar. Kontrol paneli, her derlemenin Zaman Çizelgesi sekmesinden aynı dosyayı sunar.

#### Once çalıştırmaları

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_once_runs` | Bir proje için Once çalıştırmalarını en yeniden eskiye sıralayarak listeler. `kind` (`build`, `test` veya `generic`), `status`, `is_ci` veya `git_branch` ile filtreleyin. Tamamlanmamış çalıştırmaların durumu `in_progress` olur. | `account_handle`, `project_handle` |
| `get_once_run` | Eylem toplamları, önbellek özeti ve test çalıştırmaları için test toplamlarıyla birlikte bir çalıştırmayı alın. | `account_handle`, `project_handle`, `run_id` |

Cargo derlemesi, Mix derlemesi ve Once çalıştırma kimlikleri bir proje içinde benzersizdir. Aynı okuma işlemleri HTTP API üzerinden `GET /api/projects/{account_handle}/{project_handle}/cargo/builds`, `.../mix/builds` ve `.../once/runs` adreslerinde mevcuttur; her biri tek bir kimlik için bir ayrıntı uç noktasına sahiptir.

#### Görevler, eylemler, modüller ve dosyalar

Bu proje kapsamındaki araçlar, çalıştırmalar boyunca kalıcı derleme kimliklerini inceler. `list_build_entities` ile başlayın, ardından döndürülen kararlı `id` değerini aynı `kind` ile birlikte `account_handle` ve `project_handle` parametreleriyle `get_build_entity` veya `list_build_entity_history` uç noktalarına iletin. Derleme veya çağrı kimliği gerekmez.

| Araç | Açıklama | Gerekli parametreler |
| --- | --- | --- |
| `list_build_entities` | Bir projenin derlemeleri arasında görülen tek bir türdeki görevleri, modülleri, eylemleri veya dosyaları listeler. | `account_handle`, `project_handle`, `kind` |
| `get_build_entity` | Seçilen dönem için yerel kimliği ve analitik verileriyle birlikte tek bir derleme varlığını alın. | `account_handle`, `project_handle`, `kind`, `id` |
| `list_build_entity_history` | Tek bir derleme varlığının kaydedilmiş yürütmelerini, derlemelerini veya önbellek olaylarını en yeniden eskiye sıralayarak listeler. | `account_handle`, `project_handle`, `kind`, `id` |

| `kind` | Araç zinciri | Geçmiş listeleri |
| --- | --- | --- |
| `bazel_actions` | Bazel eylemleri | BEP tarafından bildirilen eylem yürütmeleri |
| `gradle_tasks` | Gradle görevleri | Görev yürütmeleri |
| `xcode_modules` | Xcode modülleri | Derlemeler ve modül önbelleği olayları |
| `once_actions` | Once eylemleri | Yürütmeler |
| `mix_files` | Mix derlenmiş dosyalar | Derlemeler |
| `mix_modules` | Mix derlenmiş modüller | Derlemeler |
| `cargo_crates` | Cargo paketleri | Kaydedilmiş rustc çağrıları |

Bu araçlar kademeli olarak sunulmaktadır ve yalnızca etkinleştirildiği projeler için veri döndürür; diğer projeler için boş sonuç yerine hata döndürür. Bir tür, yalnızca ilgili derleme araç zincirini kullanan projeler için kullanılabilir. Araçlar sınırlı `start_at`/`end_at` filtrelerini, `environment` (`any`, `ci` veya `local`) ve tam eşleşen `branch` kabul eder. `list_build_entities`, `q` parametresini kabul eder; `list_build_entity_history`, şeffaf olmayan `after`/`before` imleçlerini destekler. Bilinmeyen zamanlama veya önbellek gözlemleri sıfır veya isabetsizlik olarak değil, mevcut değil olarak kalır. Geçmiş, mevcut çalıştırma araçlarını kullanarak ayrıntılı inceleme yapmak üzere kaydedilen üst öğeyi ve yerel yürütmeyi referans alır.

`get_build_entity` metrikleri, zamanlaması kaydedilmiş gözlem sayısını ifade eden `duration_samples` içerir: Gerçek sıfır süreler sayılır, eksik zamanlama sayılmaz. Bu sayı, gözlem sayısından daha düşük olabilir; mevcut olmayan süre istatistikleri null olarak kalır.

Xcode modül süreleri, derleme günlüklerindeki ölçülmüş hedef derlemelerden gelir. Modül önbelleği çözümlemeleri ve derleme işi içermeyen hedefler süre örneklerine katkıda bulunmaz. Derleme gözlemleri Xcode derlemesini referans alır; önbellek olayları oluşturma veya önbellek komutunu referans alır.

Bazel eylemleri, hedef etiketi, anımsatıcı ve yapılandırılmış birincil çıktı ile tanımlanır; böylece girdiye bağlı önbellek özetlerine güvenmeden ayrı eylemler ve yapılandırmalar distinct tutulur. Geçmiş, BEP tarafından bildirilen yürütmeleri kaydeder, önbellek aramalarını veya iz profili aşamalarını değil. Tam yürütme kapsamı `--build_event_publish_all_actions` gerektirir; yapıt teslimi en iyi çaba esasına göre yapılır, bu nedenle eksik gözlemler iş yapılmadığına dair kanıt değildir. Kararlı kimliği veya yürütme başlangıcı olmayan eski Kura yükleri kabul edilir ancak indekslenmez. Eksik bitiş zamanı ölçümleri mevcut değil olarak kalır ve gerçek sıfır süreler sayılır.

Mix modül süreleri, bağımsız olarak ölçülen modül işini değil, kapsayan dosyanın derlenmesini ölçer. Once eylemleri, istemci hedef eşlemelerini bildirdiğinde bildirilen hedef/yetenek/dizin yuvalarını kullanır; yalnızca tanılama etiketleri kararlı kimlikler değildir. Mevcut istemciler ve çalıştırma düzeyi araçları değişmeden desteklenmeye devam eder.

Cargo paketleri, tam olarak kaydedilen paket kökü, adı ve türüne göre gruplanır. Checkout yolu değişiklikleri geçmişleri bölebilir ve derleme profilleri, özellikler ile hedef üçlüleri ayırt edilmez. Geçmiş, dosya başına işi veya önbellek isabetlerini değil, rustc çağrılarını ölçer; eksik işler kaldırılmaları veya eksiksiz bir çalışma alanı envanterini kanıtlamaz.

Analitik okumalarının bellek ve yürütme süresi sınırları vardır. Bir sorgu bu sınırları aşarsa, araç boş bir sonuç uydurmak yerine hata döndürür.

Yeni gözlemler dağıtımdan sonra indekslenir; bu özellik mevcut çalıştırma telemetrisini geriye dönük doldurmaz. Kimlik meta verileri, <.localized_link href="/guides/server/data-retention">veri saklama politikası</.localized_link> kapsamında bireysel gözlemlerden daha uzun süre korunur.

#### Testler

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_test_runs` | Bir proje için test çalıştırmalarını listeler. `query` alanları `git_branch`, `scheme` ve `status` şeklindedir: `field:"value"` tam eşleşme sağlar, `field~"value"` büyük/küçük harfe duyarlı olmayan alt dize eşleşmesi sağlar ve başındaki `-` her iki operatörü de olumsuzlar. Örneğin, `-git_branch~"gh-readonly-queue"` birleştirme kuyruğu dallarını hariç tutar. Boşlukla ayrılmış sorgu filtreleri ve açık argümanlar AND mantığıyla birleştirilir. | `account_handle`, `project_handle` |
| `get_test_run` | Sonuç paketi (`.xcresult`) ve oturum arşivi için geçici indirme URL'leri dahil olmak üzere bir test çalıştırması için ayrıntılı metrikleri alın. | `test_run_id` |
| `list_test_module_runs` | Belirli bir test çalıştırması için test modülü çalıştırmalarını listeler. | `test_run_id` |
| `list_test_suite_runs` | Belirli bir test çalıştırması için test paketi çalıştırmalarını, isteğe bağlı olarak modüle göre filtrelenmiş şekilde listeler. | `test_run_id` |
| `list_test_cases` | Bir proje için test senaryolarını listeler (`flaky` gibi filtreleri destekler). | `account_handle`, `project_handle` |
| `get_test_case` | Güvenilirlik oranı, kararsızlık oranı ve çalıştırma sayıları dahil olmak üzere bir test senaryosu için ayrıntılı metrikleri alın. | `test_case_id` veya `identifier` + `account_handle` + `project_handle` |
| `list_test_case_runs` | Test senaryosu çalıştırmalarını, isteğe bağlı olarak test senaryosuna veya test çalıştırmasına göre filtrelenmiş şekilde listeler. | `account_handle`, `project_handle` |
| `get_test_case_run` | Belirli bir test senaryosu çalıştırması için hata ayrıntılarını ve tekrarları alın. | `test_case_run_id` |
| `list_test_case_run_attachments` | Bir test senaryosu çalıştırması için ekleri listeler. Her ek, geçici bir indirme URL'si içerir. | `test_case_run_id` |
| `list_test_case_events` | Susturma veya atlama gibi bir test senaryosundaki durum değişikliklerini listeler. | `test_case_id` |
| `update_test_case` | Bir test senaryosunun durumunu veya kararsız sınıflandırmasını günceller. Bir değişiklik, harici hizmetler dahil olmak üzere yapılandırılmış webhook uç noktalarına bir olay gönderebilir. | `test_case_id` veya `identifier` + `account_handle` + `project_handle` |
| `list_xcode_test_targets` | Bir test çalıştırması için seçici test hedef sonuçlarını listeler. | `test_run_id` |
| `get_coverage` | Bir projenin kod kapsamını hedefleriyle birlikte, bir commit'te veya bir dalın en son tamamlanmış commit'inde alın. `git_commit_sha` veya `branch` olmadan varsayılan dalı okur. | `account_handle`, `project_handle` |
| `list_coverage_files` | Bir commit'in kod kapsamının ölçtüğü dosyaları, satır kapsamlarıyla birlikte, bir commit'te veya bir dalın en son tamamlanmış commit'inde listeler. `search`, sıralama ve sayfalama desteği sunar. | `account_handle`, `project_handle` |
| `get_coverage_file` | Bir dosyanın kod kapsamını ve işlevlerini, bir commit'te veya bir dalın en son tamamlanmış commit'inde alın. Her satırın yürütme sayısını almak için `include_lines` ayarlayın. | `account_handle`, `project_handle`, `path` |

Kod kapsamı araçları, kod kapsamı etkinleştirilmiş hesaplara sunulur.

#### Paketler

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_bundles` | Bir proje için paketleri (uygulama ikili dosyalarını) listeler. İsteğe bağlı olarak `git_branch` ve `tags` ile filtreleyin (tüm etiketlerin tam eşleşmesi gerekir). | `account_handle`, `project_handle` |
| `get_bundle` | Özel etiketler dahil olmak üzere belirli bir paket hakkında ayrıntılı bilgi alın. | `bundle_id` |
| `get_bundle_artifact_tree` | Bir paketin tam yapıt ağacını, yola göre sıralanmış düz bir liste olarak alın. | `bundle_id` |

`list_bundles`, derleme varyantlarını veya ortamları ayırt etmek için `tags: ["paid", "production"]` kabul eder. Etiketler, büyük/küçük harfe duyarlı, harf, rakam, tire veya alt çizgi içeren etiketlerdir; en fazla 10 etiket ve etiket başına 50 karakter olabilir. Liste ve ayrıntı sonuçları `custom_metadata.tags` içerir. Sayfalama sayıları ve dal filtreleri etiketli sonuçlara uygulanır; `tags` atlandığında filtrelensiz davranış korunur. Geçersiz etiket filtreleri sorguyu genişletmek yerine hata döndürür.

#### Oluşturmalar

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_generations` | Bir proje için oluşturma çalıştırmalarını listeler. | `account_handle`, `project_handle` |
| `get_generation` | Belirli bir oluşturma çalıştırması hakkında ayrıntılı bilgi alın. | `generation_id` |

#### Önbellek çalıştırmaları

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_cache_runs` | Bir proje için önbellek çalıştırmalarını listeler. | `account_handle`, `project_handle` |
| `get_cache_run` | Belirli bir önbellek çalıştırması hakkında ayrıntılı bilgi alın. | `cache_run_id` |
| `list_xcode_module_cache_targets` | Bir oluşturma veya önbellek çalıştırması için modül önbelleği hedeflerini listeler; hedef başına önbellek isabeti/ıska durumu ve ek karma girdileri dahil olmak üzere tanılama bileşeni karmalarını gösterir. | `run_id` |

#### Önizlemeler

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_previews` | Bir proje için paylaşılabilir uygulama önizlemelerini listeler. | `account_handle`, `project_handle` |
| `get_preview` | Bir önizlemeyi ve derlemeleri için geçici indirme URL'lerini alın. | `preview_id` |
| `get_latest_preview` | Çalışan bir uygulama ikili dosyası için en son önizlemeyi bulun. | `account_handle`, `project_handle`, `binary_id`, `build_version` |

#### Otomasyonlar

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_automation_alerts` | Bir proje için otomasyon uyarılarını listeler. | `account_handle`, `project_handle` |
| `get_automation_alert` | Bir otomasyon uyarısını alın. | `alert_id` |
| `list_automation_alert_revisions` | Bir otomasyon uyarısının revizyon geçmişini listeler. Eylem kimlik bilgileri gizlenir. | `alert_id` |
| `list_project_notification_alerts` | Proje bildirim uyarısı kurallarını listeler. Kontrol paneli ayarları sayfasıyla aynı yönetici iznini gerektirir. Webhook adresleri gizlenir. | `account_handle`, `project_handle` |

### Olaylar

Durumsuz `2026-07-28` Model Bağlam Protokolü yaşam döngüsünü kullanan istemciler, olayları ve yük şemalarını keşfetmek için `events/list` çağrısı yapabilir:

| Olay | Ne zaman gönderilir | Abonelik filtresi |
|-------|-----------------|---------------------|
| `test_case.marked_flaky` | Bir test senaryosu kararsız olmayan durumdan kararsız duruma geçer. | `account_handle`, `project_handle` |
| `build.failed` | Yerel veya sürekli entegrasyon Xcode, Gradle ya da Bazel derlemesi bir başarısızlıkla sonlanır. | `account_handle`, `project_handle` |
| `test_run.failed` | Yerel veya sürekli entegrasyon test çalıştırması bir başarısızlıkla sonlanır; birleştirilmiş parçalı çalıştırma veya terk edilmiş çalıştırma dahildir. | `account_handle`, `project_handle` |
| `ci_job.failed` | Bir Tuist runner işi bir başarısızlıkla tamamlanır. | `account_handle` |

Abone olmak için istemci, olay adıyla, yukarıda `arguments` içinde listelenen tanıtıcılarla ve bir `https://` geri çağırma URL'si ile bir `whsec_` imzalama sırrı içeren bir `webhook` teslimatıyla `events/subscribe` çağrısı yapar. Proje olayları hesap üyeliği ve ilgili test veya derleme verilerine okuma erişimi gerektirir; runner işi olayları hesap üyeliği ve runner okuma erişimi gerektirir. Talep edilen [`auth.md`](https://workos.com/auth-md) erişim belirteçleri, talep edilen hesap belirteçleri ve tarayıcı yetkilendirme izinleri abonelik oluşturabilir; ilişkili kimlik bilgisi artık etkin olmadığında teslimat durur. Her kullanıcı en fazla 25 etkin abonelik tutabilir. Tuist, aboneliği kaydetmeden önce geri çağırmaya bir doğrulama sorgusu gönderir. Geri çağırma, aynı `challenge` değerini içeren bir nesne döndürmelidir. Abonelik varsayılan olarak yedi gün sürer, yeniden abone olunarak yenilenebilir ve kullanıcının erişimi veya kimlik bilgisi kaldırıldığında teslimat durur. İsteğe bağlı `ttlMs`, bir saat ile 30 gün arasında sınırlıdır. Tuist, zaman aşımına uğrayan bir geri çağırmayı yeniden dener ve beş dakikayı kapsayan en az üç ardışık zaman aşımından sonra aboneliği iptal eder; geri çağırmayı restore ettikten sonra yeniden abone olun.

Bir olay gerçekleştiğinde Tuist, kaynak tanımlayıcısını ve kontrol paneli URL'sini geri çağırmaya gönderir. Derleme ve test çalıştırması hataları ayrıca `is_ci` ve `git_branch` içerir, böylece istemciler yerel hataları yok sayabilir veya dala göre filtreleyebilir. Derleme olayları `build_system` içerir; runner işi olayları hem `workflow_job_id` hem de `workflow_run_id` içerir. İstek, istemcinin kaynağını doğrulayabilmesi için bir abonelik tanımlayıcısı ve [Standard Webhooks](https://www.standardwebhooks.com/) imza başlıkları içerir. Tuist başarısız teslimatları yeniden dener, bu nedenle istemciler kopyaları atmak için kararlı `eventId` kullanmalıdır. Yük, test adlarını, günlükleri ve hata mesajlarını dışarıda bırakır; istemci bu ayrıntıları yukarıdaki araçlar aracılığıyla alabilir ve bir ekibi bilgilendirmeye veya hata ayıklamaya başlamaya karar verebilir. İstemciler teslimatı `events/unsubscribe` ile durdurabilir.

### İstemler

| İstem | Açıklama |
|--------|-------------|
| `fix_flaky_test` | Başarısızlık kalıplarını analiz ederek, kök nedeni belirleyerek ve hedefe yönelik bir düzeltme uygulayarak kararsız bir testi düzeltmeniz konusunda size rehberlik eder. |
| `compare_builds` | Performans gerilemelerini, önbellek değişikliklerini ve derleme sorunlarını belirlemek için derlemeleri karşılaştırmanız konusunda size rehberlik eder. Xcode, Gradle, Bazel ve Cargo projeleri için yerel araçları kullanır. Cargo karşılaştırmaları kısmi derleyici kapsamını korur ve tahmini derleyici işini geçen süre tasarrufundan ayırır. |
| `compare_test_runs` | Gerilemeleri, yeni hataları ve kararsız testleri belirlemek için iki test çalıştırmasını karşılaştırmanız konusunda size rehberlik eder. |
| `compare_bundles` | Yapıt ağacındaki boyut değişikliklerini belirlemek için iki paketi karşılaştırmanız konusunda size rehberlik eder. |
| `compare_test_case` | İki dal veya zaman dilimi arasında bir test senaryosunun davranışını karşılaştırmanız konusunda size rehberlik eder. |
| `compare_generations` | Performans gerilemelerini ve modül önbelleği değişikliklerini belirlemek için iki oluşturma çalıştırmasını karşılaştırmanız konusunda size rehberlik eder. |
| `compare_cache_runs` | Önbellek etkinliği değişikliklerini ve hedef düzeyindeki gerilemeleri belirlemek için iki önbellek çalıştırmasını karşılaştırmanız konusunda size rehberlik eder. |
| `integrate_gradle_project` | Tuist'i mevcut bir Gradle projesine entegre etmeniz konusunda size rehberlik eder. Ayrı araç ve Gradle kimlik doğrulaması, hesap keşfi, proje oluşturma, uzak önbellek politikası, derleme içgörüsü ve geri okuma doğrulamasını içerir. |
| `integrate_bazel_project` | Bir Bazel projesi oluşturmanız veya seçmeniz, komut satırını kimlik doğrulamanız, uzak önbelleği ve derleme içgörülerini yapılandırmanız ve entegrasyonu Tuist derleme verileri aracılığıyla doğrulamanız konusunda size rehberlik eder. |
| `integrate_xcode_project` | Tuist'i mevcut bir Xcode projesine entegre etmeniz konusunda size rehberlik eder. Xcode önbelleğini, derleme içgörüsünü, test içgörüsünü ve test parçalamayı destekler. |
| `ask_tuist` | Kamuya açık materyalleri bağlam olarak kullanarak ve mevcut davranışın doğruluk kaynağı olarak odaklanmış uygulama ve test kanıtlarını kullanarak bir Tuist sorusunu yanıtlar. Bir `question` gerektirir ve revizyon sabitli kanıtlara atıfta bulunur. |

Proje verisi istemleri, incelemeyi belirli bir projeye daraltmak için `account_handle` ve `project_handle` kabul eder. Karşılaştırma istemleri ayrıca karşılaştırılacak iki öğeyi (ID, kontrol paneli URL'si veya dal adı ile) belirtmek için `base` ve `head` bağımsız değişkenlerini kabul eder. `ask_tuist`, proje parametreleri yerine bir `question` kabul eder. `integrate_gradle_project` ayrıca uygulanacak Gradle entegrasyonlarının virgülle ayrılmış bir listesini olan `features` kabul eder: `remote_cache`, `build_insights`, `test_insights`, `flaky_tests` ve `test_sharding`. `integrate_bazel_project`, kendi kendine barındırılan veya yerel kurulumlar için isteğe bağlı bir `server_url` kabul eder. `integrate_xcode_project`, `xcode_cache`, `build_insights`, `test_insights` ve `test_sharding` ile `features` kabul eder.

#### Gradle entegrasyonu istemi özellikleri

`integrate_gradle_project` istemi ve `get_gradle_integration_guide` aracı, eksiksiz kurulum iş akışını belgeler. Araç ayrıca sunucunun başlatma talimatlarında referans verilir; bu da istemleri numaralandırmayan ajanlar tarafından keşfedilebilir olmasını sağlar.

| Özellik | Ajanın yapılandırdığı şey |
|---------|---------------------------|
| `remote_cache` | Gradle'ın derleme önbelleğini etkinleştirir, Tuist uzak önbellek yükleme politikasını yapılandırır ve yalnızca yerel salt okunur kullanıma sahip sürekli entegrasyon çalıştırıcılarından yüklemeleri önerir. |
| `build_insights` | Tuist Gradle eklentisini uygular ve gerektiğinde derleme analitiği yükleme davranışını yapılandırır. |
| `test_insights` | Gradle `Test` görev sonuçlarının otomatik olarak yüklenmesi için Tuist Gradle eklentisini uygular. |
| `flaky_tests` | Kararsız test tespiti kurulumunu, isteğe bağlı Gradle Test Retry eklentisi kullanımını ve test karantina yapılandırmasını rehberlik eder. |
| `test_sharding` | `tuistPrepareTestShards`, parça matrisi oluşturma ve `TUIST_SHARD_INDEX` tabanlı test yürütme için sürekli entegrasyon iş akışını ekler. |

`features` atlandığında, istem ajandan kullanıcının hangi entegrasyonları istediğini netleştirmesini veya Gradle projesini düzenlemeden önce istekten en küçük faydalı seti çıkarmasını ister.

#### Xcode entegrasyonu istemi özellikleri

`integrate_xcode_project` istemi, Tuist'in desteklediği her Xcode entegrasyonunu belgeler:

| Özellik | Ajanın yapılandırdığı şey |
|---------|---------------------------|
| `xcode_cache` | `tuist setup cache`, oluşturulan proje önbellek ayarlarını, manuel Xcode önbellek derleme ayarlarını ve yalnızca sürekli entegrasyon çalıştırıcılarıyla sınırlı bir yükleme politikasını yapılandırır. |
| `build_insights` | `tuist inspect build`, `tuist xcodebuild`, `-resultBundlePath` ve `tuist setup insights` aracılığıyla isteğe bağlı makine metriklerini yapılandırır. |
| `test_insights` | `tuist inspect test`, şema test sonrası eylemlerini ve sürekli entegrasyon test çalıştırmaları için sonuç paketi oluşturmayı yapılandırır. |
| `test_sharding` | `TUIST_SHARD_INDEX` ile Xcode veya oluşturulan proje parça planlama ve parça yürütme iş akışını ekler. |

`features` atlandığında, istem ajandan kullanıcının hangi entegrasyonları istediğini netleştirmesini veya Xcode projesini düzenlemeden önce istekten en küçük faydalı seti çıkarmasını ister.
