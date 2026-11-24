---
{
  "title": "Model Context Protocol (MCP)",
  "titleTemplate": ":title · Ajan tabanlı kodlama · Özellikler · Kılavuzlar · Tuist",
  "description": "AI ajanlarına Tuist'in MCP uç noktası üzerinden test içgörülerine ve daha fazlasına erişim sağlayın."
}
---
# Model Context Protocol

[Model Context Protocol (MCP)](https://modelcontextprotocol.io/docs/getting-started/intro), yapay zekâ ajanlarının harici hizmetler ve veri kaynaklarıyla etkileşime girmesini sağlayan açık bir standarttır. [Claude](https://claude.ai/), [Claude Code](https://docs.anthropic.com/en/docs/claude-code), [Codex](https://developers.openai.com/codex/) gibi uygulamaların ve [Zed](https://zed.dev), [Cursor](https://www.cursor.com) veya [Visual Studio Code](https://code.visualstudio.com) gibi editörlerin Tuist ile birlikte çalışabilmesini sağlar.

Tuist, sunucu tarafında bir Model Context Protocol uç noktasını `https://tuist.dev/mcp` adresinde barındırır. İstemcinizi bu uç noktaya bağlayarak ajanların test içgörülerini, kararsız test analizlerini ve daha fazlasını içeren Tuist proje verilerinize erişmesini sağlayabilirsiniz. Çoğu araç, kimliği doğrulanmış kullanıcının panoda zaten görebildiği Tuist verilerini okur. Her araç, salt okunur olup olmadığını, geri alınması zor bir değişikliğe neden olup olmadığını (`destructiveHint`) ve Tuist dışına erişip erişmediğini (`openWorldHint`) belirten ek açıklamalar sunar. Durumu değiştiren araçlar, her biri hesabın veya projenin kullanıcı izinleriyle sınırlı olmak üzere şunlardır:

- **Kuruluşlar ve üyeler**: `create_organization`, `add_organization_member` (mevcut bir kullanıcıyı ekler veya bir üyenin rolünü değiştirir), `invite_organization_member` (herhangi bir adrese davet e-postası gönderir) ve `cancel_organization_invitation`.
- **Projeler**: `create_project`, `start_project_logo_upload` ve `complete_project_logo_upload` (logoyu değiştirir), `connect_project_repository` ve `disconnect_project_repository` (GitHub depo bağlantıları).
- **Testler**: `update_test_case` (bir test senaryosunu sessize alır, atlar, yeniden etkinleştirir veya kararsız olarak işaretler; değişiklik hesabın webhook uç noktalarına ulaşabilir).
- **Bildirim kuralları**: `create_notification_rule`, `update_notification_rule` ve `delete_notification_rule`.
- **Sürekli entegrasyon çalıştırıcıları**: `create_runner_profile`, `update_runner_profile` (önbellek birimlerini kaydeden işleri daraltmak bekleyen kayıtları iptal eder), `delete_runner_profile` ve `delete_runner_volume` (birimin kaydedilmiş içeriğini siler).
- **Sandıklar**: `create_sandbox`, `pause_sandbox`, `resume_sandbox`, `extend_sandbox`, `archive_sandbox` ve `delete_sandbox` (disklerini siler).
- **Geri bildirim**: `report_feedback` (bir araç veya istem hakkında Tuist ekibine rapor gönderir; yalnızca tuist.dev üzerinde).
- **Kuruluş Yapay Zekâsı**: `save_organization_ai_model`, `remove_organization_ai_model`, `set_organization_ai_default_model`, `save_organization_ai_task_route`, `remove_organization_ai_task_route` ve `remove_organization_ai_provider` (sağlayıcının anahtarını ve modellerini siler ve Anthropic'te bağlı bir Claude kuruluşunun bağlantısını kaldırır).
- **Ajan entegrasyonları**: `connect_amp_workspace` (çalışma alanının orb'larına hesaba CI erişimi verir), `disconnect_amp_workspace` ve `connect_claude_environment` (Claude Managed Agents ortamının Tuist sandıklarında oturumlar çalıştırmasına olanak tanır).

`add_organization_member`, `cancel_organization_invitation`, `complete_project_logo_upload`, `disconnect_project_repository`, `update_test_case`, `update_notification_rule`, `delete_notification_rule`, `update_runner_profile`, `delete_runner_profile`, `delete_runner_volume`, `delete_sandbox`, `disconnect_amp_workspace`, `remove_organization_ai_provider`, `remove_organization_ai_model` ve `remove_organization_ai_task_route` mevcut durumu değiştirdiği veya kaldırdığı için `destructiveHint: true` bildirir. `invite_organization_member`, `update_test_case`, `connect_claude_environment`, `remove_organization_ai_provider` ve `report_feedback` e-posta gönderdiği, harici webhook uç noktalarını bilgilendirdiği, Anthropic'i çağırdığı veya Tuist ekibine rapor gönderdiği için `openWorldHint: true` bildirir.

Kişisel Claude ve ChatGPT abonelikleri yalnızca panonun Yapay Zekâ ayarlarında bağlanır, bu nedenle abonelik jetonları ve oturum açma işlemleri asla bir Model Context Protocol istemcisinden geçmez. Hesap kurulum araçları kullanıcı kimlik doğrulaması gerektirir. Proje jetonları veya normal hesap jetonları tarafından kullanılamazlar. Bir kullanıcı tarayıcıda bir istemciyi yetkilendirdiğinde veya bir `auth.md` kaydını talep ettiğinde, Tuist bu kimlik bilgisini yalnızca Model Context Protocol uç noktasında kullanıcıyla ilişkilendirir, böylece kurulum araçları istenen iş akışını tamamlayabilir. Herkes bir istemci kaydedebileceğinden, tarayıcıda birini yetkilendirmek istemcinin adını ve erişiminin gönderildiği ana bilgisayarı gösteren bir onay sayfası görüntüler ve Tuist kimlik bilgisini yalnızca orada onayladıktan sonra verir. Kapsam istemeyen bir istemci `mcp` kapsam grubunu alır. İstemciler PKCE'yi `S256` ile kullanmalıdır ve yönlendirme URI'leri HTTPS, döngü adresinde HTTP veya uygulamanın kendi şemasını kullanmalıdır.

Tuist, [2026-07-28 protokolünü](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http) uygular. İstekler durumsuzdur: istemciler protokol meta verilerini her istekle birlikte gönderir ve araçları başlatma olmadan doğrudan çağırabilir. `server/discover` sunucunun kimliğini, yeteneklerini, desteklenen sürümleri ve talimatları döndürür. Oturum tanımlayıcıları veya bağımsız olay akışları yoktur. 2025-06-18 veya 2025-03-26 başlatma akışını kullanan istemciler desteklenmeye devam eder; bunlar da sunucu oturumları olmadan çalışır.

## Model Context Protocol ile beceriler

Model Context Protocol araçları ve <.localized_link href="/guides/features/agentic-coding/skills">beceriler</.localized_link> yaptıkları işlerde örtüşebilir. İkisi arasındaki mevcut örtüşme göz önüne alındığında, her iş akışı için tek bir yaklaşım seçin ve aynı akışta ikisini karıştırmak yerine tutarlı bir şekilde kullanın.

Eklenti yüklemeyi destekleyen istemciler için, her ikisini birlikte yüklemek üzere <.localized_link href="/guides/features/agentic-coding/plugins">Tuist eklentilerini</.localized_link> kullanın.

## Yapılandırma

İstemcinize uzak bir Model Context Protocol sunucusu olarak `https://tuist.dev/mcp` ekleyin. Sunucunun başlatma talimatları ve genel sunucu kartı, ajanlardan harici kimlik doğrulama belgelerini getirmelerini veya takip etmelerini istemeden, dinamik istemci kaydı ve standart tarayıcı yetkilendirme akışı ile OAuth 2.0'ı satır içinde açıklar. Bu sunucu çapındaki talimatlar iş akışı rehberliğini genel tutar: araç kimlik doğrulaması yerel komut satırı araçlarını veya derleme sistemi entegrasyonlarını kimlik doğrulamaz ve ajanlar istenen değişiklikleri ilgili Tuist araçları aracılığıyla doğrulamalıdır. Derleme sistemine özel kurulum ve kimlik doğrulama kontrolleri entegrasyon kılavuzlarında ve istemlerde belgelenmiştir. Tuist, hem [Open Authorization](https://oauth.net/2/) keşif meta verilerini hem de güncel [auth.md protokolünü](https://workos.com/auth-md) `https://tuist.dev/auth.md` adresinde ayrı ayrı yayınlamaya devam eder.

Kuruluşlarınızdan biri tek oturum açmayı zorunlu kılıyorsa, tarayıcıda bir istemciyi yetkilendirmek o kuruluş üzerinden oturum açılmış bir oturum gerektirir ve Tuist gerektiğinde sizi önce sağlayıcıya yönlendirir. Bkz. <.localized_link href="/guides/integrations/authentication/sso#choose-an-enrollment-policy">tek oturum açma</.localized_link>.

Uç nokta, daha eski oturum tabanlı yaşam döngüsünün yanı sıra, `server/discover` dahil olmak üzere durumsuz `2026-07-28` Model Context Protocol istek yaşam döngüsünü kabul eder. Mevcut istemciler mevcut bağlantı yöntemlerini kullanmaya devam edebilir.

Model Context Protocol olaylarını destekleyen istemciler proje olaylarına abone olabilir. Mevcut olay ve teslimat gereksinimleri için bkz. [Olaylar](#events).

Zaten uzaktan tarayıcı kimlik doğrulamayı destekleyen istemciler, tarayıcıda kimlik doğrulamaya devam edebilir. `auth.md` destekleyen istemciler ve ajanlar anonim olarak kayıt olabilir, güvenilir bir sağlayıcı kimlik iddiası sunabilir veya hizmetle kimliği doğrulanmış bir e-posta talebi başlatabilir. Kayıt, Tuist tarafından imzalanmış bir kimlik iddiası döndürür; bu iddia, ajan tarafından standart jeton uç noktasında bir saatlik erişim jetonu ile değiştirilir. Tuist genel imzalama anahtarını yayınlamakta ve standart jeton iptalini ve sağlayıcı güvenlik olayı teslimatını desteklemektedir.

Kimliği doğrulanmamış bir ajan, Model Context Protocol uç noktası tarafından döndürülen `WWW-Authenticate` başlığını okumalı, korunan kaynak meta verilerini getirmeli, yetkilendirme sunucusu meta verilerini getirmeli ve `agent_auth.skill` URL'sini takip etmelidir. Tuist ayrıca yetkisiz yanıt gövdesinde aynı yerel `auth_md` URL'sini döndürür, böylece dil modeli odaklı istemciler yerel bir istemci entegrasyonuna güvenmeden akışı keşfedebilir. Dağıtım yerel belgesi, uç nokta adları, istek gövdeleri, talep yoklaması ve iddia değişimi için doğruluk kaynağıdır.

Bir ajan e-posta talebini başlatmadan önce, kullanıcının Tuist hesabı için e-posta adresini onaylamasını istemelidir. Bu adresi bir sağlayıcı profilinden, Git yapılandırmasından, ortam değişkeninden veya oturum meta verilerinden çıkarmamalıdır.

Uç nokta `mcp` kapsam grubunu kullanır. Anonim bir ön-talep kimlik bilgisi yetenekleri keşfedebilir ve genel entegrasyon rehberliğini okuyabilir, ancak oturum açmış bir kullanıcı olarak değerlendirilmez. Tarayıcı yetkilendirmesinden veya talepten sonra, kimlik bilgisi kullanıcı kapsamlı olur ve her araç kontrol panelindekiyle aynı yetkilendirme kontrollerini uygular. Ayrıntılar için <.localized_link href="/guides/server/authentication#scope-groups">kapsam grupları belgelerine</.localized_link> bakın.

Araçlar, kimliği doğrulanmış kullanıcının zaten okuyabildiği projelere çözülür. Xcode ve Gradle derleme araçları bir derleme UUID'sini veya kontrol paneli URL'sini kabul eder. UUID tam olarak bir projeyi tanımlamalıdır; birden fazla projede görünüyorsa, araç başka bir projenin raporunu seçmek yerine bulunamadı döndürür. Proje kapsamlı kontrol paneli ve API okumaları kullanılabilir durumda kalır. Bildirilen aktör tanımlayıcıları doğrulanmamış etiketlerdir, kimlik bilgileri veya ek erişim hakları değildir.

Derleme listesi ve ayrıntı araçları isteğe bağlı `tuist_version` meta verilerini sunar: Xcode ve Cargo için raporlayan Tuist CLI, Gradle için Tuist Gradle eklentisi ve Mix için `tuist_ex` kütüphanesi. Xcode ayrıca, yükleyen CLI'dan farklı olabilen bağlantılı proje oluşturma olayından `tuist_generation_version` değerini de sunar. Eksik gözlemler null'dur, sunucudan veya başka bir rapordan çıkarılmaz. Bazel mevcut `bazel_version` değerini kullanır; Struo çalıştırma ayrıntıları `once_version` değerini sunar. Bu alanlar bildirilen sürümleri tanımlar, doğrulanmış kimliği veya ağ sözleşmesi sürümlerini değil. REST derleme uç noktaları aynı meta verileri sunar. Mevcut entegrasyon ve kararsız test becerileri sürüm alanlarına bağlı değildir ve iş akışı değişikliği gerektirmez.

Bir müşterinin hesabını inceleyen Tuist operatörleri bunu, her çağrıyı kaydeden Tuist'in dahili operasyon araçları aracılığıyla yapar; bu uç noktaya doğrudan bir bağlantı, kullanıcının kendi üyelikleri ötesinde hiçbir erişim sağlamaz.

### Pulse

Pulse, hesabın operasyonel metrikleri, günlükleri, izlemeleri ve hataları için salt okunur araçları sunar; tümü `account_handle` ile adreslenir. İlk üçü Pulse sayfalarını ve REST API'lerini yansıtır; diğer beşi bir ajanın telemetriyi doğrudan keşfetmesine olanak tanır ve REST eşdeğeri yoktur:

| Araç | Amaç | `/api/accounts/:account_handle/pulse` altında REST eşdeğeri |
| --- | --- | --- |
| `query_pulse` | Pulse sayfa tabloları | `GET /:signal` |
| `get_pulse_analytics` | Pulse sayfa widget'ları | `GET /:signal/analytics` |
| `get_pulse_error_issue` | Bir hata sorunu ve olayları | `GET /errors/issues/:fingerprint` |
| `query_pulse_metrics` | Anlık veya aralık PromQL | Yok |
| `list_pulse_labels` | Etiket adları veya bir etiketin değerleri | Yok |
| `search_pulse_logs` | Filtrelenmiş günlük girişleri | Yok |
| `search_pulse_traces` | Filtrelenmiş span'lar | Yok |
| `get_pulse_trace` | Bir izlemenin her span'ı | Yok |

Pulse, bir hesap veya proje herkese açık olsa bile, sunucu tarafından yapılandırılan kuruluşun mevcut üyeleriyle sınırlıdır. Kullanıcı kimlik doğrulaması veya kullanıcıyla ilişkili bir `mcp` kimlik bilgisi ve hesap okuma yetkisi gerektirir. Proje jetonları, normal hesap jetonları, anonim kayıtlar ve kuruluş üyeliği olmadan operatör erişimi Pulse erişimi sağlamaz. Kimlik bilgileri başka bir arka uç veya telemetri kiracısı seçemez ve yalnızca sunucu tarafından yapılandırılan hesabın Pulse telemetrisi vardır, bu nedenle hiçbir araç başka bir hesabın verilerini okuyamaz. Tarayıcı ajanları bu araçları yalnızca Pulse sayfalarında, o sayfanın hesap kapsamı içinde alır.

REST, bir kullanıcı kimlik bilgisi gerektirir. OAuth ve `auth.md` kullanıcı ilişkileri yalnızca `/mcp` uç noktasında mevcuttur; mevcut kullanıcısı olmayan bir hesap kimlik bilgisine, ilgili hesabın üyeliği veya görünürlüğü ne olursa olsun izin verilmez.

`query_pulse`, `signal` (`metrics`, `logs`, `traces` veya `errors`), isteğe bağlı bir `query` ve `range` (`15m`, `1h`, `6h` veya `24h`, varsayılan `1h`) parametrelerini alır. Metrikler PromQL ifadelerini kabul eder. Günlükler, izlemeler ve hatalar, günlük gövdeleri, span adları ve hata sorun başlıklarıyla eşleştirilen büyük/küçük harfe duyarlı olmayan metinleri kabul eder; varsayılan olan `*` her şeyi seçer. İzleme satırları bireysel span'lardır. Hata satırları sorunlardır: hizmete ve parmak izine göre gruplandırılmış olaylar, olay sayıları, etkilenen hesaplar, pencere içindeki ilk ve son oluşumlar ve en son olaylarının başlığı, sorumlusu, seviyesi ve platformu ile birlikte. Tablolar `search`, `page` (varsayılan `1`), `page_size` (`1`–`100`, varsayılan `20`), `sort_by` ve `sort_order` (`asc` veya `desc`) parametrelerini kabul eder. Sıralama sütunları sinyale bağlıdır ve araç şemasında listelenir. Filtreler arasında `service` ve günlükler ile hatalar için `level` bulunur. Filtre operatörleri karşılık gelen `_op` bağımsız değişkenini (`eq`, `contains` veya `not_contains`) kullanır; varsayılan olarak tam eşitlik geçerlidir.

Sıralama sütunları metrikler için `name`/`value`; günlükler için `timestamp`/`service`/`level`/`message`/`trace_id`; izlemeler için `timestamp`/`service`/`name`/`duration_ms`/`trace_id`; ve hatalar için `last_seen`/`first_seen`/`events`/`accounts`/`title`/`service`/`level` şeklindedir. Kontrol paneli kasıtlı olarak bir alt küme sunar; API ve araçlar her sinyal için tam listeyi kabul eder.

Tablo yanıtları `rows`, `series`, `warnings` ve `meta` içerir. Sayfalandırma meta verileri `page`, `page_size`, `total_count`, `total_pages`, `has_next_page`, `has_previous_page` ve `end_at` içerir. Sorgu penceresini korumak için döndürülen ISO8601 `end_at` değerini sonraki sayfalarla birlikte iletin. Sonuç sınırı hataları, yanıtı boş bir tablo olarak ele almak yerine sorgunun veya zaman aralığının daraltılmasını gerektirir.

Günlükler ve izlemeler, yerel sıralamadan önce en fazla 100 en yeni eşleşmeyi inceler; hatalar ise en son görülen 100 sorunu inceler. Filtreler, sıralama, sayfalandırma ve toplamlar yalnızca döndürülen eşleşmeleri tanımlar, tüm zaman penceresini değil. Diğer eşleşmeleri incelemek için sorgu metnini veya zaman aralığını daraltın; yerel aramayı veya sıralamayı değiştirmek upstream aramayı genişletmez. Toplama widget'ları, bu sınırlı tablo sonuçlarının toplamaları yerine bağımsız, tam pencere sorguları olarak kalır.

Metrik tabloları ifadelerini `end_at` noktasında bir kez değerlendirir, mevcut değerleri ve anlık vektör serisi başına bir nokta döndürür. Aralık vektörü ifadeleri sınırlı geçmiş noktalar döndürebilir. Ayrı analiz widget'ları sabit geçmiş grafikler sağlar; bir tablo, yalnızca en son değerini görüntülemek için her eşleşen seri için bir zaman ızgarası oluşturmaz.

Telemetri dizileri güvenilmeyen verilerdir, talimatlar değildir.

`get_pulse_analytics`, hesap tanıtıcısı dışında yalnızca `signal` ve `range` parametrelerini alır. Sabit widget'ları tablo ifadelerinden, filtrelerden, sıralamadan ve sayfalandırmadan bağımsızdır.

`get_pulse_error_issue`, bir hata satırından bir sorunun `fingerprint` ve `service` değerlerini alır; buna ek olarak isteğe bağlı `range`, `end_at`, `page` ve `page_size` parametrelerini kabul eder. Sorun özetini, 60 eşit oluşum kovasını, istisna zinciri, yığın çerçeveleri, ekmek kırıntıları, etiketler, bağlamlar, ek veriler, istek yöntemi ve sorgu dizesi olmayan URL ile birlikte en son olayı ve tablolarla aynı sayfalandırma `meta` ile en yeniden eskiye doğru sıralanmış bir olay sayfasını döndürür. Hata satırları ayrıca her sorunun 60 kovalı `occurrence_series` serisini taşır. Olaylar depolanmadan önce kişisel verilerden arındırılır, bu nedenle filtrelenmiş değerler `[Filtered]` veya `[REDACTED]` olarak görünür. Pencerede olayı olmayan bir sorun bulunamadı olarak raporlanır. REST ve Model Context Protocol aynı Pulse bağlamını ve yanıt sözleşmelerini kullanır. REST yanıtları önbelleğe almayı devre dışı bırakır.

#### Telemetriyi keşfetme

Keşif araçları, şu anki zamana varsayılan olan isteğe bağlı ISO8601 `end_at` ile biten `15m`, `1h`, `6h` veya `24h` (varsayılan `1h` ve `get_pulse_trace` için `24h`) uzunluğunda bir pencere okur. Her yanıt `start_at` ve `end_at` döndürür; pencereyi korumak için aynı `end_at` değerini tekrar iletin. Bu araçların hiçbiri SQL kabul etmez.

- `query_pulse_metrics`, bir PromQL ifadesi olan `query` öğesini `end_at` noktasında (`type: instant`, varsayılan) veya pencere boyunca her `step` saniyede bir (`type: range`) değerlendirir. Adım değeri varsayılan olarak pencerenin 360'a bölünmesine eşittir ve bundan küçük olamaz, bu nedenle bir seride en fazla 361 nokta bulunur. Sonuçlarda en fazla 5.000 seri vardır. Noktalar `[unix_seconds, value]` şeklindedir ve `NaN` ile sonsuz değerler dizge olarak temsil edilir. Anlık sorgular `range` ve `step` parametrelerini reddeder.
- `list_pulse_labels`, bir `signal` alır. `label` olmadan, etiket adlarını listeler; `label` ile, o etiketin değerlerini listeler. Metrikler için `__name__`, metrik adlarını listeler ve diğer herhangi bir etiketin değerleri `up` gibi bir seri seçici olan `match` gerektirir. Günlük ve izleme etiketi değerleri `filters` kabul eder; izleme etiket adları izleme şemasından gelir ve bunu yapmaz. Günlük ve izleme değerleri, penceredeki giriş sayılarını içerir (en sık kullanılanlar önce), bu nedenle hizmete göre hatalar gibi ayrımlar olarak da işlev görürler. `search`, yalnızca değişmez metin içeren adları veya değerleri tutar ve `limit`, `1`–`1000` (varsayılan `100`) kabul eder. Günlük etiket adı keşfi, her türden en fazla 1.000 farklı öznitelik kümesini inceler ve yalnızca filtrelerin kabul ettiği anahtarları listeler.
- `search_pulse_logs`, gövdesi `text` içeren ve her filtreyi eşleştiren en fazla `limit` girişi (`1`–`100`, varsayılan `50`), `newest` veya `oldest` öncelikli olarak döndürür. Her giriş `severity_text`, `body`, `trace_id`, `span_id`, `scope_name` ve birleştirilmiş kaynak ile günlük `attributes` bilgilerini içerir. Yalnızca OTLP günlük göndericilerinin ayarladığı Kubernetes'ten toplanan günlükler için `span_id` ve `scope_name` değerleri `null` olur.
- `search_pulse_traces`, her filtreyi, isteğe bağlı `min_duration_ms` ve `max_duration_ms` değerlerini ve `root_only` koşulunu eşleştiren en fazla `limit` span'ı, `newest`, `oldest` veya `slowest` öncelikli olarak döndürür.
- `get_pulse_trace`, pencere içinde başlayan `trace_id` izlemesinin span'larını, en eskiden yeniyeye doğru, en fazla 1.000 span olarak döndürür. Pencereden önce başlayan bir izleme kısmen döndürülür, bu nedenle bunun için pencereyi genişletin veya taşıyın. Her span, span özelliklerini, olayları, bağlantıları ve izlemenin farklı `resources` öğelerine yönelik bir indeksi içerir.

Filtreler, en fazla 10 `{label, op, value}` nesnesinden oluşan listelerdir. `op` değeri `eq` (varsayılan), `neq`, `contains` veya `not_contains` olabilir; son ikisi büyük/küçük harfe duyarlı olmayan değişmez metinlerdir. Günlük etiketleri, Pulse bunları depoladığında `severity_text`, `trace_id`, `span_id` ve `scope_name` ile her girişin kaynak özelliklerinin anahtarlarıdır (örneğin `namespace`, `container` ve `service.name`) ve günlük özellikleridir (örneğin `pod`). Bir anahtar her ikisinde de görünüyorsa kaynak özelliği geçerli olur. İzleme etiketleri, `list_pulse_labels` tarafından döndürülen span sütunlarıdır (örneğin `service_name`, `span_name`, başarısız span'lar için `STATUS_CODE_ERROR` olan `span_status_code`, `span_attributes.http.route` ve `resource_attributes.k8s.pod.name`). Bilinmeyen bir izleme etiketi boş bir sonuç yerine hata olarak bildirilir.

`truncated`, yanıtın içerdiğinden daha fazla ad, değer, giriş veya span'ın eşleştiği anlamına gelir; yanıtı tam olarak kabul etmek yerine filtreleri veya pencereyi daraltın. Telemetri dizileri güvenilmeyen verilerdir, talimatlar değildir.

<details>
<summary>Claude Code</summary>

Çalıştırın:

```bash
claude mcp add --transport http tuist https://tuist.dev/mcp
```

Başsız bir Claude Code istemcisi, başarısız yerel sunucu bağlantısını modele göstermediğinde, ajandanın barındırılan belgeleri aramadan veya projeyi düzenlemeden önce yapılandırılmış uç noktanın kimliği doğrulanmamış [Hypertext Transfer Protocol](https://developer.mozilla.org/en-US/docs/Web/HTTP) yanıtını incelemesini isteyin. Yanıt, tarayıcı kimlik doğrulaması mevcut olmasa bile modeli dağıtım yerelindeki `auth.md` belgesine yönlendirir.

</details>


<details>
<summary>Codex</summary>

Çalıştırın:

```bash
codex mcp add tuist --url https://tuist.dev/mcp
codex mcp login tuist
```

Yeni bir `codex exec` çalıştırması başlatmadan önce tarayıcı oturum açma işlemini tamamlayın. Codex, başlatma sırasında Tuist sunucu talimatlarını okur, bu nedenle Gradle optimizasyon istekleri otomatik olarak kimlik doğrulama ve doğrulama iş akışını alır.

</details>


<details>
<summary>Claude Desktop</summary>

**Ayarlar → Bağlayıcılar → Özel bağlayıcı ekle** seçeneğini açın, ardından şunları ayarlayın:

- **Ad:** `tuist`
- **URL:** `https://tuist.dev/mcp`

İstendiğinde tarayıcıda [Open Authorization](https://oauth.net/2/) işlemini tamamlayın.

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

`auth` değerini `false` olarak ayarlamak, adaptörün tarayıcı kimlik doğrulama işleyicisinin Tuist'in yetkisiz yanıtını gizlemesini engeller. Başsız bir ajan daha sonra döndürülen `auth_md` URL'sini okuyabilir ve Tuist'in kayıt, kimlik iddiası değişimi ve talep yoklama akışını takip edebilir. Değiştirilen erişim belirtecini bir bearer belirteci olarak yapılandırın veya ajanın doğrudan kimliği doğrulanmış Model Context Protocol çağrıları yapmasına izin verin.

Tarayıcı kimlik doğrulamasını tercih ediyorsanız, `auth` değerini `"oauth"` olarak ayarlayın. Bu akış için, kimlik doğrulama tamamlanırken Pi'nin [remote procedure call mode](https://pi.dev/docs/latest/rpc) ile bir işlemi canlı tutun:

```bash
pi --mode rpc
```

Bekleyen bir tarayıcı kimlik doğrulamasını ayrı `pi --print` çağrılarına bölmeyin, çünkü geri arama durumuna sahip olan işlem sonlanmıştır.

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

**Komut Paleti → MCP: Sunucu Ekle** seçeneğini kullanın, ardından aşağıdaki ayarlarla bir [Hypertext Transfer Protocol](https://developer.mozilla.org/en-US/docs/Web/HTTP) sunucusu yapılandırın:

- **Ad:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>


<details>
<summary>Zed</summary>

**Ajan paneli → Ayarlar → Özel Sunucu Ekle** seçeneğini açın, ardından şunları ayarlayın:

- **Ad:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>

Ajanınız `auth.md` destekliyorsa, tarayıcı açmadan anonim olarak başlayabilir. Sağlayıcı kimliği zaten bağlıysa, güvenilir bir sağlayıcı kimliği de tarayıcı olmadan tamamlanabilir. Hizmetle kimliği doğrulanmış e-posta, anonim talep veya ilk sağlayıcı bağlantısı için ajan size bir Tuist doğrulama bağlantısı ve altı haneli bir kod gösterir. Bağlantıyı açın, oturum açın ve Tuist sayfasında ajanın kodunu girin. Kodu asla ajana geri göndermeyin. Tuist'in yetkilendirme sunucusu meta verileri, doğrudan dağıtımın kendi `/auth.md` adresine işaret eder; bu belge kesin istek ve yoklama yapılarını içerir.

## Amp orb'larında ve Claude Code bulut oturumlarında ajanlar

Bir Tuist hesabına bağlı alan kutularında (sandbox) çalışan kodlama ajanları, tarayıcı veya kaydedilmiş bir Tuist kimlik bilgisi gerekmeden kendi kimlik belirteçleriyle uç noktaya kimlik doğrulaması yapabilir:

- Hesabın **Ayarlar → Entegrasyonlar → Amp** altında bağladığı bir Amp çalışma alanının veya projesinin **Amp orb'ları**, orb'un kimlik belirtecini gönderir. Amp'te sunucunun `Authorization` başlığını `Bearer ${amp:id-token}` olarak ayarlayın. Amp, belirteci sunucu URL'sinin kaynağı için basar, bu nedenle URL bu Tuist örneğinin kendi adresi olmalıdır ve süresi dolmadan önce yeniler. Başka bir kaynak için basılan belirteçler reddedilir.
- Bağlı bir Claude Code ortamının **Claude Code bulut oturumları**, Tuist'in onlara `TUIST_OIDC_TOKEN` olarak ilettiği oturum belirtecini gönderir. Başlığı `Bearer ${TUIST_OIDC_TOKEN}` olarak ayarlayın.

Tuist'in Linux alan kutuları sunucuyu sizin için eklemez: aynı kimlikle oturum açan Tuist CLI'sini ve ajana sonuçlarını projenin geçmişine göre ne zaman kontrol etmesi gerektiğini söyleyen bir beceriyi sunarlar. Ajanlara MCP araçlarını da sağlamak için sunucuyu yukarıdaki başlıkla birlikte Amp veya Claude Code ayarlarınıza ya da projenin `.mcp.json` dosyasına ekleyin.

Bu belirteçler, bağlı hesabın her projesine salt okunur erişim sağlar: `mcp` grubunun okuma kapsamını taşırlar ve testleri sessize alma veya atlama gibi veri oluşturan, değiştiren veya silen hiçbir kapsamı taşımazlar. Çalışma alanının veya ortamın bağlantısını kesmek, bir sonraki istekte erişimi durdurur ve erişim asla belirtecin kendisinden daha uzun sürmez. Birden fazla Tuist hesabına bağlı bir Amp çalışma alanı reddedilir, çünkü belirteci tek bir hesabı adlandırmaz. Bir bağlantı eksik olduğunda, yetkisiz yanıtın `error_description` alanı bunu belirtir.

Bu salt okunur erişim yalnızca Model Context Protocol uç noktası için geçerlidir. Aynı alan kutusundaki komut satırı aracı ve derleme sistemi entegrasyonları, bağlantının CI erişimi için belirteci değiştirmeye devam eder.

## WebMCP

[WebMCP](https://webmachinelearning.github.io/webmcp) destekleyen tarayıcılarda, Tuist sayfaları araçları `document.modelContext` ile kaydeder, böylece tarayıcıya yerleşik ajanlar herhangi bir ek yapılandırma olmadan bunları çağırabilir. Çağrılar Tuist sunucusunda çalışır.

- **Web sitesi ve dokümantasyon sayfaları**, dokümantasyon ve kaynak araçlarını (`search_tuist`, `search_tuist_code`, `list_tuist_files` ve `read_tuist_file`) kaydeder. Oturum açmanıza gerek yoktur.
- Oturum açtığınızda, **bir hesabın kontrol paneli sayfaları** o hesap için Tuist'in salt okunur araçlarını kaydeder. Her sayfa yalnızca gösterdiği şeyler için, projenin derleme sistemine uygun araçları kaydeder: bir Gradle projesinin derlemeler sayfası Gradle derleme araçlarını, test sayfaları test ve kapsam araçlarını, çalıştırıcı sayfaları çalıştırıcı araçlarını ve alan kutusu sayfaları alan kutusu araçlarını alır. Her sayfa ayrıca `list_projects` ve `get_project` dokümantasyon araçlarını da alır. Araçlar, oturum açmış kullanıcı olarak çalışır, bu nedenle yalnızca kontrol panelinde okuyabileceğiniz verilere ve yalnızca baktığınız hesaba erişirler. Başka bir sayfaya veya hesaba geçtiğinizde, araçlar o sayfanın araçlarıyla değiştirilir.

Veri oluşturan, değiştiren veya silen araçlar WebMCP üzerinden kullanılamaz, çünkü bir tarayıcı ajanı araçları siz eklemeden alır ve derlemeler ile testlerin ürettiği içeriği okur. Bu araçları kullanmak için bir MCP istemcisini `/mcp` uç noktasına bağlayın.

Kuruluş tek oturum açmayı zorunlu kılıyorsa, araçlarını kullanmak için kontrol paneline sağlayıcısıyla oturum açın.

## Derleme sistemi entegrasyonları iki kimlik bilgisi kullanır

Model Context Protocol araçları için kullanılan kimlik bilgisi, Gradle eklentisini veya Bazel'in uzak hizmetlerini kimlik doğrulamaz. Bir ajan bir Gradle veya Bazel entegrasyonunu düzenlemeden veya doğrulamadan önce şunu çalıştırmalıdır:

```bash
tuist auth whoami --url https://tuist.dev
```

Bu komut kimlik doğrulaması yapmamışsa, ajan durmalı ve kullanıcıdan şunu çalıştırmasını istemelidir:

```bash
tuist auth login --url https://tuist.dev
```

Yerel veya kendi barındırdığınız bir dağıtım için, her iki komuttaki ve `tuist.toml` dosyasındaki URL'yi değiştirin. Ana bilgisayar adının yazımını her yerde aynı tutun. Örneğin, `localhost` ve `127.0.0.1` ayrı depolanmış kimlik bilgileri kullanır.


## Yetenekler

### Araçlar

Aşağıdaki araçlar Tuist Model Context Protocol sunucusu üzerinden kullanılabilir:

Her araç, açık giriş ve çıkış şemalarıyla birlikte insan tarafından okunabilir bir açıklama yayımlar. Başarılı çağrılar, duyurulan çıkış şemasına uyan yapılandırılmış içerik döndürür ve ayrıca henüz yapılandırılmış içeriği tüketmeyen istemciler için metin olarak serileştirilmiş aynı sonucu döndürür.

Tek bir kaydın tanımlayıcısını alan araçlar, örneğin `build_run_id`, `test_run_id`, `test_case_id`, `bundle_id`, `run_id`, `generation_id` veya `cache_run_id`, ayrıca o kaydın Tuist kontrol paneli URL'sini de kabul eder. Tanımlayıcıyı ayıklamak yerine URL'yi doğrudan tarayıcıdan yapıştırın.

`get_xcode_build`, `get_test_run`, `get_gradle_build` ve `get_project` `side_quests` içerebilir: Projenin kullanmadığı ancak kaydın faydalı olacağını gösterdiği Tuist yetenekleri. Her birinin bir `id`, dayandığı kanıtı belirten bir `tip` ve bir `docs` bağlantısı vardır. Ajanlardan önce kullanıcının isteğini tamamlamaları, geçerli yan görevlerden bahsetmeleri ve yalnızca kullanıcı onay verdiğinde bunlardan birini gerçekleştirmeleri istenir. Bunlar yalnızca projenin hesabının üyelerine döndürülür; ister kullanıcı oturumu, MCP jetonu veya ajan kimliği ile bağlansınlar:

| Kimlik | Araç | Önerildiğinde |
|----|------|----------------|
| `xcode_compilation_cache` | `get_xcode_build` | Xcode 26 veya üzeriyle işlenen temiz bir derleme, önbelleğe alınabilir derleme görevi çalıştırmadı. |
| `gradle_build_cache` | `get_gradle_build` | Bir derleme, Gradle'in derleme önbelleği bunlardan hiçbiri için bir anahtar hesaplamadan önbelleğe alınabilir görevleri yürüttü, yani derleme önbelleği kapalıydı. |
| `flaky_test_quarantine` | `get_test_run` | Bir çalıştırmada kararsız testler vardı ve projede bunları sessize alan veya atlayan etkin otomasyon yoktu. Struo projeleri için önerilmez. |
| `test_sharding` | `get_test_run` | Tuist'in parçalara bölebileceği bir derleme sisteminde, parçalara bölünmemiş bir CI çalıştırması 10 dakika veya daha fazla sürdü. İpucu, seçici testin ne zaman kaç testi atladığını belirtir. |
| `tuist_runners` | `get_xcode_build`, `get_test_run` | Bir CI çalıştırması GitHub Actions, Bitrise, GitLab CI veya Buildkite makinelerini kullandı ve hesap hiçbir zaman Tuist Runners üzerinde bir iş çalıştırmadı. Yalnızca tuist.dev'de. |
| `pull_request_comments` | `get_xcode_build`, `get_test_run` | Bir GitHub Actions çalıştırması, GitHub deposuna bağlı olmayan bir projeye aittir. |
| `other_build_systems` | `get_project` | Hesap, desteklenen her derleme sistemiyle Tuist'i kullanmıyor. İpucu, diğerlerini tanımlayan dosyaları listeler, böylece ajan depoyu kontrol edebilir. |

#### Dokümantasyon ve topluluk araması

Bu salt okunur araç, dokümantasyon web sitesini güçlendiren aynı arama motoru aracılığıyla Tuist'in dokümantasyonunu, [uygulama programlama arayüzü](https://en.wikipedia.org/wiki/API) referansını, GitHub sürümlerini, topluluk forumunu ve GitHub sorunlarını arar. Sürüm sonuçları ürünü, sürümü, yayın tarihini ve ön sürüm durumunu içerir. Varsayılan olarak kararlı sürümler aranır ve ön sürümler `include_prereleases` ile dahil edilebilir. Araç yalnızca `https://tuist.dev/mcp` adresindeki Tuist tarafından barındırılan sunucuda kullanılabilir.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `search_tuist` | Genel Tuist dokümantasyonunu, uygulama programlama arayüzü referansını, GitHub sürümlerini, topluluk tartışmalarını ve GitHub sorunlarını arayın. İsteğe bağlı olarak tek bir `source` (`docs`, `api_reference`, `releases`, `forum`, `issues`) ile sınırlayın. | `query` |

#### Geri bildirim

Ajanlar, bir Tuist aracının veya isteminin bekledikleri gibi çalışmadığında (örneğin kafa karıştırıcı bir sonuç, hata, eksik veri veya eksik bir yetenek) Tuist ekibine bildirebilir. Ajanlardan bir rapor önermeleri ve bunu yalnızca siz onay verdikten sonra göndermeleri istenir. Her rapor, Tuist desteği ile bir konuşma başlatır; destek ekibi size e-posta ile yanıt verebilir. Bir rapor, ajanın ne beklediğini, ne olduğunu, isteğe bağlı bir öneriyi, Tuist kullanıcı kimliğinizi, kullanıcı adınızı ve e-postanızı ve ait olduğunuz kuruluşları içerir. Ajanlar ayrıca sorunun yaşandığı hesabı ve projeyi belirtebilir, böylece ekip hangi kuruluşa geri dönüş yapacağını bilir; yalnızca ait olduğunuz hesaplar kabul edilir. Raporları yalnızca Tuist kullanıcısı olarak oturum açmış ajanlar gönderebilir ve her kullanıcı saatte en fazla 10 rapor açabilir. Araç yalnızca `https://tuist.dev/mcp` adresindeki Tuist tarafından barındırılan sunucuda kullanılabilir.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `report_feedback` | Bir Tuist aracı veya istemiyle ilgili bir sorunu bildirin. İsteğe bağlı olarak `tool_name`, gerçekleştiği `account_handle` ve `project_handle` adlandırın ve bir `suggestion` ekleyin. | `category`, `expected`, `actual` |

#### Kaynak destekli yanıtlar

Bu salt okunur araçlar, ajanların mevcut davranışa bağlı yanıtlar için gerçek kaynak olarak barındırılan sunucuyla birlikte dağıtılan tam genel Tuist kaynak revizyonunu kullanmasına olanak tanır. Yalnızca `https://tuist.dev/mcp` adresinde kullanılabilirler.

Uyumlu istemciler, satır içi OAuth kimlik doğrulama bilgilerinin yanı sıra başlatma sırasında araçların kaynak revizyonu, bağlantılar ve sonuç sınırları hakkında gerçek açıklamalar alır. Bu açıklamalar yanıt stilini veya bir doğrulama iş akışını dikte etmez. Kullanıcılar, önce `ask_tuist` istemini çağırmadan doğrudan bir soru sorabilir; istem, açık bir kaynak destekli iş akışı için kullanılmaya devam eder.

Her işlem için eşzamanlılık, süre, gezinme, okunan bayt ve yanıt boyutu açısından sabit sınırlar vardır. Arama ve listeleme sonuçları `truncated` ve `truncation_reason` alanlarını içerir. Bir sonuç kısaltıldığında, sonucu kapsamlı olarak değerlendirmek yerine yolu, dosya desenini veya arama terimini daraltın.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `search_tuist_code` | Kaynak dosyaları arayarak mevcut davranış, varsayılanlar, yapılandırma, özellik kapıları, hata işleme veya belgelenmemiş ayrıntılar hakkındaki soruları yanıtlayın. Sonuçlar çevreleyen satırları, revizyonla sabitlenmiş kaynak bağlantılarını ve tarama istatistiklerini içerir. | `pattern` |
| `list_tuist_files` | İlgili yol bilinmediğinde bir kaynak alt sistemini veya yakındaki testleri keşfedin. Listelemelerin sınırlı derinliği ve sonuç sayıları vardır. | Yok |
| `read_tuist_file` | İlgili yolu bulduktan sonra bir uygulama dosyasındaki, çağrı noktasındaki veya testteki odaklanmış satır aralığını inceleyin. Kısaltılmış yanıtlar, devam etmek için `next_start_line` sağlar. | `path` |

#### Projeler

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_accounts` | Kimliği doğrulanmış kullanıcı için kullanılabilen kişisel ve kuruluş hesap kullanıcı adlarını, her hesabın proje oluşturup oluşturamayacağı dahil olmak üzere listeleyin. | Yok |
| `get_organization` | Bir kuruluşun üye dizinini alın. Bekleyen davetler, gösterge paneliyle aynı yönetici iznini gerektirir; davet kabul belirteçleri asla döndürülmez. | `account_handle` |
| `create_organization` | Kimliği doğrulanmış kullanıcı için bir Tuist kuruluşu oluşturun. | `handle` |
| `create_project` | Kimliği doğrulanmış kullanıcının erişebileceği bir hesap altında bir Tuist projesi oluşturun. | `account_handle`, `project_handle` |
| `add_organization_member` | Mevcut bir Tuist kullanıcısını bir kuruluşa ekleyin veya mevcut bir üyenin rolünü güncelleyin. `user` (varsayılan), `admin` veya `viewer` kabul eder; burada görüntüleyici panoları ve çalıştırmaları okuyabilir ancak hiçbir şeyi değiştiremez. | `organization_handle`, `email` |
| `invite_organization_member` | Bir e-posta adresini, mevcut bir Tuist kullanıcısına ait olup olmadığına bakmaksızın bir kuruluşa davet edin. Tuist, 14 gün sonra sona eren bir kabul bağlantısı e-postayla gönderir; sunucu e-posta gönderemediğinde `email_sent` değeri `false` olur ve bağlantının gösterge panelinden kopyalanması gerekir. `user` (varsayılan), `admin` veya `viewer` kabul eder. Kuruluş yöneticisi izni gerektirir. | `organization_handle`, `email` |
| `cancel_organization_invitation` | Bekleyen bir kuruluş davetini iptal ederek bağlantısının artık kabul edilememesini sağlayın. Kuruluş yöneticisi izni gerektirir. | `organization_handle`, `email` |
| `list_projects` | Kimliği doğrulanmış kullanıcının erişebileceği tüm projeleri listeleyin. | Yok |
| `get_project` | Bir projenin yapılandırmasını ve bağlı depo URL'sini alın. | `account_handle`, `project_handle` |
| `connect_project_repository` | Bir projeyi, hesabın GitHub Uygulaması yüklemesinin erişebileceği bir GitHub deposuna bağlayın. Proje, deponun varsayılan dalını benimser. Proje yöneticisi izni gerektirir. | `account_handle`, `project_handle`, `repository_full_handle` |
| `disconnect_project_repository` | Bir projenin GitHub deposuna olan bağlantısını kaldırın. Proje yöneticisi izni gerektirir. | `account_handle`, `project_handle` |

#### Hesap belirteçleri

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_account_tokens` | Belirteç değerlerini açığa çıkarmadan hesap belirteci meta verilerini listeleyin. | `account_handle` |
| `get_account_token` | Değerini açığa çıkarmadan hesap belirteci meta verilerini alın. | `account_handle`, `token_id` |
| `list_project_tokens` | Belirteç değerlerini açığa çıkarmadan proje belirteci meta verilerini listeleyin. | `account_handle`, `project_handle` |

#### Bildirim kuralları

Bu araçlar, kimliği doğrulanmış kullanıcının kendi bildirim kurallarını yönetir: Yeni bir önizleme gibi bir olay, kuralın projelerinde (veya hiçbiri listelenmediğinde bildirim alabileceğiniz herhangi bir projede) gerçekleştiğinde ve koşullarını karşıladığında, Tuist uygulama cihazlarınıza anlık bildirim göndermek gibi eylemlerini yürütür. Kural olmadan bildirim almazsınız. Kullanıcı kimlik doğrulaması gerektirirler, yalnızca kendi kurallarınız üzerinde işlem yaparlar ve yalnızca ait olduğunuz hesaplara ait projeleri kabul ederler. Kurallar tüm hesaplarınızı kapsadığından gösterge paneli sayfalarında sunulmazlar.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_notification_events` | Kuralların abone olabileceği olay türlerini, her biri için koşullarına ilişkin bir JSON Şemasıyla birlikte listeleyin. | Yok |
| `list_notification_condition_options` | Bir projedeki bir olay için koşul değerleri önerin; örneğin, son önizlemelerinin yolları ve dalları. | `event`, `account_handle`, `project_handle` |
| `list_notification_rules` | Kurallarınızı listeleyin. | Yok |
| `create_notification_rule` | Bir olaydan, isteğe bağlı projelerden ve koşullardan ve en az bir eylemden oluşan bir kural oluşturun. | `event`, `actions` |
| `update_notification_rule` | Bir kuralın etkin durumunu, projelerini, koşullarını veya eylemlerini değiştirin. | `rule_id` |
| `delete_notification_rule` | Bir kuralı silin. | `rule_id` |

#### Sürekli entegrasyon çalıştırıcıları

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_runner_jobs` | Bir hesap için sürekli entegrasyon çalıştırıcı işlerini listeleyin. | `account_handle` |
| `get_runner_job` | Bir sürekli entegrasyon çalıştırıcı işini alın; makinenin belleğinin tükenip tükenmediği, neyi durdurduğu ve neyin değiştirilmesi gerektiği dahil. | `account_handle`, `workflow_job_id` |
| `list_runner_job_steps` | Bir sürekli entegrasyon çalıştırıcı işi için kaydedilen adımları listeleyin. | `account_handle`, `workflow_job_id` |
| `list_runner_job_metrics` | Bir sürekli entegrasyon çalıştırıcı işi için kaydedilen makine metriklerini listeleyin. | `account_handle`, `workflow_job_id` |
| `list_runner_job_logs` | Bir sürekli entegrasyon çalıştırıcı işi için yakalanan en fazla 500 günlük satırını listeleyin. | `account_handle`, `workflow_job_id` |
| `list_runner_workflows` | Bir hesap için sürekli entegrasyon iş akışı özetlerini listeleyin. | `account_handle` |
| `list_runner_profiles` | Bir hesap için sürekli entegrasyon çalıştırıcı profillerini, her birinin `runs-on` etiketiyle birlikte listeleyin. | `account_handle` |
| `get_runner_catalog` | Bir çalıştırıcı profilinin kullanabileceği makine şekillerini ve Xcode sürümlerini listeleyin. | `account_handle` |
| `create_runner_profile` | Bir platform, bir makine şekli ve macOS'ta bir Xcode sürümü ile bir çalıştırıcı profili oluşturun. İsteğe bağlı olarak hangi dalların önbellek birimlerini kaydedeceğini ayarlayın. Hesap yöneticiliği veya `account:runners:write` kapsamı gerektirir. | `account_handle`, `name`, `platform`, `vcpus`, `memory_gb` |
| `update_runner_profile` | Bir çalıştırıcı profilinin makine şeklini, Xcode sürümünü veya özel önbellek birimi değişikliklerini hangi dalların kaydedeceğini değiştirin. Atlanmış alanlar değerlerini korur. Hesap yöneticiliği veya `account:runners:write` kapsamı gerektirir. | `account_handle`, `profile_name` |
| `delete_runner_profile` | Kullanıcı onayından sonra bir çalıştırıcı profilini silin. Varsayılan profiller silinemez. Hesap yöneticiliği veya `account:runners:write` kapsamı gerektirir. | `account_handle`, `profile_name` |

Çalıştırıcı birimi araçları, Birimler gösterge panelindekiyle aynı verileri ortaya çıkarır. Okuma araçları çalıştırıcı erişimi gerektirir; temizleme işlemi hesap yöneticiliği veya `account:runners:write` kapsamı ve kullanıcı onayı gerektirir.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_runner_volumes` | Birimleri ada ve depoya göre filtreleyin, sıralayın ve sayfalandırın. | `account_handle` |
| `get_runner_volume` | Depo, platform, kapasite, kullanılan alan ve son kullanım. | `account_handle`, `volume_id` |
| `list_runner_volume_jobs` | Sayfalandırılmış iş ve iş akışı referansları, önbellek durumu, isabet sonucu ve bağlama süresi. | `account_handle`, `volume_id` |
| `list_runner_job_volumes` | Bir iş tarafından bağlanan birimler. | `account_handle`, `workflow_job_id` |
| `get_runner_volume_analytics` | Depolama serileri, iş çalıştırmaları, isabet oranı ve eğilimler. İsteğe bağlı `volume_id`, `start` ve `end` (ISO 8601); varsayılan yedi gün, maksimum 90. | `account_handle` |
| `delete_runner_volume` | Bir birimi ve kaydedilen içeriğini silin. Çalışan işler özel kopyalarını tutar ancak bunları kaydedemez; aynı anahtara sahip sonraki işler boş başlar. | `account_handle`, `volume_id` |

Listeler `page` ve `page_size` (en fazla 100) kabul eder. Birim envanteri ayrıca `name` ve `repository` (tam eşleşmeler, AND ile birleştirilmiş), `sort_by` (`volume`, `repository`, `used_space`, `capacity`, `last_used`) ve `sort_order` (`asc`, `desc`) kabul eder. Bilinmeyen ölçümler ve isabet sonuçları `null` olarak kalır. Önbellek durumu, iş başarısını değil, birim değişikliklerinin kaydedilip kaydedilmediğini açıklar.

#### Sandbox'lar

Sandbox araçları, Sandbox'lar gösterge panelindekiyle aynı verileri ve eylemleri, [API](https://tuist.dev/api/docs) ile aynı erişimle ortaya çıkarır: hesap üyeleri hesaptaki her sandbox'ta her aracı kullanabilir. Salt okunur görüntüleyiciler bunları kullanamaz. Hesabın sandbox'ların etkinleştirilmiş olması gerekir. Gösterge panelinin sandbox sayfaları salt okunur araçları kaydeder.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_sandboxes` | Sandbox'ları durumları, şekilleri ve zaman damgalarıyla sayfalandırın. İsteğe bağlı `search` (sandbox'taki metin, Amp Orb veya Anthropic oturum kimliği), `status`, `vcpus`, `sort_by` (`created`, `last_active`, `identifier`) ve `sort_order`. | `account_handle` |
| `get_sandbox` | Bir sandbox'ın durumu, şekli, düğümü, arşivi ve zaman damgaları. | `account_handle`, `sandbox_id` |
| `get_sandbox_analytics` | vCPU-saatleri, oluşturulan sandbox'lar, oturum, kurulum ve başlama süreleri ve hesabın sınırlarına göre tepe vCPU'lar, bellek ve disk, eğilimlerle birlikte. İsteğe bağlı `start` ve `end` (ISO 8601); varsayılan 30 gün, maksimum 90. | `account_handle` |
| `create_sandbox` | Boş bir sanal alanı başlatın ve çalışmaya başladığında döndürün. İsteğe bağlı `platform` (`linux` veya `darwin`), `xcode_version` (bir macOS sanal alanının tam Xcode sürümü; aracın açıklamasında listelenenlerden seçilir; `darwin` anlamına gelir), `repository` (bir macOS sanal alanının github.com `owner/name`, hesabın projelerinden birine bağlı: Linux Claude Code ortamında bir macOS kurulum betiği varsa Mac <.localized_link href="/guides/features/sandboxes/claude#remote-mac-snapshots">hazır anlık görüntüsünden</.localized_link> önyüklenir), `template`, `vcpus` ile `memory_mb` (Linux: 2x4096, 4x8192 veya 8x16384, varsayılan 2x4096; macOS: 8x8192, 8x16384 veya 8x24576, varsayılan 8x8192) `workspace_gb` ve `lifetime_seconds` (çalışan komutları iptal edilmeden, duraklatılıp arşivlenmeden ve dosyaları korunarak ne kadar süre çalışabileceği: varsayılan olarak iki saat, en fazla bir gün). Açıklaması, aracıya deponun kullandığı Xcode'u bulmasını (`.xcode-version`, mise, CI yapılandırması veya belgeler) ve bunu iletmesini söyler; çünkü başka bir Xcode deponun önbelleklerini ve anlık görüntüsünü kaçırır. Ayrıca Mac'in `/opt/tuist/agent-guide.md` konumunda taşıdığı kılavuzu okumasını ister. Mac'teki Tuist, depo bir sürüm sabitlediğinde o sabitlenmiş sürümü kullanır ve <.localized_link href="/guides/features/sandboxes#tuist-in-sandbox">hesabın önbelleğini</.localized_link> kendi başına kullanır. | `account_handle` |
| `pause_sandbox` | Çalışan bir sandbox'ın anlık görüntüsünü düğümünün diskine alın. | `account_handle`, `sandbox_id` |
| `resume_sandbox` | Duraklatılmış veya arşivlenmiş bir sandbox'ı devam ettirin. | `account_handle`, `sandbox_id` |
| `extend_sandbox` | Bir sandbox'ın yaşam süresini şimdi yeniden başlatın, isteğe bağlı `lifetime_seconds` ile (en fazla bir gün). Bir entegrasyonun sahibi olduğu sandbox'ların süresi yoktur. | `account_handle`, `sandbox_id` |
| `archive_sandbox` | Duraklatılmış bir sandbox'ın disklerini nesne depolamaya taşımak için sıraya alın. | `account_handle`, `sandbox_id` |
| `delete_sandbox` | Kullanıcı onayından sonra bir sandbox'ı ve disklerini silin. | `account_handle`, `sandbox_id` |

Bir sandbox aracının hatası, kendi satırında kararlı bir kodla başlar, örneğin `code: fleet_busy`, ardından ne yapılacağı gelir; bekleme içeren kodlar bir `retry_after_seconds:` satırı ekler. API, hata gövdesinde aynı `code` kodunu gönderir. Her sunucu meşgul olduğunda, `create_sandbox` yanıt vermeden önce biri için en fazla 25 saniye bekler ve ardından `fleet_busy` yanıtını verir.

#### Amp çalışma alanları

Bu araçlar, orb'ların belirteç olmadan Tuist'te oturum açmasına olanak tanıyan <.localized_link href="/guides/server/authentication#amp-orbs">Amp çalışma alanı bağlantılarını</.localized_link> yönetir. Gösterge panelinin Entegrasyonlar sayfasındakiyle aynı yöneticiye özel izni kullanırlar. Bir orb'daki aracı, kendi kimliklerini `$AMP_WORKSPACE_ID` ve `$AMP_PROJECT_ID` üzerinden okuyabilir. Bir bağlantının kabul ettiği her orb, hesaptaki tüm projelere CI erişimi kazanır, bu nedenle ajanlar bağlanmadan önce kullanıcıyla onaylamalıdır.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_amp_workspace_connections` | Hesabın bağlı Amp çalışma alanlarını ve her birinin sınırlandığı projeyi, varsa listeleyin. | `account_handle` |
| `connect_amp_workspace` | Bir Amp çalışma alanını bağlayın. İsteğe bağlı `project_id`, oturum açmayı tek bir Amp projesinin orb'larıyla sınırlar. | `account_handle`, `workspace_id` |
| `disconnect_amp_workspace` | Bir çalışma alanının bağlantısını kesin. Orb'larının zaten sahip olduğu oturumlar, sona erene kadar geçerli kalır. | `account_handle`, `connection_id` |

#### Claude ortamları

Bu araçlar, Claude Managed Agents kendi kendine barındırılan ortamlarını bağlar, böylece oturumları Ayarlar → Entegrasyonlar → Claude'daki gibi Tuist sandbox'larında çalışır. Hesap yönetimi ve sandbox'ların etkinleştirilmesini gerektirirler. Bir aracı, ortamı Anthropic'in API'si ile oluşturabilir, ancak yalnızca Claude Console ortam anahtarını oluşturur, bu nedenle aracı kullanıcıdan bunu ister. Tuist, oturumları bir Anthropic API anahtarı veya iş yükü kimlik federasyonu ile başlatır ve kaydetmeden önce ortamı bu kimlik bilgisiyle getirir. Anthropic tarafındaki kurulum, kullanıcının kendi Anthropic kimlik bilgilerini kullanır; Tuist bunları asla almaz. Anahtarlar istemci ve model üzerinden geçtiği için, bunları yalnızca açıkça sağlayın.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_claude_environments` | Bağlı ortamları ve her birinin kullandığı kimlik bilgisini, ayrıca bir federasyon kuralının güvenmesi gereken yayıncı URL'sini ve konu önekini listeleyin. | `account_handle` |
| `connect_claude_environment` | Bir ortamı `api_key` ile veya `organization_id`, `workspace_id`, `service_account_id` ve `federation_rule_id` ile bağlayın. İsteğe bağlı `platform`, `vcpus` ve `memory_mb` sandbox yapısını belirler. | `account_handle`, `environment_id`, `environment_key` |

#### Kuruluş Yapay Zekası

Bu araçlar, Ayarlar → Yapay Zeka'daki gibi bir kuruluşun sunucu tarafı yapay zeka görevlerinin kullandığı modelleri yönetir ve kurallarını paylaşır: yalnızca kuruluş yöneticileri için ve yalnızca yapay zeka ayarlarına sahip kuruluşlar için. Her görev, örneğin `pulse_grouping` veya `pulse_explanation`, varsa kendi görev rotasını, yoksa varsayılan modeli kullanır; ikisi de yoksa hiçbir istek göndermez. Her araç, her görevin mevcut modelini ve bunun rotasından, varsayılandan mı yoksa hiçbiri mi geldiğini içeren tüm yapılandırmayı döndürür. Bir sağlayıcı eklemek veya düzenlemek bir API anahtarı gerektirir, bu nedenle bu işlem gösterge panelinde veya REST API (`/api/accounts/{handle}/ai`) üzerinden yapılır, bu araçlar üzerinden değil.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `get_organization_ai_configuration` | Sağlayıcıları (anahtarlar olmadan), modelleri, varsayılan modeli, görev rotalarını ve her görevin mevcut modelini okuyun. | `account_handle` |
| `save_organization_ai_model` | Bir model ekleyin (`name`, `provider_id`, `upstream_model_id`), veya `id` ile birini güncelleyin. | `account_handle` |
| `remove_organization_ai_model` | Bir modeli ve onun görev rotalarını kaldırın. | `account_handle`, `model_id` |
| `set_organization_ai_default_model` | Varsayılan modeli seçin veya null ile temizleyin. | `account_handle`, `model_id` |
| `save_organization_ai_task_route` | Bir `task` görevini yapılandırılmış bir `model_id` modeline yönlendirin veya bir rotayı `id` ile güncelleyin. Bir görevin en fazla bir rotası olabilir. | `account_handle` |
| `remove_organization_ai_task_route` | Bir rotayı kaldırın, böylece görev tekrar varsayılan modeli kullanır. | `account_handle`, `route_id` |
| `remove_organization_ai_provider` | Bir sağlayıcıyı anahtarı, modelleri ve onların rotalarıyla birlikte kaldırın; bağlı bir Claude kuruluşunun bağlantısını keser. | `account_handle`, `provider_id` |

#### Webhook'lar

Webhook araçları, gösterge panelindekiyle aynı yöneticiye özel izni kullanır. Teslimat denemeleri, uç nokta için kaydedilen istek ve yanıt verilerini içerir, ancak asla uç nokta imzalama gizli anahtarını içermez.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_webhook_endpoints` | Bir hesap için webhook uç noktalarını listeleyin. | `account_handle` |
| `get_webhook_endpoint` | Bir webhook uç noktası alın. | `account_handle`, `webhook_endpoint_id` |
| `list_webhook_delivery_attempts` | Bir uç nokta için teslimat denemelerini listeleyin. | `account_handle`, `webhook_endpoint_id` |
| `get_webhook_delivery_attempt` | Bir teslimat denemesi alın. | `account_handle`, `webhook_endpoint_id`, `delivery_attempt_id` |

#### Xcode derlemeleri

Xcode, Gradle, Bazel, Mix ve Cargo için derleme ayrıntısı araçları, mevcut `custom_metadata: {tags, values}` yapısını, bildirildiğinde altyapı gözlemleri dahil olmak üzere ortaya çıkarır. Değerler dize olarak kalır ve bilinmeyen anahtarlar korunur. Örneğin, `tuist.cpu.available_processors` çalışma zamanında kullanılabilen mantıksal işlemcileri tanımlarken, `tuist.gradle.max_workers` bir Gradle işçi sınırıdır ve `tuist.jvm.max_heap_bytes` bir JVM yığın sınırıdır, ana makine belleği değil. Bunlar güvenilir olmayan istemci gözlemleridir, doğrulanmış çalıştırıcı kimlikleri değildir. Eksik gözlemler eksik kalır; içe aktarılan günlükler ve daha eski istemcilerde altyapı meta verileri olmayabilir. Struo meta verileri koordineli bir istemci/protokol güncellemesini bekliyor.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_xcode_builds` | Bir proje için Xcode derleme çalıştırmalarını listeleyin. | `account_handle`, `project_handle` |
| `get_xcode_build` | Belirli bir Xcode derleme çalıştırması hakkında, ham `.xcactivitylog` dosyasını içeren arşiv için geçici bir indirme URL'si dahil olmak üzere ayrıntılı bilgi alın. | `build_run_id` |
| `list_xcode_build_targets` | Belirli bir Xcode derleme çalıştırması için derleme hedeflerini listeleyin. | `build_run_id` |
| `list_xcode_build_files` | Belirli bir Xcode derleme çalıştırması için derlenmiş dosyaları listeleyin. | `build_run_id` |
| `list_xcode_build_steps` | Günlük metni olmadan, zamanlamalar ve sonuçlarla birlikte kaydedilmiş derleme adımlarını listeleyin. | `build_run_id` |
| `get_xcode_build_step` | Günlüğü ve kırpma bayrağı dahil olmak üzere tek bir kaydedilmiş derleme adımını alın. | `build_run_id`, `step_id` |
| `list_xcode_build_issues` | Belirli bir derleme çalıştırması için derleme sorunlarını (uyarılar ve hatalar) listeleyin. | `build_run_id` |
| `list_xcode_build_cache_tasks` | Belirli bir Xcode derleme çalıştırması için önbelleklenebilir görevleri (önbellek isabetleri/ıskaaları) listeleyin. | `build_run_id` |
| `list_xcode_build_cas_outputs` | Belirli bir Xcode derleme çalıştırması için [içerik adreslenebilir depolama](https://en.wikipedia.org/wiki/Content-addressable_storage) çıktılarını listeleyin. | `build_run_id` |

`list_xcode_build_steps` varsayılan olarak 20 adımlık sayfalar döndürür (`page_size` ile maksimum 100), gezinme için `page` ve `pagination_metadata` sağlar. Başlıkları, projeleri veya hedefleri eşleştirmek ya da tam `project`, `target`, `category` (örneğin, `swiftCompilation`) ve `status` (`success` veya `failure`) değerlerini filtrelemek için `search` kullanın. En yavaş olanı önce getirmek için `duration_ms` ile veya kronolojik sıralama için `start_ms` ile sıralayın. Adım kimlikleri eşitliği bozar ve 64 bitlik hassasiyetlerini korumak için ondalık dizeler olarak döndürülür. Kimlikler bir derlemeye özeldir ve derlemeler arasında eşleştirilmemelidir.

İsteğe bağlı `start_ms` ve `end_ms`, derleme başlangıcından itibaren milisaniye cinsinden bir zaman aralığıyla örtüşen adımları seçer; bitiş hariçtir. Her iki araç da `build_run_id` olarak bir derleme UUID'sini veya gösterge paneli URL'sini kabul eder. Döndürülen adım `id` değerini değiştirmeden `step_id` olarak geçirerek günlüğünü alın. Günlükler adım başına en fazla 64 KiB tutar, `log_truncated` atlanan çıktıyı belirtir.

Xcode derlemeleri işlendiğinde adımlar varsayılan olarak toplanır. Kaydedilen adım verileri 90 gün boyunca saklanır. Liste yanıtı `availability` içerir: kaydedilmiş adımlar varsa, hiçbir filtre eşleşmese bile `available`; derleme hala işleniyorsa ve henüz adım yoksa `processing`; veya adımlar kaydedilmediyse ya da süresi dolduysa `unavailable`.

Aynı işlemler, aynı filtreler ve sayfalama ile `GET /api/projects/{account_handle}/{project_handle}/xcode/builds/{build_id}/steps` ve `GET /api/projects/{account_handle}/{project_handle}/xcode/builds/{build_id}/steps/{step_id}` HTTP API uç noktalarında mevcuttur. Her ikisi de derlemenin projesine okuma erişimi gerektirir.

#### Gradle derlemeleri

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `get_gradle_integration_guide` | Tam kimlik doğrulama, proje kurulumu, Gradle eklentisi, önbellek politikası ve iki derlemeli doğrulama iş akışını döndürün. Aracılar, mevcut bir Android veya Gradle projesini düzenlemeden önce bunu çağırmalıdır. | Yok |
| `list_gradle_builds` | Özel meta veriler dahil olmak üzere bir proje için Gradle derleme çalıştırmalarını listeleyin. İsteğe bağlı `tag` parametresi ile özel bir etikete göre filtreleyin. | `account_handle`, `project_handle` |
| `get_gradle_build` | Derleme meta verilerini, görev/önbellek sayılarını ve `failures` öğesini alın: başarısız olan her görevin ve yapılandırma adımının hata mesajı. | `build_run_id` |
| `list_gradle_build_tasks` | Görev sonuçlarını, bileşik derleme kimliğini, önbelleklenebilirliği, artımlı durumu ve hata mesajlarını listeleyin. | `build_run_id` |
| `list_gradle_build_steps` | Arama, meta veri ve örtüşen zaman filtreleriyle zamanlanmış görevleri, yapılandırmayı ve dönüşümleri listeleyin. | `build_run_id` |
| `get_gradle_build_step` | Kaydedilmiş adım meta verilerini opak kimliğe göre inceleyin; başarısız bir görevin veya yapılandırma adımının `log` değeri onun hata mesajıdır. | `build_run_id`, `step_id` |

Gradle ve Bazel adım listeleri varsayılan olarak 20 sonuç döndürür (maksimum 100), `search`, tam `project`, `target`, `category` ve `status`, örtüşen `start_ms` / `end_ms` filtrelerini (bitiş hariç) ve `duration_ms` veya `start_ms` sıralamasını destekler. Döndürülen kimlikleri değiştirmeden geçirin; bunlar kendi derlemelerine özeldir. Listeler `time_origin` ve `coverage` sunar. Daha eski Gradle raporları, derleme başlangıcı yüklenmediği için `first_recorded_timestamp` kullanır. Bazel profilleri, tüm kaydedilen aralıkları `trace_profile` kapsamı ve zaman kökeni olarak `profile_start` ile ortaya çıkarır. Daha eski derlemeler, saklanan BEP özetlerine geri döner. Kaynak kayıtlar 90 gün sonra sona erer. Bazel ayrıntıları, yayınlandığında temizlenmiş eylem günlüklerini içerir. Başarısız bir görevin veya yapılandırma adımının Gradle ayrıntıları, Tuist Gradle eklentisinin `log` olarak bildirdiği hata mesajını içerir: istisna mesajı ve neden zinciri, Gradle konsolunun yazdırdığı şekilde, yığın izleri veya görev çıktısı olmadan, proje içindeki yollar göreceli hale getirilmiş ve kimlik bilgileri ile diğer yerel yollar sansürlenmiş, adım başına en fazla 16 KiB ve derleme başına 32 başarısız adım. Diğer Gradle adımları, daha eski eklenti sürümleri tarafından bildirilen derlemeler ve kimlik bilgisi içermeyen raporlar null `log` değerine sahiptir. Yapılandırma adımları başarısız olduklarında `failure`, aksi takdirde `unknown` bildirir. `compare_builds` istemi, tam Bazel izlerini saklanan özetlerden ayırt etmek için bu kapsamı kullanır ve aracıları, daha geniş çağrı çıktısını kontrol etmeden önce eylem sonuçları ve günlükler için adım ayrıntılarına yönlendirir.

Tek adımlı araçlar `get_gradle_build_step` ve `get_bazel_build_step` bir adımı kimliğe göre alır ve zaman filtrelerini kabul etmez; adımları zaman aralığına göre filtrelemek için ilgili liste araçlarını kullanın.

Saklanan özetlerden döndürülen Bazel adım kimlikleri, bir adım listelenip alındıktan sonra tam bir profil gelirse okunabilir kalır. Adım verilerinin süresi dolmuş indekslenmiş bir profil, kullanılamaz olarak raporlanır. Gradle adım listeleri, sıfır süreli önbelleklenmiş ve atlanan işlemleri içerir.

#### Bazel çağrıları

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `get_bazel_integration_guide` | Kimlik doğrulama, proje kurulumu, Bazel yapılandırması ve doğrulama iş akışını döndürün. | Yok |
| `list_bazel_invocations` | Tamamlanmış [Bazel Derleme Olay Protokolü](https://bazel.build/remote/bep) çağrılarını en yeniden eskiye doğru, derleme metrikleri, sınırlı bir yürütme zaman çizelgesi, kritik yol tanılama ve bir proje için ilişkili uzak önbellek toplamlarıyla listeleyin. `status`, `git_branch`, `git_commit_sha`, `is_ci` ve `command` ile filtreleyin. | `account_handle`, `project_handle` |
| `get_bazel_invocation` | Derleme metrikleri, sınırlı bir yürütme zaman çizelgesi, kritik yol tanılama ve ilişkili uzak önbellek toplamları ile tek bir tamamlanmış Bazel çağrısını alın. | `account_handle`, `project_handle`, `invocation_id` |
| `list_bazel_build_steps` | Filtreler ve açık kapsam ile kaydedilmiş Bazel profil aralıklarını listeleyin. | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_build_step` | Kaydedilmiş bir Bazel adımını ve bunun yayınlanan eylem sonucunu ve temizlenmiş günlüğünü inceleyin. | `account_handle`, `project_handle`, `invocation_id`, `step_id` |
| `list_bazel_remote_actions` | Tuist uzak yürütmenin bir çağrı için çalıştırdığı eylemleri mnemonik, hedef, eylem özeti, çıkış kodu, yürütme yolu ve faz zamanlamalarıyla listeleyin. İsteğe bağlı `sort_by` (`duration` veya `queued_at`), `failed` ve `mnemonic` filtreleri. | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_remote_action` | Bir uzak eylemin argv değerini, ortamını (gizli anahtar benzeri değerler maskelenmiş), platformunu, çalışma dizinini, çıktı yollarını, işçisini, çıkış kodunu, stdout ve stderr'in ilk 16 KiB'ini, stderr'de tanınan derleyici `errors` hatalarını, faz zamanlamalarını ve eylem özetini alın. | `account_handle`, `project_handle`, `invocation_id`, `action_id` |
| `get_bazel_remote_action_log` | Bir uzak eylemin stdout veya stderr çıktısından bayt ofsetine göre en fazla 64 KiB okuyun, varsayılan olarak akışın sonuna kadar. Uzun akışlar tamamen kopyalanır veya daha uzun olduklarında ilk 16 KiB'lerini ve son 16 MiB'lerini korur; `recorded` mevcut aralıkları listeler. | `account_handle`, `project_handle`, `invocation_id`, `action_id`, `stream` |
| `list_bazel_invocation_logs` | Bir Bazel çağrısı için yakalanan temizlenmiş günlükleri yürütme sırasına göre listeleyin: Bazel'in ilerleme çıktısının sınırlı kuyruk kısmı ve `test.log` yapıtları. İsteğe bağlı `stream` (`stdout` veya `stderr`), `source` (`progress` veya `test_log`), `target_label` ve `errors` filtreleri sonuçları daraltır. | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_invocation_log` | Bir Bazel çağrısı için yakalanan tek bir temizlenmiş günlük parçasını alın. | `account_handle`, `project_handle`, `invocation_id`, `invocation_log_id` |
| `list_bazel_cache_events` | Ham Bazel uzak önbellek gözlemlerini işlemi, uç noktası ve gözlem zamanıyla birlikte, isteğe bağlı olarak bir çağrı, sonuç veya işlemle daraltılmış şekilde listeleyin. | `account_handle`, `project_handle` |
| `get_bazel_cache_event` | Tek bir ham Bazel uzak önbellek gözlemini alın. | `account_handle`, `project_handle`, `cache_event_id` |

#### Uzak yürütme

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `get_remote_execution_activity` | Projenin çalışan Bazel çağrılarını ve şu anda çalışan ve sıraya alınmış uzak eylemlerini, her bir eylemin çağrısı, mnemoniği, hedefi, eylem özeti, makine boyutu ve bu duruma ne zaman girdiği bilgileriyle listeleyin. Yürütme ağ geçidinin önceden hazırladığı bir VM üzerinde çalıştırdığı eylemler tamamlanana kadar listelenmez. | `account_handle`, `project_handle` |
| `get_remote_execution_usage` | `[from, to)` aralığında projenin uzak yürütmelerini ve ölçülen yürütme süresini toplamda, makine boyutuna göre, dağıtım moduna göre ve saat, gün veya ay bazında alın. Dönem varsayılan olarak son 30 gündür ve en fazla 366 günü kapsar. | `account_handle`, `project_handle` |

`list_bazel_invocations` filtreleri tam eşleşmedir ve aynı saniyede biten çağrılar çağrı kimliğine göre sıralanır. Bir dal üzerindeki en son başarısız çağrıyı bulmak için `status: "failure"`, `git_branch` ve `page_size: 1` ile çağırın. REST uç noktası `GET /api/projects/{account_handle}/{project_handle}/bazel/invocations` aynı filtreleri kabul eder.

Dizinlenmiş profillerden güvenli bir şekilde ilişkili sunucu faz zamanlamalarına sahip yalnızca eylemleri döndürmek için `list_bazel_build_steps` üzerinde `remote_execution: true` ayarlayın. Liste ve ayrıntı yanıtları isteğe bağlı null olabilir `remote_queue_ms`, `remote_input_fetch_ms`, `remote_execution_ms` ve `remote_output_upload_ms` değerlerini sunar. Değerler, eylem içindeki yeniden denemeler dahil olmak üzere kaydedilen fazların toplamıdır; eksik veya null değerler sıfır değil, kullanılamaz anlamına gelir. Bunlar profil gözlemleridir, faturalandırılabilir kullanım veya yeni yürütme kanıtı değildir, çünkü önbelleğe alınmış sunucu sonuçları yürütme meta verilerini taşıyabilir. İstemci yüklemeleri hariç tutulur. Daha eski veya belirsiz profiller, uzak iş gerçekleşse bile eşleşen eylem döndürmeyebilir. Adım REST uç noktası aynı `remote_execution=true` filtresini kabul eder. Panonun Uzak yürütme sekmesi aynı sorguyu ve 90 günlük saklama süresini kullanır.

Test günlükleri, geldikleri test sonucunun `target_label` ve deneme `status` bilgisini taşır, bu nedenle `target_label: "//foo:bar_test"` yalnızca o hedefin test günlüklerini döndürür. `errors: true` başarısız denemelerin test günlüklerini ve Bazel raporlayıcısının `ERROR:`, `FAIL:` veya `TIMEOUT:` ile başladığı bir satır içeren stderr ilerleme parçalarını döndürür. İlerleme çıktısı hedeflere atfedilmez ve atfetme kaydedilmeden önce yazılan günlüklerin alanları boştur. Başarısız eylemler ve kendi çıktıları `list_bazel_build_steps` üzerinden hedef başına, test durumu başına başarısızlıklar ise test çalıştırması araçlarından elde edilebilir.

#### Cargo derlemeleri

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_cargo_builds` | Bir proje için Cargo derlemelerini en yeniden eskiye doğru listeleyin. `git_branch`, `status`, `is_ci` veya `command` ile filtreleyin. Cargo test yürütme sonuçları bu derleme listesi üzerinden değil, test araçları üzerinden kullanılabilir. | `account_handle`, `project_handle` |
| `get_cargo_build` | Derleme meta verilerini, toplam önbellek sayaçlarını ve tanılama bilgileriyle birlikte en fazla 500 kaydedilmiş derleyici işini alın. `compilations_truncated` atlanan işleri gösterir; tanılama yalnızca döndürülen işleri kapsar. | `account_handle`, `project_handle`, `build_id` |

Doğrulanmış görev kararlarını ve CAS işlemlerini almak için `get_cargo_build` üzerinde `include_cache_inspection: true` ayarlayın, sınır 4 MB'tır. Varsayılan olarak ve kayıtlar eksik veya geçersiz olduğunda `cache_inspection` null değerindedir. Kısmi yakalama `truncated` bayrağına saygı gösterin; aktarımlar her görev isabetinin yerel/uzak kökenini belirlemez. HTTP ayrıntı uç noktası aynı sorgu parametresini kabul eder.

#### Mix derlemeleri

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_mix_builds` | Bir proje için Mix (Elixir) derleme derlemelerini, özel meta veriler dahil olmak üzere en yeniden eskiye doğru listeleyin. `git_branch`, `status`, `is_ci` veya `mix_env` ile filtreleyin. | `account_handle`, `project_handle` |
| `get_mix_build` | Derleme meta verilerini, tanılama sayılarını ve bağımlılık önbellek özetini alın. | `account_handle`, `project_handle`, `build_id` |

#### Derleme izleri

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `get_build_trace` | Bir Xcode, Gradle, Bazel veya Mix derlemesinin zaman çizelgesi için [Perfetto](https://ui.perfetto.dev) içinde açabileceğiniz bir iz dosyası olarak indirme bağlantısı alın. | `account_handle`, `project_handle`, `build_id` |

`build_id` derleme çalıştırma kimliğidir (Bazel için çağrı kimliği) veya derlemenin pano URL'sidir. Döndürülen `trace_url` bir [Chrome Trace Event](https://docs.google.com/document/d/1CvAClvFfyA5R-PhYUmn5OOQtYMH4h6I0nSsKchNAySU) JSON dosyası sunar. Bağlantıya sahip olan herkes, başka kimlik bilgisi olmadan `expires_at` tarihine kadar, yani aramadan bir saat sonrasına kadar o derlemenin izini indirebilir. Ajanlar bunu `curl` ile indirebilir, Perfetto'da açmanız için size verebilir veya Perfetto'nun `trace_processor` ile sorgulayabilir. İz, paralellikle şeritlere paketlenmiş kaydedilmiş adımları, tüm derlemeyi kapsayan bir parçayı ve derleme makine metriklerini kaydettiğinde CPU ve bellek sayaçlarını içerir. Günlükler olmadan yukarıdaki adım araçlarıyla aynı veriyi tutar. Pano, her derlemenin Zaman Çizelgesi sekmesinden aynı dosyayı sunar.

#### Struo çalıştırmaları

<a id="once-runs"></a>

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_once_runs` | Bir proje için Struo çalıştırmalarını en yeniden eskiye doğru listeleyin. `kind` (`build`, `test` veya `generic`), `status`, `is_ci` veya `git_branch` ile filtreleyin. Tamamlanmamış çalıştırmaların durumu `in_progress` olur. | `account_handle`, `project_handle` |
| `get_once_run` | Eylem toplamları, önbellek özeti ve test çalıştırmaları için test toplamları ile bir çalıştırmayı alın. | `account_handle`, `project_handle`, `run_id` |

Cargo derleme, Mix derleme ve Struo çalıştırma kimlikleri bir proje içinde benzersizdir. Aynı okumalar HTTP API üzerinden `GET /api/projects/{account_handle}/{project_handle}/cargo/builds`, `.../mix/builds` ve `.../once/runs` adreslerinde mevcuttur, her biri tek bir kimlik için bir ayrıntı uç noktasına sahiptir.

#### Görevler, eylemler, modüller ve dosyalar

Bu proje kapsamındaki araçlar, çalıştırmalar boyunca kalıcı derleme kimliklerini inceler. `list_build_entities` ile başlayın, ardından döndürülen sabit `id` ile aynı `kind` türünü `get_build_entity` veya `list_build_entity_history` öğesine, `account_handle` ve `project_handle` ile birlikte iletin. Derleme veya çağrı tanımlayıcısı gerekmez.

| Araç | Açıklama | Gerekli parametreler |
| --- | --- | --- |
| `list_build_entities` | Bir projenin derlemeleri arasında görülen tek bir türdeki görevleri, modülleri, eylemleri veya dosyaları listeleyin. | `account_handle`, `project_handle`, `kind` |
| `get_build_entity` | Seçilen dönem için yerel kimliği ve analitiği ile tek bir derleme varlığını alın. | `account_handle`, `project_handle`, `kind`, `id` |
| `list_build_entity_history` | Bir derleme varlığının kaydedilmiş yürütmelerini, derlemelerini veya önbellek olaylarını en yeniden eskiye doğru listeleyin. | `account_handle`, `project_handle`, `kind`, `id` |

| `kind` | Araç zinciri | Geçmiş listeleri |
| --- | --- | --- |
| `bazel_actions` | Bazel eylemleri | BEP tarafından bildirilen eylem yürütmeleri |
| `gradle_tasks` | Gradle görevleri | Görev yürütmeleri |
| `xcode_modules` | Xcode modülleri | Derlemeler ve modül önbelleği olayları |
| `once_actions` | Struo eylemleri | Yürütmeler |
| `mix_files` | Mix ile derlenmiş dosyalar | Derlemeler |
| `mix_modules` | Mix ile derlenmiş modüller | Derlemeler |
| `cargo_crates` | Cargo kasaları | Kaydedilmiş rustc çağrıları |

Bu araçlar kademeli olarak yayımlanmaktadır ve yalnızca etkinleştirildiği projeler için veri döndürür; diğer projeler için boş bir sonuç yerine hata döndürür. Bir tür yalnızca ilgili derleme araç zincirini kullanan projeler için kullanılabilir. Araçlar sınırlı `start_at`/`end_at` filtrelerini, `environment` (`any`, `ci` veya `local`) ve tam eşleşen bir `branch` kabul eder. `list_build_entities` `q` parametresini kabul eder; `list_build_entity_history` şeffaf olmayan `after`/`before` imleçlerini destekler. Bilinmeyen zamanlama veya önbellek gözlemleri sıfır veya isabetsizlik olarak değil, mevcut değil olarak kalır. Geçmiş, mevcut çalıştırma araçlarını kullanarak detaylı inceleme için kaydedilen üst öğeyi ve yerel yürütmeyi referans alır.

`get_build_entity` metrikleri, kaydedilmiş zamanlamaya sahip gözlem sayısını içeren `duration_samples` değerini içerir: Gerçek sıfır süreler sayılır, eksik zamanlama sayılmaz. Bu sayı, gözlem sayısından daha düşük olabilir; mevcut olmayan süre istatistikleri null olarak kalır.

Xcode modül süreleri, derleme günlüklerindeki ölçülen hedef derlemelerden gelir. Modül önbelleği çözümlemeleri ve derleme işi olmayan hedefler süre örneklerine katkıda bulunmaz. Derleme gözlemleri Xcode derlemesini referans alır; önbellek olayları oluşturma veya önbellek komutunu referans alır.

Bazel eylemleri, hedef etiketi, anımsatıcı ve yapılandırılmış birincil çıktı ile tanımlanır; girişe bağlı önbellek özetlerine güvenmeden ayrı eylemleri ve yapılandırmaları distinct tutar. Geçmiş, BEP tarafından bildirilen yürütmeleri kaydeder, önbellek aramalarını veya iz profili aşamalarını değil. Tam yürütme kapsamı `--build_event_publish_all_actions` gerektirir; yapıt teslimi en iyi çabayla yapılır, bu nedenle eksik gözlemler hiçbir işin çalışmadığına dair kanıt değildir. Kararlı kimliği veya yürütme başlangıcı olmayan eski Kura yükleri kabul edilir ancak indekslenmez. Eksik bitiş zamanı ölçümleri mevcut değil olarak kalır ve gerçek sıfır süreler sayılır.

Mix modül süreleri, bağımsız olarak ölçülen modül işini değil, kapsayan dosyanın derlemesini ölçer. Struo eylemleri, istemci hedef eşlemelerini bildirdiğinde bildirilen hedef/yetenek/dizin yuvalarını kullanır; yalnızca tanılama etiketleri kararlı kimlikler değildir. Mevcut istemciler ve çalıştırma düzeyi araçları değişmeden desteklenmeye devam eder.

Cargo kasaları, tam olarak kaydedilen kasa kökü, adı ve türüne göre gruplanır. Checkout yolu değişiklikleri geçmişleri bölebilir ve derleme profilleri, özellikler ve hedef üçlüleri ayırt edilmez. Geçmiş, dosya başına işi veya önbellek isabetlerini değil, rustc çağrılarını ölçer; eksik işler kaldırmaları veya tam bir çalışma alanı envanterini tesis etmez.

Analitik okumaları sınırlı bellek ve yürütme süresine sahiptir. Bir sorgu bu sınırları aşarsa, araç boş bir sonuç uydurmak yerine hata döndürür.

Yeni gözlemler dağıtımdan sonra indekslenir; bu özellik mevcut çalıştırma telemetrisini geriye dönük doldurmaz. Kimlik meta verileri, <.localized_link href="/guides/server/data-retention">veri saklama politikası</.localized_link> kapsamında bireysel gözlemlerden daha uzun süre yaşar.

#### Testler

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_test_runs` | Bir proje için test çalıştırmalarını, her biri kendi `selective_testing_strategy` ile birlikte listeleyin. `selective_testing` ile filtreleyin (`coverage`, kapsama tabanlı seçimin geri dönüşlerini içerir, veya `module_hash`). `query` alanları `git_branch`, `scheme`, `status` ve `selective_testing` şeklindedir: `field:"value"` tam eşleşir, `field~"value"` büyük/küçük harfe duyarlı olmayan bir alt dizeyle eşleşir (`selective_testing` üzerinde değil) ve baştaki `-` operatörlerden herhangi birini negatifleştirir. Örneğin, `-git_branch~"gh-readonly-queue"` birleştirme kuyruğu dallarını hariç tutar. Boşlukla ayrılmış sorgu filtreleri ve açık argümanlar AND mantığıyla birleşir. | `account_handle`, `project_handle` |
| `get_test_run` | Bir test çalıştırması için kendi kod kapsamı (`coverage`: herhangi bir ölçüm yapılıp yapılmadığı, satırları ve figürü, kısmi olup olmadığı veya kirli bir checkout'tan çalışıp çalışmadığı), seçici test özeti (`selective_testing`: strateji, temel commit ve istenen, seçilen, atlanan ve tahmini test sayıları, test seçimi etkinliğinin hesaplandığı değerler) ve onu çalıştıran komutun sonuç paketi (`.xcresult`) ve oturum arşivi (CLI günlükleri) için geçici indirme URL'leri dahil olmak üzere ayrıntılı metrikleri alın veya çalıştırmaya bağlı bir komut yoksa `null` döner. | `test_run_id` |
| `list_test_module_runs` | Belirli bir test çalıştırması için test modülü çalıştırmalarını listeleyin. | `test_run_id` |
| `list_test_suite_runs` | Belirli bir test çalıştırması için test paketi çalıştırmalarını, isteğe bağlı olarak modüle göre filtrelenmiş şekilde listeleyin. | `test_run_id` |
| `list_test_cases` | Bir proje için test senaryolarını listeleyin (`flaky` gibi filtreleri destekler). | `account_handle`, `project_handle` |
| `get_test_case` | Güvenilirlik oranı, kararsızlık oranı ve çalıştırma sayıları dahil olmak üzere bir test senaryosu için ayrıntılı metrikleri alın. | `test_case_id` veya `identifier` + `account_handle` + `project_handle` |
| `list_test_case_runs` | Test senaryosu çalıştırmalarını, isteğe bağlı olarak test senaryosuna veya test çalıştırmasına göre filtrelenmiş şekilde listeleyin. | `account_handle`, `project_handle` |
| `get_test_case_run` | Belirli bir test senaryosu çalıştırması için hata ayrıntılarını ve tekrarları alın ve çalıştırmanın kapsama tabanlı seçimi testi tuttuğunda nedenini (`selective_testing`: karar, neden, eşleşen değişen dosya ve parça) öğrenin. | `test_case_run_id` |
| `list_test_case_run_attachments` | Bir test senaryosu çalıştırması için ekleri listeleyin. Her ek, geçici bir indirme URL'si içerir. | `test_case_run_id` |
| `list_test_case_events` | Bir test senaryosu için susturma veya atlama gibi durum değişikliklerini listeleyin. | `test_case_id` |
| `update_test_case` | Bir test senaryosunun durumunu veya kararsız sınıflandırmasını güncelleyin. Bir değişiklik, harici hizmetler dahil olmak üzere yapılandırılmış webhook uç noktalarına bir olay gönderebilir. | `test_case_id` veya `identifier` + `account_handle` + `project_handle` |
| `list_xcode_test_targets` | Bir test çalıştırması için seçici test hedef sonuçlarını listeleyin. | `test_run_id` |
| `list_selective_testing_tests` | Bir test çalıştırmasının kapsama tabanlı seçiminin karar verdiği, seçtiği ve atladığı testleri; her kararın nedenini, onu seçen değişen dosyayı, parçasını ve çalıştırmadaki sonucunu listeleyin. `decision`, `reason` veya `search` ile filtreleyin. | `test_run_id` |
| `list_selective_testing_changed_files` | Bir test çalıştırmasının kapsama tabanlı seçim temelinden bu yana değişen dosyaları; her birinin kaç testi seçtiğini ve değişimi seçimin geri dönüşüne neden olan izlenen bir dosya olup olmadığını listeleyin. | `test_run_id` |
| `get_coverage` | Bir projenin kod kapsamını hedefleriyle birlikte, bir commit'te veya bir dalın en son tamamlanan commit'inde alın. `git_commit_sha` veya `branch` olmadan varsayılan dalı okur. | `account_handle`, `project_handle` |
| `list_coverage_files` | Bir commit'in kod kapsamının ölçtüğü dosyaları, satır kapsamlarıyla birlikte, bir commit'te veya bir dalın en son tamamlanan commit'inde listeleyin. `search`, sıralama ve sayfalama desteklenir. | `account_handle`, `project_handle` |
| `get_coverage_file` | Bir dosyanın kod kapsamını ve fonksiyonlarını, bir commit'te veya bir dalın en son tamamlanan commit'inde alın. Her satırın yürütme sayısını almak için `include_lines` ayarlayın. | `account_handle`, `project_handle`, `path` |
| `list_coverage_branches` | Kod kapsamı bulunan dalları, varsayılan dal ilk sırada olacak şekilde listeleyin. | `account_handle`, `project_handle` |
| `list_coverage_commits` | Bir dalın commit'lerini; kapsama durumları (`complete`, `incomplete`, `in_progress`, `not_measured`), figürü ve önceki tamamlanan commit'ten farkıyla birlikte, en yeniden eskiye doğru listeleyin. İmleçlerle sayfalama yapılır. | `account_handle`, `project_handle` |
| `list_coverage_runs` | Bir commit'in veya dalın arkasındaki kod kapsamına sahip test çalıştırmalarını; her biri `full`, `partial` veya `discarded` (kirli checkout) olarak işaretlenmiş şekilde listeleyin. İmleçlerle sayfalama yapılır. | `account_handle`, `project_handle` |
| `list_coverage_targets` | Bir commit'in hedef başına kapsamını, ardından çalıştırmalarının kapsam sayaçları olmadan ikili önbellekten aldığı hedefleri (`measured: false`) listeleyin. `search`, sıralama ve sayfalama desteklenir. | `account_handle`, `project_handle` |

Kod kapsamı araçları, kod kapsamı etkinleştirilmiş hesaplara sunulur.

#### Paketler

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_bundles` | Bir proje için paketleri (uygulama ikililerini) listeleyin. İsteğe bağlı olarak `git_branch` ve `tags` ile filtreleyin (tüm etiketler tam eşleşmelidir). | `account_handle`, `project_handle` |
| `get_bundle` | Özel etiketler dahil olmak üzere belirli bir paket hakkında ayrıntılı bilgi alın. | `bundle_id` |
| `get_bundle_artifact_tree` | Bir paket için tam yapıt ağacını, yola göre sıralanmış düz bir liste olarak alın. | `bundle_id` |

`list_bundles`, derleme çeşitlerini veya ortamları ayırt etmek için `tags: ["paid", "production"]` kabul eder. Etiketler, büyük/küçük harfe duyarlı, harf, rakam, tire veya alt çizgi içeren etiketlerdir; en fazla 10 etiket ve etiket başına 50 karakter bulunur. Liste ve ayrıntı sonuçları `custom_metadata.tags` içerir. Sayfalama sayıları ve dal filtreleri etiketli sonuçlara uygulanır; `tags` atlandığında filtrelensiz davranış korunur. Geçersiz etiket filtreleri sorguyu genişletmek yerine bir hata döndürür.

#### Nesiller

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_generations` | Bir proje için nesil çalıştırmalarını listeleyin. | `account_handle`, `project_handle` |
| `get_generation` | Belirli bir nesil çalıştırması hakkında ayrıntılı bilgi alın. | `generation_id` |

#### Önbellek çalıştırmaları

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_cache_runs` | Bir proje için önbellek çalıştırmalarını listeleyin. | `account_handle`, `project_handle` |
| `get_cache_run` | Oturum arşivi (CLI günlükleri) için geçici bir indirme URL'si dahil olmak üzere belirli bir önbellek çalıştırması hakkında ayrıntılı bilgi alın. | `cache_run_id` |
| `list_xcode_module_cache_targets` | Bir nesil veya önbellek çalıştırması için modül önbelleği hedeflerini; hedef başına önbellek isabeti/isabetsizliği durumunu ve ek hashing girdileri dahil tanısal bileşen hash'lerini göstererek listeleyin. | `run_id` |

#### Önizlemeler

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_previews` | Bir proje için paylaşılabilir uygulama önizlemelerini listeleyin. | `account_handle`, `project_handle` |
| `get_preview` | Bir önizlemeyi ve derlemeleri için geçici indirme URL'lerini alın. | `preview_id` |
| `get_latest_preview` | Çalışan bir uygulama ikilisi için en son önizlemeyi bulun. | `account_handle`, `project_handle`, `binary_id`, `build_version` |

#### Otomasyonlar

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_automation_alerts` | Bir proje için otomasyon uyarılarını listeleyin. | `account_handle`, `project_handle` |
| `get_automation_alert` | Bir otomasyon uyarısı alın. | `alert_id` |
| `list_automation_alert_revisions` | Bir otomasyon uyarısının revizyon geçmişini listeleyin. Eylem kimlik bilgileri gizlenmiştir. | `alert_id` |
| `list_project_notification_alerts` | Proje bildirim uyarı kurallarını listeleyin. Gösterge paneli ayarları sayfasıyla aynı yönetici iznini gerektirir. Webhook adresleri gizlenmiştir. | `account_handle`, `project_handle` |

### Olaylar

Durumsuz `2026-07-28` Model Context Protocol yaşam döngüsünü kullanan istemciler, olayları ve yük şemalarını keşfetmek için `events/list` çağrısını yapabilir:

| Olay | Ne zaman gönderilir | Abonelik filtresi |
|-------|-----------------|---------------------|
| `test_case.marked_flaky` | Bir test senaryosu kararsız olmayan durumdan kararsız duruma geçer. | `account_handle`, `project_handle` |
| `build.failed` | Yerel veya sürekli entegrasyon Xcode, Gradle ya da Bazel derlemesi bir başarısızlıkla sonlanır. | `account_handle`, `project_handle` |
| `test_run.failed` | Yerel veya sürekli entegrasyon test çalıştırması bir başarısızlıkla sonlanır; birleştirilmiş parçalı çalıştırma veya terk edilmiş çalıştırma dahildir. | `account_handle`, `project_handle` |
| `ci_job.failed` | Bir Tuist runner işi bir başarısızlıkla tamamlanır. | `account_handle` |
| `pulse_symptom.opened` | Pulse, board veya page katmanında bir semptomu açar veya yeniden açar. Yalnızca audit katmanında günlüğe kaydedilen semptomlar ve açık bir semptomdaki sonraki değişiklikler gönderilmez. | `account_handle` |

Abone olmak için istemci, olay adıyla, yukarıda `arguments` içinde listelenen tanıtıcılarla ve bir `https://` geri çağırma URL’si ile bir `whsec_` imzalama sırrı içeren bir `webhook` teslimatıyla `events/subscribe` çağrısını yapar. Proje olayları hesap üyeliği ve ilgili test veya derleme verilerine okuma erişimi gerektirir; runner işi olayları hesap üyeliği ve runner okuma erişimi gerektirir; Pulse semptom olayları organizasyon üyeliği ve hesap için Pulse erişimi gerektirir ve bir hesap jetonu o hesaba ait olmalıdır. Talep edilen [`auth.md`](https://workos.com/auth-md) erişim jetonları, talep edilen hesap jetonları ve tarayıcı yetkilendirme izinleri abonelik oluşturabilir; ilişkili kimlik bilgisi artık etkin olmadığında teslimat durur. Her kullanıcı en fazla 25 etkin abonelik tutabilir. Tuist, aboneliği kaydetmeden önce geri çağırmaya bir doğrulama sorgusu gönderir. Geri çağırma, aynı `challenge` değerini içeren bir nesne döndürmelidir. Abonelik varsayılan olarak yedi gün sürer, tekrar abone olunarak yenilenebilir ve kullanıcının erişimi veya kimlik bilgisi kaldırıldığında teslimat durur. İsteğe bağlı `ttlMs` bir saat ile 30 gün arasında sınırlıdır. Tuist zaman aşımına uğramış bir geri çağırmayı yeniden dener ve beş dakikayı kapsayan en az üç ardışık zaman aşımından sonra aboneliği iptal eder; geri çağırmayı geri yükledikten sonra tekrar abone olun.

Bir olay gerçekleştiğinde, Tuist kaynak tanımlayıcısını ve gösterge paneli URL’sini geri çağırmaya gönderir. Derleme ve test çalıştırması hataları ayrıca `is_ci` ve `git_branch` içerir, böylece istemciler yerel hataları yok sayabilir veya dala göre filtreleyebilir. Derleme olayları `build_system` içerir; runner işi olayları hem `workflow_job_id` hem de `workflow_run_id` içerir; Pulse semptom olayları `symptom_id`, `tier` (`board` veya `page`) ve etkilenen varlığı `untrusted` altında, her değeri en fazla 200 karakter olacak şekilde `{"type": "untrusted_json", "value": {"service", "kind", "key"}}` olarak içerir: varlık üretim telemetrisinden gelir, bu nedenle onu veri olarak ele alın, talimat olarak asla kullanmayın. URL’leri semptomun sayfasını açar. İstek, istemcinin kaynağını doğrulayabilmesi için bir abonelik tanımlayıcısı ve [Standard Webhooks](https://www.standardwebhooks.com/) imza başlıkları içerir. Tuist başarısız teslimatları yeniden dener, bu nedenle istemciler yinelenenleri atmak için kararlı `eventId` kullanmalıdır. Yük, test adlarını, günlükleri ve hata mesajlarını içermez; istemci bu ayrıntıları yukarıdaki araçlar aracılığıyla alabilir ve bir ekibi bilgilendirmeye veya hata ayıklamaya başlamaya karar verebilir. İstemciler teslimatı `events/unsubscribe` ile durdurabilir.

### İstemler

| İstem | Açıklama |
|--------|-------------|
| `fix_flaky_test` | Başarısızlık kalıplarını analiz ederek, kök nedeni belirleyerek ve hedefe yönelik bir düzeltme uygulayarak kararsız bir testi düzeltmenize rehberlik eder. |
| `compare_builds` | Performans gerilemelerini, önbellek değişikliklerini ve derleme sorunlarını belirlemek için derlemeleri karşılaştırmanıza rehberlik eder. Xcode, Gradle, Bazel ve Cargo projeleri için yerel araçları kullanır. Cargo karşılaştırmaları kısmi derleyici kapsamını korur ve tahmini derleyici işini geçen süreden tasarruftan ayırır. |
| `compare_test_runs` | Gerilemeleri, yeni hataları ve kararsız testleri belirlemek için iki test çalıştırmasını karşılaştırmanıza rehberlik eder. |
| `compare_bundles` | Yapıt ağacı genelinde boyut değişikliklerini belirlemek için iki paketi karşılaştırmanıza rehberlik eder. |
| `compare_test_case` | Bir test senaryosunun davranışını iki dal veya zaman dilimi arasında karşılaştırmanıza rehberlik eder. |
| `compare_generations` | Performans gerilemelerini ve modül önbelleği değişikliklerini belirlemek için iki nesil çalıştırmasını karşılaştırmanıza rehberlik eder. |
| `compare_cache_runs` | Önbellek etkinliği değişikliklerini ve hedef düzeyindeki gerilemeleri belirlemek için iki önbellek çalıştırmasını karşılaştırmanıza rehberlik eder. |
| `integrate_gradle_project` | Tuist’i mevcut bir Gradle projesine entegre etmenize rehberlik eder. Ayrı araç ve Gradle kimlik doğrulaması, hesap keşfi, proje oluşturma, uzak önbellek politikası, derleme içgörileri ve geri okuma doğrulamasını içerir. |
| `integrate_bazel_project` | Bir Bazel projesi oluşturmanıza veya seçmenize, komut satırını kimlik doğrulamanıza, uzak önbelleği ve derleme içgörülerini yapılandırmanıza ve entegrasyonu Tuist derleme verileri aracılığıyla doğrulamanıza rehberlik eder. |
| `integrate_xcode_project` | Tuist’i mevcut bir Xcode projesine entegre etmenize rehberlik eder. Xcode önbelleği, derleme içgörileri, test içgörileri ve test parçalama desteği sunar. |
| `ask_tuist` | Bağlam için genel materyali ve mevcut davranış için gerçek kaynak olarak odaklanmış uygulama ve test kanıtını kullanarak bir Tuist sorusunu yanıtlar. Bir `question` gerektirir ve revizyon sabitli kanıtlara atıfta bulunur. |

Proje verisi istemleri, incelemeyi belirli bir projeye daraltmak için `account_handle` ve `project_handle` kabul eder. Karşılaştırma istemleri ayrıca karşılaştırılacak iki öğeyi (ID, gösterge paneli URL’si veya dal adına göre) belirtmek için `base` ve `head` bağımsız değişkenlerini kabul eder. `ask_tuist`, proje parametreleri yerine bir `question` kabul eder. `integrate_gradle_project` ayrıca uygulanacak Gradle entegrasyonlarının virgülle ayrılmış bir listesi olan `features` kabul eder: `remote_cache`, `build_insights`, `test_insights`, `flaky_tests` ve `test_sharding`. `integrate_bazel_project`, kendi kendine barındırılan veya yerel kurulumlar için isteğe bağlı bir `server_url` kabul eder. `integrate_xcode_project`, `xcode_cache`, `build_insights`, `test_insights` ve `test_sharding` ile `features` kabul eder.

#### Gradle entegrasyonu istemi özellikleri

`integrate_gradle_project` istemi ve `get_gradle_integration_guide` aracı, kurulum iş akışının tamamını belgeler. Araç ayrıca sunucunun başlatma talimatları tarafından referans verilir, bu da istemleri numaralandırmayan ajanlar tarafından keşfedilmesini sağlar.

| Özellik | Ajanın neyi yapılandırdığı |
|---------|---------------------------|
| `remote_cache` | Gradle'ın derleme önbelleğini etkinleştirir, Tuist uzak önbellek yükleme politikasını yapılandırır ve yalnızca yerel salt okunur kullanıma sahip sürekli entegrasyon çalıştırıcılarından yüklemeleri önerir. |
| `build_insights` | Tuist Gradle eklentisini uygular ve gerektiğinde derleme analitiği yükleme davranışını yapılandırır. |
| `test_insights` | Gradle `Test` görev sonuçlarının otomatik olarak yüklenmesi için Tuist Gradle eklentisini uygular. |
| `flaky_tests` | Kararsız test tespiti kurulumuna, isteğe bağlı Gradle Test Retry eklentisi kullanımına ve test karantina yapılandırmasına rehberlik eder. |
| `test_sharding` | `tuistPrepareTestShards`, parça matrisi oluşturma ve `TUIST_SHARD_INDEX` tabanlı test yürütme için sürekli entegrasyon iş akışını ekler. |

`features` atlandığında, istem ajandan kullanıcının hangi entegrasyonları istediğini netleştirmesini veya Gradle projesini düzenlemeden önce istekten en küçük yararlı seti çıkarmasını ister.

#### Xcode entegrasyonu istemi özellikleri

`integrate_xcode_project` istemi, Tuist'in desteklediği her Xcode entegrasyonunu belgeler:

| Özellik | Ajanın neyi yapılandırdığı |
|---------|---------------------------|
| `xcode_cache` | `tuist setup cache`, oluşturulan proje önbellek ayarlarını, manuel Xcode önbellek derleme ayarlarını ve yalnızca sürekli entegrasyon çalıştırıcılarıyla sınırlı bir yükleme politikasını yapılandırır. |
| `build_insights` | `tuist inspect build`, `tuist xcodebuild`, `-resultBundlePath` ve isteğe bağlı makine metriklerini `tuist setup insights` aracılığıyla yapılandırır. |
| `test_insights` | `tuist inspect test`, şema test son eylemlerini ve sürekli entegrasyon test çalıştırmaları için sonuç paketi oluşturmayı yapılandırır. |
| `test_sharding` | `TUIST_SHARD_INDEX` ile Xcode veya oluşturulan proje parça planlama ve parça yürütme iş akışını ekler. |

`features` atlandığında, istem ajandan kullanıcının hangi entegrasyonları istediğini netleştirmesini veya Xcode projesini düzenlemeden önce istekten en küçük yararlı seti çıkarmasını ister.
