---
{
  "title": "Model Context Protocol (MCP)",
  "titleTemplate": ":title · Ajan tabanlı kodlama · Özellikler · Kılavuzlar · Tuist",
  "description": "AI ajanlarına Tuist'in MCP uç noktası üzerinden test içgörülerine ve daha fazlasına erişim sağlayın."
}
---
# Model Context Protocol

[Model Context Protocol (MCP)](https://modelcontextprotocol.io/docs/getting-started/intro), yapay zekâ ajanlarının harici hizmetler ve veri kaynaklarıyla etkileşime girmesini sağlayan açık bir standarttır. [Claude](https://claude.ai/), [Claude Code](https://docs.anthropic.com/en/docs/claude-code), [Codex](https://developers.openai.com/codex/) gibi uygulamaların ve [Zed](https://zed.dev), [Cursor](https://www.cursor.com) veya [Visual Studio Code](https://code.visualstudio.com) gibi editörlerin Tuist ile birlikte çalışabilmesini sağlar.

Tuist, sunucu tarafında bir Model Context Protocol uç noktasını `https://tuist.dev/mcp` adresinde barındırır. İstemcinizi bu uç noktaya bağlayarak ajanlar test içgörülerine, kararsız test analizlerine ve daha fazlasına dahil olmak üzere Tuist proje verilerinize erişebilir. Çoğu araç, kimliği doğrulanmış kullanıcının panoda zaten görebildiği Tuist verilerini okur. Her araç, salt okunur olup olmadığını, zor geri alınabilir bir değişikliğe neden olup olamayacağını (`destructiveHint`) ve Tuist dışına erişip erişemeyeceğini (`openWorldHint`) belirten açıklamalar sunar. Durumu değiştiren araçlar, her biri hesabın veya projedeki kullanıcı izinleriyle sınırlıdır:

- **Kuruluşlar ve üyeler**: `create_organization`, `add_organization_member` (mevcut bir kullanıcı ekler veya bir üyenin rolünü değiştirir), `invite_organization_member` (herhangi bir adrese davet e-postası gönderir) ve `cancel_organization_invitation`.
- **Projeler**: `create_project`, `start_project_logo_upload` ve `complete_project_logo_upload` (logoyu değiştirir), `connect_project_repository` ve `disconnect_project_repository` (GitHub depo bağlantıları).
- **Testler**: `update_test_case` (bir test senaryosunu sessize alır, atlar, yeniden etkinleştirir veya kararsız olarak işaretler; değişiklik hesabın webhook uç noktalarına ulaşabilir).
- **Bildirim kuralları**: `create_notification_rule`, `update_notification_rule` ve `delete_notification_rule`.
- **Sürekli entegrasyon çalıştırıcıları**: `create_runner_profile`, `update_runner_profile` (hangi işlerin önbellek birimlerini kaydettiğini daraltmak bekleyen kayıtları siler), `delete_runner_profile` ve `delete_runner_volume` (birimin kaydedilen içeriğini siler).
- **Sandbox’lar**: `create_sandbox`, `pause_sandbox`, `resume_sandbox`, `archive_sandbox` ve `delete_sandbox` (disklerini siler).
- **Geri bildirim**: `report_feedback` (bir araç veya istem hakkında Tuist ekibine rapor gönderir; yalnızca tuist.dev üzerinde).
- **Ajan entegrasyonları**: `connect_amp_workspace` (çalışma alanının orb’larına hesaba CI erişimi verir), `disconnect_amp_workspace` ve `connect_claude_environment` (Claude Managed Agents ortamının Tuist sandbox’larında oturumlar çalıştırmasına olanak tanır).

`add_organization_member`, `cancel_organization_invitation`, `complete_project_logo_upload`, `disconnect_project_repository`, `update_test_case`, `update_notification_rule`, `delete_notification_rule`, `update_runner_profile`, `delete_runner_profile`, `delete_runner_volume`, `delete_sandbox` ve `disconnect_amp_workspace`, mevcut durumu değiştirdiği veya kaldırdığı için `destructiveHint: true` bildirir. `invite_organization_member`, `update_test_case`, `connect_claude_environment` ve `report_feedback`, e-posta gönderdiği, harici webhook uç noktalarını bilgilendirdiği, Anthropic’i aradığı veya Tuist ekibine rapor gönderdiği için `openWorldHint: true` bildirir.

Kişisel Claude ve ChatGPT abonelikleri yalnızca panonun AI ayarlarında bağlanır, bu nedenle abonelik jetonları ve oturum açma işlemleri asla bir Model Context Protocol istemcisinden geçmez. Hesap kurulum araçları kullanıcı kimlik doğrulaması gerektirir. Proje jetonları veya normal hesap jetonları tarafından kullanılamazlar. Bir kullanıcı tarayıcıda bir istemciye yetki verdiğinde veya bir `auth.md` kaydını talep ettiğinde, Tuist bu kimlik bilgisini yalnızca Model Context Protocol uç noktasında kullanıcıyla ilişkilendirir, böylece kurulum araçları istenen iş akışını tamamlayabilir.

Tuist, [2026-07-28 protokolünü](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http) uygular. İstekler durumsuzdur: istemciler her istekle birlikte protokol meta verilerini gönderir ve araçları başlatma olmadan doğrudan çağırabilir. `server/discover`, sunucunun kimliğini, yeteneklerini, desteklenen sürümleri ve talimatlarını döndürür. Oturum tanımlayıcıları veya bağımsız olay akışları yoktur. 2025-06-18 veya 2025-03-26 başlatma akışını kullanan istemciler desteklenmeye devam eder; bunlar da sunucu oturumları olmadan çalışır.

## Model Context Protocol ile beceriler

Model Context Protocol araçları ve <.localized_link href="/guides/features/agentic-coding/skills">beceriler</.localized_link> yaptıkları işlerde örtüşebilir. İkisi arasındaki mevcut örtüşme göz önüne alındığında, her iş akışı için tek bir yaklaşım seçin ve aynı akışta ikisini karıştırmak yerine tutarlı bir şekilde kullanın.

Eklenti yüklemeyi destekleyen istemciler için, ikisini birlikte yüklemek amacıyla <.localized_link href="/guides/features/agentic-coding/plugins">Tuist eklentilerini</.localized_link> kullanın.

## Yapılandırma

İstemcinize uzak bir Model Context Protocol sunucusu olarak `https://tuist.dev/mcp` ekleyin. Sunucunun başlatma talimatları ve genel sunucu kartı, ajanlardan harici kimlik doğrulama belgelerini getirmelerini veya takip etmelerini istemeden, dinamik istemci kaydı ile OAuth 2.0’ı ve standart tarayıcı yetkilendirme akışını satır içinde açıklar. Bu sunucu çapındaki talimatlar iş akışı rehberliğini genel tutar: araç kimlik doğrulaması yerel komut satırı araçlarını veya derleme sistemi entegrasyonlarını kimlik doğrulamaz ve ajanlar istenen değişiklikleri ilgili Tuist araçları aracılığıyla doğrulamalıdır. Derleme sistemine özel kurulum ve kimlik doğrulama kontrolleri entegrasyon kılavuzlarında ve istemlerde belgelenmiştir. Tuist, hem [Open Authorization](https://oauth.net/2/) keşif meta verilerini hem de güncel [auth.md protokolünü](https://workos.com/auth-md) `https://tuist.dev/auth.md` adresinde ayrı ayrı duyurmaya devam eder.

Kuruluşlarınızdan biri tek oturum açmayı (SSO) zorunlu kılıyorsa, tarayıcıda bir istemciye yetki vermek o kuruluş üzerinden oturum açmış bir oturum gerektirir ve Tuist gerektiğinde sizi önce sağlayıcıya yönlendirir. Bkz. <.localized_link href="/guides/integrations/authentication/sso#choose-an-enrollment-policy">tek oturum açma</.localized_link>.

Uç nokta, eski oturum tabanlı yaşam döngüsünün yanı sıra, `server/discover` dahil olmak üzere durumsuz `2026-07-28` Model Context Protocol istek yaşam döngüsünü kabul eder. Mevcut istemciler mevcut bağlantı yöntemlerini kullanmaya devam edebilir.

Model Context Protocol olaylarını destekleyen istemciler proje olaylarına abone olabilir. Mevcut olay ve teslimat gereksinimleri için bkz. [Olaylar](#events).

Zaten uzak tarayıcı kimlik doğrulamasını destekleyen istemciler tarayıcıda kimlik doğrulamaya devam edebilir. `auth.md` destekleyen istemciler ve ajanlar anonim olarak kayıt olabilir, güvenilir bir sağlayıcı kimlik iddiası sunabilir veya hizmetle kimliği doğrulanmış bir e-posta talebi başlatabilir. Kayıt, Tuist tarafından imzalanmış bir kimlik iddiası döndürür; ajan bu iddiayı standart jeton uç noktasında bir saatlik erişim jetonu ile takas eder. Tuist genel imzalama anahtarını yayımlar ve standart jeton iptalini ile sağlayıcı güvenlik olayı teslimatını destekler.

Kimliği doğrulanmamış bir ajan, Model Context Protocol uç noktası tarafından döndürülen `WWW-Authenticate` başlığını okumalı, korunan kaynak meta verilerini getirmeli, yetkilendirme sunucusu meta verilerini getirmeli ve `agent_auth.skill` URL'sini izlemelidir. Tuist ayrıca yetkisiz yanıt gövdesinde aynı yerel `auth_md` URL'sini döndürür; böylece dil modeli tabanlı istemciler, yerel bir istemci entegrasyonuna güvenmeden akışı keşfedebilir. Dağıtım yerel belgesi, uç nokta adları, istek gövdeleri, talep yoklaması ve iddia değişimi için doğruluk kaynağıdır.

Bir ajan e-posta talebini başlatmadan önce, kullanıcının Tuist hesabına ait e-posta adresini onaylamasını istemelidir. Bu adresi bir sağlayıcı profilinden, Git yapılandırmasından, ortam değişkeninden veya oturum meta verilerinden çıkarmamalıdır.

Uç nokta `mcp` kapsam grubunu kullanır. Anonim bir ön-talep kimlik bilgisi yetenekleri keşfedebilir ve genel entegrasyon rehberlerini okuyabilir, ancak oturum açmış bir kullanıcı olarak değerlendirilmez. Tarayıcı yetkilendirmesi veya talepten sonra, kimlik bilgisi kullanıcı kapsamlı hale gelir ve her araç, kontrol panelindekiyle aynı yetkilendirme kontrollerini uygular. Ayrıntılar için bkz. <.localized_link href="/guides/server/authentication#scope-groups">kapsam grupları belgeleri</.localized_link>.

Araçlar, kimliği doğrulanmış kullanıcının zaten okuma erişimine sahip olduğu projelere çözülür. Xcode ve Gradle derleme araçları bir derleme UUID'sini veya kontrol paneli URL'sini kabul eder. UUID tam olarak bir projeyi tanımlamalıdır; birden fazla projede görünürse, araç başka bir projenin raporunu seçmek yerine bulunamadı hatası döndürür. Proje kapsamlı kontrol paneli ve API okumaları kullanılabilir durumda kalır. Bildirilen aktör tanımlayıcıları doğrulanmamış etiketlerdir; kimlik bilgileri veya ek erişim hakları değildir.

Derleme listesi ve ayrıntı araçları isteğe bağlı `tuist_version` meta verilerini sunar: Xcode ve Cargo için raporlayan Tuist CLI, Gradle için Tuist Gradle eklentisi ve Mix için `tuist_ex` kütüphanesi. Xcode ayrıca, yükleyen CLI'dan farklı olabilen bağlantılı proje oluşturma olayından `tuist_generation_version` değerini sunar. Eksik gözlemler null'dur; sunucudan veya başka bir rapordan çıkarılmaz. Bazel mevcut `bazel_version` değerini kullanır; Once çalıştırma ayrıntıları `once_version` değerini sunar. Bu alanlar bildirilen sürümleri tanımlar, doğrulanmış kimliği veya ağ sözleşmesi sürümlerini değil. REST derleme uç noktaları aynı meta verileri sunar. Mevcut entegrasyon ve kararsız test becerileri sürüm alanlarına bağlı değildir ve iş akışı değişikliği gerektirmez.

Bir müşterinin hesabını inceleyen Tuist operatörleri bunu, her çağrıyı kaydeden Tuist'in dahili operasyon araçları aracılığıyla yapar; bu uç noktaya doğrudan bağlantı, kullanıcının kendi üyelikleri dışında hiçbir erişim sağlamaz.

### Pulse

Pulse, hesabın operasyonel metrikleri, günlükleri, izleri ve hataları için salt okunur araçlar sunar; tümü `account_handle` ile adreslenir. İlk üçü Pulse sayfalarını ve REST API'lerini yansıtır; diğer beşi bir ajanın telemetriyi doğrudan keşfetmesine olanak tanır ve REST eşdeğeri yoktur:

| Araç | Amaç | `/api/accounts/:account_handle/pulse` altındaki REST eşdeğeri |
| --- | --- | --- |
| `query_pulse` | Pulse sayfa tabloları | `GET /:signal` |
| `get_pulse_analytics` | Pulse sayfa widget'ları | `GET /:signal/analytics` |
| `get_pulse_error_issue` | Bir hata sorunu ve olayları | `GET /errors/issues/:fingerprint` |
| `query_pulse_metrics` | Anlık veya aralıklı PromQL | Yok |
| `list_pulse_labels` | Etiket adları veya bir etiketin değerleri | Yok |
| `search_pulse_logs` | Filtrelenmiş günlük girdileri | Yok |
| `search_pulse_traces` | Filtrelenmiş span'ler | Yok |
| `get_pulse_trace` | Bir izlemenin tüm span'leri | Yok |

Pulse, bir hesap veya proje herkese açık olsa bile, sunucu tarafından yapılandırılmış kuruluşun mevcut üyeleriyle sınırlıdır. Kullanıcı kimlik doğrulaması veya kullanıcıyla ilişkili bir `mcp` kimlik bilgisi ve hesap okuma yetkisi gerektirir. Proje jetonları, normal hesap jetonları, anonim kayıtlar ve kuruluş üyeliği olmayan operatör erişimi Pulse erişimi sağlamaz. Kimlik bilgileri başka bir arka uç veya telemetri kiracısı seçemez ve yalnızca sunucu tarafından yapılandırılmış hesabın Pulse telemetrisi vardır, bu nedenle hiçbir araç başka bir hesabın verilerini okuyamaz. Tarayıcı ajanları bu araçları yalnızca Pulse sayfalarında, o sayfanın hesap kapsamı içinde alır.

REST bir kullanıcı kimlik bilgisi gerektirir. OAuth ve `auth.md` kullanıcı ilişkileri yalnızca `/mcp` uç noktasında mevcuttur; ilişkili hesabın üyeliği veya görünürlüğünden bağımsız olarak, mevcut kullanıcı içermeyen bir hesap kimlik bilgisi reddedilir.

`query_pulse`, `signal` (`metrics`, `logs`, `traces` veya `errors`), isteğe bağlı `query` ve `range` (`15m`, `1h`, `6h` veya `24h`, varsayılan `1h`) parametrelerini alır. Metrikler PromQL ifadelerini kabul eder. Günlükler, izler ve hatalar, günlük gövdeleri, span adları ve hata sorun başlıklarıyla eşleştirilen büyük/küçük harf duyarsız metinleri kabul eder; varsayılan olan `*` her şeyi seçer. İz satırları bireysel span'lerdir. Hata satırları sorunlardır: hizmete ve parmak izine göre gruplandırılmış olaylar; olay sayıları, etkilenen hesaplar, penceredeki ilk ve son oluşum ve en son olaylarının başlığı, sorumlusu, seviyesi ve platformu ile birlikte. Tablolar `search`, `page` (varsayılan `1`), `page_size` (`1`–`100`, varsayılan `20`), `sort_by` ve `sort_order` (`asc` veya `desc`) kabul eder. Sıralama sütunları sinyale bağlıdır ve araç şemasında listelenir. Filtreler arasında `service` ve günlükler ile hatalar için `level` bulunur. Filtre operatörleri karşılık gelen `_op` argümanını (`eq`, `contains` veya `not_contains`) kullanır; varsayılan olarak tam eşitlik geçerlidir.

Sıralama sütunları metrikler için `name`/`value`; günlükler için `timestamp`/`service`/`level`/`message`/`trace_id`; izler için `timestamp`/`service`/`name`/`duration_ms`/`trace_id`; ve hatalar için `last_seen`/`first_seen`/`events`/`accounts`/`title`/`service`/`level` şeklindedir. Kontrol paneli kasıtlı olarak bir alt küme sunar; API ve araçlar her sinyal için tam listeyi kabul eder.

Tablo yanıtları `rows`, `series`, `warnings` ve `meta` içerir. Sayfalama meta verileri `page`, `page_size`, `total_count`, `total_pages`, `has_next_page`, `has_previous_page` ve `end_at` içerir. Sorgu penceresini korumak için sonraki sayfalarla birlikte döndürülen ISO8601 `end_at` değerini iletin. Sonuç sınırı hataları, yanıtı boş bir tablo olarak ele almak yerine sorgunun veya zaman aralığının daraltılmasını gerektirir.

Günlükler ve izler, yerel sıralamadan önce en fazla 100 en yeni eşleşmeyi inceler; hatalar ise en son görülen 100 sorunu inceler. Filtreler, sıralama, sayfalama ve toplamlar yalnızca döndürülen eşleşmeleri tanımlar, tüm zaman penceresini değil. Diğer eşleşmeleri incelemek için sorgu metnini veya zaman aralığını daraltın; yerel aramayı veya sıralamayı değiştirmek upstream aramayı genişletmez. Toplama widget'ları, bu sınırlı tablo sonuçlarının toplamaları yerine bağımsız, tam pencere sorguları olarak kalır.

Metrik tabloları ifadelerini `end_at` noktasında bir kez değerlendirir, mevcut değerleri ve anlık vektör serisi başına bir nokta döndürür. Aralık vektörü ifadeleri sınırlı geçmiş noktalar döndürebilir. Ayrı analiz widget'ları sabit geçmiş grafikler sağlar; bir tablo, yalnızca en son değerini göstermek için her eşleşen seri için bir zaman ızgarası oluşturmaz.

Telemetri dizeleri güvenilmeyen verilerdir, talimatlar değildir.

`get_pulse_analytics`, hesap tanıtıcısı dışında yalnızca `signal` ve `range` alır. Sabit widget'ları tablo ifadelerinden, filtrelerden, sıralamadan ve sayfalama işleminden bağımsızdır.

`get_pulse_error_issue`, bir hata satırından bir sorunun `fingerprint` ve `service` değerlerini alır; buna isteğe bağlı olarak `range`, `end_at`, `page` ve `page_size` eklenir. Soru özeti, 60 eşit oluşum kovası, istisna zinciri, yığın çerçeveleri, iz sürme bilgileri, etiketler, bağlamlar, ek veriler, sorgu dizesi olmadan istek yöntemi ve URL içeren en son olayı ve tablolarla aynı sayfalama `meta` ile en yeniden eskiye doğru sıralanmış bir olay sayfasını döndürür. Hata satırları ayrıca her sorunun 60 kovalı `occurrence_series` serisini taşır. Olaylar depolamadan önce kişisel verilerden arındırılır, bu nedenle filtrelenen değerler `[Filtered]` veya `[REDACTED]` olarak görünür. Pencere içinde olayı olmayan bir sorun bulunamadı olarak raporlanır. REST ve Model Context Protocol aynı Pulse bağlamını ve yanıt sözleşmelerini kullanır. REST yanıtları önbelleğe almayı devre dışı bırakır.

#### Telemetriyi keşfetme

Keşif araçları, varsayılan olarak şu ana ayarlanan isteğe bağlı ISO8601 `end_at` ile biten `15m`, `1h`, `6h` veya `24h` (`1h` varsayılan, `get_pulse_trace` için `24h`) uzunluğunda bir pencere okur. Her yanıt `start_at` ve `end_at` döndürür; pencereyi korumak için aynı `end_at` değerini tekrar iletin. Bu araçların hiçbiri SQL kabul etmez.

- `query_pulse_metrics`, bir PromQL ifadesi olan `query` değerini `end_at` (`type: instant`, varsayılan) noktasında veya pencere boyunca her `step` saniyede bir (`type: range`) değerlendirir. Adım değeri varsayılan olarak pencerenin 360'a bölünmesine eşittir ve bundan küçük olamaz; bu nedenle bir seride en fazla 361 nokta bulunur. Sonuçlarda en fazla 5.000 seri vardır. Noktalar `[unix_seconds, value]` şeklindedir ve `NaN` ile sonsuz değerler dize olarak ifade edilir. Anlık sorgular `range` ve `step` parametrelerini reddeder.
- `list_pulse_labels` bir `signal` alır. `label` olmadan etiket adlarını listeler; `label` ile o etiketin değerlerini listeler. Metrikler için `__name__` metrik adlarını listeler ve diğer herhangi bir etiketin değerleri `up` gibi bir seri seçici olan `match` gerektirir. Günlük ve iz etiket değerleri `filters` kabul eder; iz etiket adları iz şemasından gelir ve bunu yapmaz. Günlük ve iz değerleri, penceredeki giriş sayılarını içerir (en sık olanlar önce gelir), bu nedenle hizmete göre hatalar gibi ayrıntılı dökümler olarak da hizmet ederler. `search` yalnızca değişmez metin içeren adları veya değerleri tutar ve `limit` `1`–`1000` aralığını (varsayılan `100`) kabul eder. Günlük etiket adı keşfi, her türden en fazla 1.000 farklı özellik kümesini inceler ve yalnızca filtrelerin kabul ettiği anahtarları listeler.
- `search_pulse_logs`, gövdesi `text` içeren ve her filtreyi eşleştiren en fazla `limit` girişi (`1`–`100`, varsayılan `50`), `newest` veya `oldest` öncelikli olarak döndürür. Her giriş `severity_text`, `body`, `trace_id`, `span_id`, `scope_name` ve birleştirilmiş kaynak ile günlük `attributes` bilgilerini içerir. `span_id` ve `scope_name`, yalnızca OTLP günlük göndericilerinin ayarladığı Kubernetes'ten toplanan günlükler için `null` değerindedir.
- `search_pulse_traces`, her filtreyi, isteğe bağlı `min_duration_ms` ve `max_duration_ms` değerlerini ve `root_only` koşulunu eşleştiren en fazla `limit` span'i, `newest`, `oldest` veya `slowest` öncelikli olarak döndürür.
- `get_pulse_trace`, pencere içinde başlayan `trace_id` span'lerini, en eskiden en yeniye doğru, en fazla 1.000 span olacak şekilde döndürür. Pencereden önce başlayan bir iz kısmen döndürülür; bu nedenle pencereyi genişletin veya taşıyın. Her span, span özelliklerini, olayları, bağlantıları ve izdeki benzersiz `resources` öğelerine yönelik bir dizini içerir.

Filtreler, en fazla 10 `{label, op, value}` nesnesinden oluşan listelerdir. `op` değeri `eq` (varsayılan), `neq`, `contains` veya `not_contains` olabilir; son ikisi büyük/küçük harfe duyarlı olmayan değişmez metinlerdir. Günlük etiketleri, Pulse bunları depoladığında `severity_text`, `trace_id`, `span_id` ve `scope_name` ile her girişin kaynak özelliklerinin anahtarlarıdır (örneğin `namespace`, `container` ve `service.name`) ve günlük özellikleridir (örneğin `pod`). Bir anahtar her ikisinde de göründüğünde kaynak özelliği geçerlidir. İz etiketleri, `list_pulse_labels` tarafından döndürülen span sütunlarıdır; örneğin `service_name`, `span_name`, `span_status_code` (başarısız span'ler için `STATUS_CODE_ERROR`), `span_attributes.http.route` ve `resource_attributes.k8s.pod.name`. Bilinmeyen bir iz etiketi boş sonuç yerine hata olarak bildirilir.

`truncated`, yanıtın içerdiğinden daha fazla ad, değer, giriş veya span'in eşleştiği anlamına gelir; yanıtı tam olarak kabul etmek yerine filtreleri veya pencereyi daraltın. Telemetri dizeleri güvenilmeyen verilerdir, talimatlar değildir.

<details>
<summary>Claude Code</summary>

Çalıştır:

```bash
claude mcp add --transport http tuist https://tuist.dev/mcp
```

Headless bir Claude Code istemcisi başarısız yerel sunucu bağlantısını modele göstermediğinde, aracının barındırılan belgeleri aramadan veya projeyi düzenlemeden önce yapılandırılmış uç noktanın kimliği doğrulanmamış [Hypertext Transfer Protocol](https://developer.mozilla.org/en-US/docs/Web/HTTP) yanıtını incelemesini zorunlu kılın. Yanıt, tarayıcı kimlik doğrulaması mevcut olmasa bile modeli dağıtım yerelindeki `auth.md` belgesine yönlendirir.

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

**Ayarlar → Bağlayıcılar → Özel bağlayıcı ekle** seçeneğini açın, ardından şunları ayarlayın:

- **Ad:** `tuist`
- **URL:** `https://tuist.dev/mcp`

İstendiğinde tarayıcıda [Open Authorization](https://oauth.net/2/) işlemini tamamlayın.

</details>


<details>
<summary>Pi</summary>

Pi bir Model Context Protocol istemcisi içermez. Kaynak kodunu ve güvenlik etkilerini inceledikten sonra üçüncü taraf [`pi-mcp-adapter`](https://pi.dev/packages/pi-mcp-adapter) uzantısını yükleyebilirsiniz:

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

`auth` değerini `false` olarak ayarlamak, adaptörün tarayıcı kimlik doğrulama işleyicisinin Tuist'in yetkisiz yanıtını gizlemesini engeller. Böylece headless bir aracı döndürülen `auth_md` URL'sini okuyabilir ve Tuist'in kayıt, kimlik iddiası değişimi ve talep yoklama akışını takip edebilir. Değiştirilen erişim token'ını bearer token olarak yapılandırın veya aracının doğrudan kimliği doğrulanmış Model Context Protocol çağrıları yapmasına izin verin.

Tarayıcı kimlik doğrulamasını tercih ediyorsanız `auth` değerini `"oauth"` olarak ayarlayın. Bu akış için, kimlik doğrulama tamamlanırken Pi'nin [remote procedure call mode](https://pi.dev/docs/latest/rpc) ile bir işlemi canlı tutun:

```bash
pi --mode rpc
```

Bekleyen bir tarayıcı kimlik doğrulamasını ayrı `pi --print` çağrılarına bölmeyin çünkü geri arama durumuna sahip olan süreç sonlandırılmıştır.

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

Ardından sunucuda kimlik doğrulaması yapın:

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

**Komut Paleti → MCP: Sunucu Ekle** seçeneğini kullanın, ardından şu ayarlarla bir [Hypertext Transfer Protocol](https://developer.mozilla.org/en-US/docs/Web/HTTP) sunucusu yapılandırın:

- **Ad:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>


<details>
<summary>Zed</summary>

**Ajan paneli → Ayarlar → Özel Sunucu Ekle** seçeneğini açın, ardından şunları ayarlayın:

- **Ad:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>

Aracınız `auth.md` destekliyorsa, tarayıcı açmadan anonim olarak başlayabilir. Sağlayıcı kimliği zaten bağlıysa güvenilir bir sağlayıcı kimliği de tarayıcı olmadan işlemi tamamlayabilir. Hizmetle kimliği doğrulanmış e-posta, anonim talep veya ilk sağlayıcı bağlantısı için aracı size bir Tuist doğrulama bağlantısı ve altı haneli bir kod gösterir. Bağlantıyı açın, oturum açın ve Tuist sayfasında aracının kodunu girin. Kodu asla aracıya geri göndermeyin. Tuist'in yetkilendirme sunucusu meta verileri doğrudan dağıtımın kendi `/auth.md` belgesine işaret eder; bu belge tam istek ve yoklama şekillerini içerir.

## Amp orb'larında ve Claude Code bulut oturumlarında çalışan ajanlar

Bir Tuist hesabına bağlı alan kutularında (sandbox) çalışan kodlama ajanları, tarayıcı veya kaydedilmiş bir Tuist kimlik bilgisi gerekmeden kendi kimlik token'larıyla uç noktada kimlik doğrulaması yapabilir:

- Hesabın **Ayarlar → Entegrasyonlar → Amp** altında bağladığı bir Amp çalışma alanının veya projesinin **Amp orb'ları**, orb'un kimlik token'ını gönderir. Amp'te sunucunun `Authorization` başlığını `Bearer ${amp:id-token}` olarak ayarlayın. Amp, token'ı sunucu URL'sinin kaynağı için basar, bu nedenle URL bu Tuist örneğinin kendi adresi olmalıdır ve süresi dolmadan önce yeniler. Başka bir kaynak için basılan token'lar reddedilir.
- Bağlı bir Claude Code ortamının **Claude Code bulut oturumları**, Tuist'in kendilerine `TUIST_OIDC_TOKEN` olarak ilettiği oturum token'ını gönderir. Başlığı `Bearer ${TUIST_OIDC_TOKEN}` olarak ayarlayın.

Tuist'in Linux alan kutuları bununla birlikte gelir: Amp'in kullanıcı ayarlarında ve Claude Code'un kullanıcı yapılandırmasında, her ikisi de `${TUIST_URL}/mcp` adresine yönlendirilmiş bir `tuist` sunucusu; ayrıca Tuist CLI ve aracının sonuçlarını projenin geçmişine göre ne zaman kontrol edeceğini söyleyen bir beceri. Başka yerlerde, yukarıdaki başlıkla sunucuyu kendiniz ekleyin.

Bu token'lar bağlı hesabın her projesine salt okunur erişim sağlar: `mcp` grubunun okuma kapsamlarını taşırlar ve testleri sessize alma veya atlatma gibi veri oluşturan, değiştiren veya silen hiçbir kapsam taşımazlar. Çalışma alanının veya ortamın bağlantısını kesmek, sonraki istekte erişimi durdurur ve erişim asla token'ın kendisinden daha uzun sürmez. Birden fazla Tuist hesabına bağlı bir Amp çalışma alanı reddedilir çünkü token'ı tek bir hesabı adlandırmaz. Bir bağlantı eksik olduğunda, yetkisiz yanıtın `error_description` alanı bunu belirtir.

Bu salt okunur erişim yalnızca Model Context Protocol uç noktası için geçerlidir. Aynı alan kutusundaki komut satırı aracı ve derleme sistemi entegrasyonları, token'ı yine de bağlantının CI erişimi için değiştirir.

## WebMCP

[WebMCP](https://webmachinelearning.github.io/webmcp) destekleyen tarayıcılarda, Tuist sayfaları araçları `document.modelContext` ile kaydeder, böylece tarayıcıya yerleşik ajanlar herhangi bir ek yapılandırma olmadan bunları çağırabilir. Çağrılar Tuist sunucusunda çalışır.

- **Web sitesi ve belge sayfaları**, belge ve kaynak araçlarını (`search_tuist`, `search_tuist_code`, `list_tuist_files` ve `read_tuist_file`) kaydeder. Oturum açmanıza gerek yoktur.
- Oturum açtığınızda **bir hesabın pano sayfaları**, o hesap için Tuist'in salt okunur araçlarını kaydeder. Her sayfa yalnızca gösterdiği içeriğe ve projenin derleme sistemine yönelik araçları kaydeder: bir Gradle projesinin derlemeler sayfası Gradle derleme araçlarını, test sayfaları test ve kapsam araçlarını, çalıştırıcı sayfaları çalıştırıcı araçlarını ve alan kutusu sayfaları alan kutusu araçlarını alır. Her sayfa ayrıca belge araçlarını, `list_projects` ve `get_project` araçlarını da alır. Araçlar oturum açmış kullanıcı olarak çalışır, bu nedenle yalnızca panoda okuyabileceğiniz verilere ve yalnızca baktığınız hesaba erişebilirler. Başka bir sayfaya veya hesaba geçtiğinizde, araçlar o sayfanın araçlarıyla değiştirilir.

Veri oluşturan, değiştiren veya silen araçlar WebMCP üzerinden kullanılamaz, çünkü bir tarayıcı ajanı araçları sizin eklemeniz olmadan alır ve derlemeler ile testlerin ürettiği içeriği okur. Bu araçları kullanmak için bir MCP istemcisini `/mcp` uç noktasına bağlayın.

Kuruluş tek oturum açmayı zorunlu kılıyorsa, araçlarını kullanmak için panoya sağlayıcısıyla oturum açın.

## Derleme sistemi entegrasyonları iki kimlik bilgisi kullanır

Model Context Protocol araçları için kullanılan kimlik bilgisi, Gradle eklentisini veya Bazel'in uzak hizmetlerini doğrulamaz. Bir aracı bir Gradle veya Bazel entegrasyonunu düzenlemeden veya doğrulamadan önce şunu çalıştırmalıdır:

```bash
tuist auth whoami --url https://tuist.dev
```

Bu komut kimliği doğrulanmamışsa, aracı durmalı ve kullanıcıdan şunu çalıştırmasını istemelidir:

```bash
tuist auth login --url https://tuist.dev
```

Yerel veya kendi barındırdığınız bir dağıtım için, her iki komuttaki ve `tuist.toml` dosyasındaki URL'yi değiştirin. Ana bilgisayar adının yazımını her yerde aynı tutun. Örneğin, `localhost` ve `127.0.0.1` ayrı kaydedilmiş kimlik bilgileri kullanır.


## Yetenekler

### Araçlar

Aşağıdaki araçlar Tuist Model Context Protocol sunucusu üzerinden kullanılabilir:

Her araç, açık giriş ve çıkış şemalarıyla birlikte insan tarafından okunabilir bir açıklama yayımlar. Başarılı çağrılar, ilan edilen çıkış şemasına uygun yapılandırılmış içerik döndürür; ayrıca henüz yapılandırılmış içeriği tüketmeyen istemciler için aynı sonucu metin olarak serileştirir.

Tek bir kaydın tanımlayıcısını alan araçlar, örneğin `build_run_id`, `test_run_id`, `test_case_id`, `bundle_id`, `run_id`, `generation_id` veya `cache_run_id`, o kaydın Tuist pano URL'sini de kabul eder. Tanımlayıcıyı ayıklamak yerine URL'yi doğrudan tarayıcıdan yapıştırın.

`get_xcode_build`, `get_test_run`, `get_gradle_build` ve `get_project` `side_quests` içerebilir: projenin kullanmadığı ancak kaydın yardımcı olacağını gösterdiği Tuist yetenekleri. Her birinin bir `id`, dayandığı kanıtı belirten bir `tip` ve bir `docs` bağlantısı vardır. Ajanlardan öncelikle kullanıcının isteğini tamamlamaları, geçerli yan görevlerden bahsetmeleri ve yalnızca kullanıcı onay verdiğinde bunlardan birini uygulamaları istenir. Bunlar yalnızca projenin hesabının üyelerine döndürülür; ister kullanıcı oturumu, ister MCP token'ı, ister aracı kimliğiyle bağlansınlar:

| Kimlik | Araç | Önerildiği durumlar |
|----|------|----------------|
| `xcode_compilation_cache` | `get_xcode_build` | Xcode 26 veya sonraki bir sürümle işlenen temiz bir derleme, önbelleğe alınabilir derleme görevi çalıştırmadı. |
| `gradle_build_cache` | `get_gradle_build` | Bir derleme, Gradle'ın derleme önbelleği bunlardan hiçbiri için bir anahtar hesaplamadan önbelleğe alınabilir görevleri yürüttü; bu, derleme önbelleğinin kapalı olduğu anlamına gelir. |
| `flaky_test_quarantine` | `get_test_run` | Bir çalıştırmada kararsız testler vardı ve projede etkinleştirilmiş hiçbir otomasyon bunları sessize almıyor veya atlamıyor. Once projeleri için önerilmez. |
| `test_sharding` | `get_test_run` | Tuist'in parçalayabileceği bir derleme sisteminde, parçalanmamış bir CI çalıştırması 10 dakika veya daha uzun sürdü. İpucu, seçici testin ne zaman yaptığına bağlı olarak zaten kaç testi atladığını belirtir. |
| `tuist_runners` | `get_xcode_build`, `get_test_run` | Bir CI çalıştırması GitHub Actions, Bitrise, GitLab CI veya Buildkite makinelerini kullandı ve hesap hiçbir zaman Tuist Runners üzerinde bir iş çalıştırmadı. Yalnızca tuist.dev'de. |
| `pull_request_comments` | `get_xcode_build`, `get_test_run` | Bir GitHub Actions çalıştırması, GitHub deposuna bağlı olmayan bir projeye aittir. |
| `other_build_systems` | `get_project` | Hesap, desteklenen her derleme sistemiyle Tuist'i kullanmıyor. İpucu, diğerlerini tanımlayan dosyaları listeler, böylece aracı depoyu kontrol edebilir. |

#### Belgelendirme ve topluluk araması

Bu salt okunur araç, Tuist'in belgelerini, [uygulama programlama arayüzü](https://en.wikipedia.org/wiki/API) referansını, GitHub sürümlerini, topluluk forumunu ve GitHub sorunlarını belge sitesine güç veren aynı arama motoru üzerinden arar. Sürüm sonuçları ürünü, sürümü, yayın tarihini ve ön sürüm durumunu içerir. Varsayılan olarak kararlı sürümler aranır ve ön sürümler `include_prereleases` ile dahil edilebilir. Araç yalnızca `https://tuist.dev/mcp` adresindeki Tuist tarafından barındırılan sunucuda kullanılabilir.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `search_tuist` | Genel Tuist belgelerini, uygulama programlama arayüzü referansını, GitHub sürümlerini, topluluk tartışmalarını ve GitHub sorunlarını arayın. İsteğe bağlı olarak tek bir `source` ile sınırlayın (`docs`, `api_reference`, `releases`, `forum`, `issues`). | `query` |

#### Geri bildirim

Ajanlar, bir Tuist aracının veya isteminin bekledikleri gibi çalışmadığında (kafa karıştırıcı bir sonuç, hata, eksik veri veya eksik bir yetenek gibi) Tuist ekibine bildirebilir. Ajanlardan bir rapor önermeleri ve bunu yalnızca siz onay verdikten sonra göndermeleri istenir. Her rapor, Tuist desteği ile bir konuşma başlatır; destek ekibi size e-posta ile yanıt verebilir. Bir rapor, ajanın ne beklediğini, ne olduğunu, isteğe bağlı bir öneriyi, Tuist kullanıcı kimliğinizi, kullanıcı adınızı ve e-postanızı ve ait olduğunuz kuruluşları içerir. Ajanlar ayrıca sorunun yaşandığı hesabı ve projeyi de belirtebilir, böylece ekip hangi kuruluşla iletişime geçeceğini bilir; yalnızca ait olduğunuz hesaplar kabul edilir. Raporları yalnızca Tuist kullanıcısı olarak oturum açmış ajanlar gönderebilir ve her kullanıcı saatte en fazla 10 rapor açabilir. Araç yalnızca `https://tuist.dev/mcp` adresindeki Tuist tarafından barındırılan sunucuda kullanılabilir.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `report_feedback` | Bir Tuist aracı veya istemiyle ilgili bir sorunu bildirin. İsteğe bağlı olarak `tool_name`, gerçekleştiği `account_handle` ve `project_handle` belirtin ve bir `suggestion` ekleyin. | `category`, `expected`, `actual` |

#### Kaynak destekli yanıtlar

Bu salt okunur araçlar, ajanların mevcut davranışa dayanan yanıtlar için gerçek kaynak olarak barındırılan sunucuyla birlikte dağıtılan tam genel Tuist kaynak revizyonunu kullanmasına olanak tanır. Yalnızca `https://tuist.dev/mcp` adresinde kullanılabilirler.

Uyumlu istemciler, başlatma sırasında satır içi OAuth kimlik doğrulama bilgilerinin yanı sıra araçların kaynak revizyonuna ilişkin olgusal açıklamaları, bağlantıları ve sonuç sınırlamalarını alır. Bu açıklamalar yanıt stilini veya bir doğrulama iş akışını dayatmaz. Kullanıcılar, önce `ask_tuist` istemini çağırmadan doğrudan bir soru sorabilir; istem, açık bir kaynak destekli iş akışı için kullanılmaya devam eder.

Her işlemin eşzamanlılık, süre, tarama, okunan bayt ve yanıt boyutu için sabit sınırları vardır. Arama ve listeleme sonuçları `truncated` ve `truncation_reason` alanlarını içerir. Bir sonuç kısaltıldığında, sonucu kapsamlı olarak değerlendirmek yerine yolu, dosya kalıbını veya arama terimini daraltın.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `search_tuist_code` | Kaynak dosyaları arayarak mevcut davranış, varsayılanlar, yapılandırma, özellik kapıları, hata yönetimi veya belgelenmemiş ayrıntılar hakkındaki soruları yanıtlayın. Sonuçlar çevredeki satırları, revizyon sabitli kaynak bağlantılarını ve tarama istatistiklerini içerir. | `pattern` |
| `list_tuist_files` | İlgili yol bilinmediğinde bir kaynak alt sistemini veya yakındaki testleri keşfedin. Listelemelerin sınırlı derinliği ve sonuç sayıları vardır. | Yok |
| `read_tuist_file` | İlgili yolu bulduktan sonra bir uygulama dosyasındaki, çağrı noktasındaki veya testteki odaklanmış satır aralığını inceleyin. Kısaltılmış yanıtlar devam için `next_start_line` sağlar. | `path` |

#### Projeler

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_accounts` | Kimliği doğrulanmış kullanıcı için kullanılabilen kişisel ve kuruluş hesap kullanıcı adlarını, her hesabın proje oluşturup oluşturamayacağı dahil olmak üzere listeleyin. | Yok |
| `get_organization` | Bir kuruluşun üye dizinini alın. Bekleyen davetler, pano ile aynı yönetici iznini gerektirir; davet kabul token'ları asla döndürülmez. | `account_handle` |
| `create_organization` | Kimliği doğrulanmış kullanıcı için bir Tuist kuruluşu oluşturun. | `handle` |
| `create_project` | Kimliği doğrulanmış kullanıcının erişebileceği bir hesap altında bir Tuist projesi oluşturun. | `account_handle`, `project_handle` |
| `add_organization_member` | Mevcut bir Tuist kullanıcısını bir kuruluşa ekleyin veya mevcut bir üyenin rolünü güncelleyin. `user` (varsayılan), `admin` veya `viewer` kabul edilir; burada görüntüleyici panoları ve çalıştırmaları okuyabilir ancak hiçbir şeyi değiştiremez. | `organization_handle`, `email` |
| `invite_organization_member` | Bir e-posta adresini, mevcut bir Tuist kullanıcısına ait olup olmadığına bakmaksızın bir kuruluşa davet edin. Tuist, 14 gün sonra sona eren bir kabul bağlantısı içeren e-posta gönderir; sunucu e-posta gönderemediğinde `email_sent` değeri `false` olur ve bağlantının panodan kopyalanması gerekir. `user` (varsayılan), `admin` veya `viewer` kabul edilir. Kuruluş yöneticisi izni gerektirir. | `organization_handle`, `email` |
| `cancel_organization_invitation` | Bekleyen bir kuruluş davetini iptal ederek bağlantısının artık kabul edilememesini sağlayın. Kuruluş yöneticisi izni gerektirir. | `organization_handle`, `email` |
| `list_projects` | Kimliği doğrulanmış kullanıcı tarafından erişilebilen tüm projeleri listeleyin. | Yok |
| `get_project` | Bir projenin yapılandırmasını ve bağlı depo URL'sini alın. | `account_handle`, `project_handle` |
| `connect_project_repository` | Bir projeyi, hesabın GitHub Uygulaması yüklemesinin erişebileceği bir GitHub deposuna bağlayın. Proje, deponun varsayılan dalını benimser. Proje yöneticisi izni gerektirir. | `account_handle`, `project_handle`, `repository_full_handle` |
| `disconnect_project_repository` | Bir projenin GitHub deposuna olan bağlantısını kaldırın. Proje yöneticisi izni gerektirir. | `account_handle`, `project_handle` |

#### Hesap token'ları

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_account_tokens` | Token değerlerini açığa çıkarmadan hesap token meta verilerini listeleyin. | `account_handle` |
| `get_account_token` | Değerini açığa çıkarmadan hesap token meta verilerini alın. | `account_handle`, `token_id` |
| `list_project_tokens` | Token değerlerini açığa çıkarmadan proje token meta verilerini listeleyin. | `account_handle`, `project_handle` |

#### Bildirim kuralları

Bu araçlar, kimliği doğrulanmış kullanıcının kendi bildirim kurallarını yönetir: Kuralın projelerinde (veya hiçbirini listelemediğinde bildirilebileceğiniz herhangi bir projede) yeni bir önizleme gibi bir olay gerçekleştiğinde ve koşulları karşıladığında, Tuist uygulama cihazlarınıza push bildirimi gibi eylemlerini yürütür. Kurallar olmadan bildirim almazsınız. Kullanıcı kimlik doğrulaması gerektirirler, yalnızca kendi kurallarınız üzerinde işlem yaparlar ve yalnızca ait olduğunuz hesaplara ait projeleri kabul ederler. Kurallar tüm hesaplarınızı kapsadığından pano sayfalarında sunulmazlar.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_notification_events` | Kuralların abone olabileceği olay türlerini, her biri için koşullarına ilişkin bir JSON Şeması ile birlikte listeleyin. | Yok |
| `list_notification_condition_options` | Bir projedeki bir olay için koşul değerleri önerin; örneğin, son önizlemelerinin track'leri ve dalları. | `event`, `account_handle`, `project_handle` |
| `list_notification_rules` | Kurallarınızı listeleyin. | Yok |
| `create_notification_rule` | Bir olaydan, isteğe bağlı projelerden ve koşullardan ve en az bir eylemden oluşan bir kural oluşturun. | `event`, `actions` |
| `update_notification_rule` | Bir kuralın etkin durumunu, projelerini, koşullarını veya eylemlerini değiştirin. | `rule_id` |
| `delete_notification_rule` | Bir kuralı silin. | `rule_id` |

#### Sürekli entegrasyon çalıştırıcıları

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_runner_jobs` | Bir hesap için sürekli entegrasyon çalıştırıcı işlerini listeleyin. | `account_handle` |
| `get_runner_job` | Bir sürekli entegrasyon çalıştırıcı işini alın; makinenin belleğinin dolup dolmadığı, neyi durdurduğu ve neyin değiştirilmesi gerektiği dahil. | `account_handle`, `workflow_job_id` |
| `list_runner_job_steps` | Bir sürekli entegrasyon çalıştırıcı işi için kaydedilen adımları listeleyin. | `account_handle`, `workflow_job_id` |
| `list_runner_job_metrics` | Bir sürekli entegrasyon çalıştırıcı işi için kaydedilen makine metriklerini listeleyin. | `account_handle`, `workflow_job_id` |
| `list_runner_job_logs` | Bir sürekli entegrasyon çalıştırıcı işi için yakalanan en fazla 500 günlük satırını listeleyin. | `account_handle`, `workflow_job_id` |
| `list_runner_workflows` | Bir hesap için sürekli entegrasyon iş akışı özetlerini listeleyin. | `account_handle` |
| `list_runner_profiles` | Bir hesap için sürekli entegrasyon çalıştırıcı profillerini, her birinin `runs-on` etiketiyle birlikte listeleyin. | `account_handle` |
| `get_runner_catalog` | Bir çalıştırıcı profilinin kullanabileceği makine şekillerini ve Xcode sürümlerini listeleyin. | `account_handle` |
| `create_runner_profile` | Bir platform, bir makine şekli ve macOS'ta bir Xcode sürümü ile bir çalıştırıcı profili oluşturun. İsteğe bağlı olarak hangi dalların önbellek birimlerini kaydedeceğini ayarlayın. Hesap yöneticiliği veya `account:runners:write` kapsamı gerektirir. | `account_handle`, `name`, `platform`, `vcpus`, `memory_gb` |
| `update_runner_profile` | Bir çalıştırıcı profilinin makine şeklini, Xcode sürümünü veya özel önbellek birimi değişikliklerini hangi dalların kaydedeceğini değiştirin. Atlanmış alanlar değerlerini korur. Hesap yöneticiliği veya `account:runners:write` kapsamı gerektirir. | `account_handle`, `profile_name` |
| `delete_runner_profile` | Kullanıcı onayından sonra bir çalıştırıcı profilini silin. Varsayılan profiller silinemez. Hesap yöneticiliği veya `account:runners:write` kapsamı gerektirir. | `account_handle`, `profile_name` |

Çalıştırıcı birimi araçları, Birimler panosuyla aynı verileri sunar. Okuma araçları çalıştırıcı erişimi gerektirir; temizleme işlemi hesap yöneticiliği veya `account:runners:write` kapsamı ve kullanıcı onayı gerektirir.

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

Sandbox araçları, Sandbox'lar panosuyla aynı verileri ve eylemleri, [API](https://tuist.dev/api/docs) ile aynı erişimle sunar: hesap üyeleri sandbox'ları listeleyebilir, alabilir, oluşturabilir, duraklatabilir, devam ettirebilir ve silebilir; ancak bir aracı ortamı, Amp'i veya uzak yürütmeyi sunan sandbox'lar ile analiz ve arşiv araçları hesap yöneticiliği gerektirir. Salt okunur görüntüleyiciler bunları kullanamaz. Hesabın sandbox'ların etkinleştirilmiş olması gerekir. Panonun sandbox sayfaları salt okunur araçları kaydeder.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_sandboxes` | Sandbox'ları durumları, şekilleri ve zaman damgalarıyla sayfalandırın. İsteğe bağlı `search` (sandbox'taki metin, Amp Orb veya Anthropic oturum kimliği), `status`, `vcpus`, `sort_by` (`created`, `last_active`, `identifier`) ve `sort_order`. | `account_handle` |
| `get_sandbox` | Bir sandbox'ın durumu, şekli, düğümü, arşivi ve zaman damgaları. | `account_handle`, `sandbox_id` |
| `get_sandbox_analytics` | vCPU-saatleri, oluşturulan sandbox'lar, oturum, kurulum ve başlama süresi süreleri ve hesabın limitlerine göre tepe vCPU'lar, bellek ve disk, eğilimlerle birlikte. İsteğe bağlı `start` ve `end` (ISO 8601); varsayılan 30 gün, maksimum 90. | `account_handle` |
| `create_sandbox` | Boş bir sandbox önyükleyin ve çalıştığında geri döndürün. İsteğe bağlı `platform` (`linux` veya `darwin`), `template`, `memory_mb` ile `vcpus` (Linux: 2x4096, 4x8192 veya 8x16384, varsayılan 2x4096; macOS: 8x8192, 8x16384 veya 8x24576, varsayılan 8x8192) ve `workspace_gb`. Açıklaması, aracıya Mac'te `mise install` ile deponun sabitlenmiş Tuist'ini yüklemesini söyler; bu da daha sonra <.localized_link href="/guides/features/sandboxes#tuist-in-sandbox">hesabın önbelleğini</.localized_link> kendi başına kullanır. | `account_handle` |
| `pause_sandbox` | Çalışan bir sandbox'ın anlık görüntüsünü düğümünün diskine alın. | `account_handle`, `sandbox_id` |
| `resume_sandbox` | Duraklatılmış veya arşivlenmiş bir sandbox'ı devam ettirin. | `account_handle`, `sandbox_id` |
| `archive_sandbox` | Duraklatılmış bir sandbox'ın disklerini nesne depolamaya taşımayı kuyruğa alın. | `account_handle`, `sandbox_id` |
| `delete_sandbox` | Kullanıcı onayından sonra bir sandbox'ı ve disklerini silin. | `account_handle`, `sandbox_id` |

#### Amp çalışma alanları

Bu araçlar, orb'ların token olmadan Tuist'e oturum açmasını sağlayan <.localized_link href="/guides/server/authentication#amp-orbs">Amp çalışma alanı bağlantılarını</.localized_link> yönetir. Panonun Entegrasyonlar sayfasıyla aynı yöneticiye özel izni kullanırlar. Bir orb'daki aracı, kendi kimliklerini `$AMP_WORKSPACE_ID` ve `$AMP_PROJECT_ID` üzerinden okuyabilir. Bir bağlantının kabul ettiği her orb, hesaptaki tüm projelere CI erişimi kazanır; bu nedenle aracılar bağlanmadan önce kullanıcıyla onaylamalıdır.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_amp_workspace_connections` | Hesabın bağlı Amp çalışma alanlarını ve her birinin sınırlandırıldığı projeyi, varsa listeleyin. | `account_handle` |
| `connect_amp_workspace` | Bir Amp çalışma alanını bağlayın. İsteğe bağlı `project_id`, oturum açmayı tek bir Amp projesinin orb'larıyla sınırlar. | `account_handle`, `workspace_id` |
| `disconnect_amp_workspace` | Bir çalışma alanının bağlantısını kesin. Orb'larının zaten sahip olduğu oturumlar, süresi dolana kadar geçerli kalır. | `account_handle`, `connection_id` |

#### Claude ortamları

Bu araçlar, Claude Managed Agents self-hosted ortamlarını bağlar, böylece oturumları Ayarlar → Entegrasyonlar → Claude'da olduğu gibi Tuist sandbox'larında çalışır. Hesap yöneticiliği ve etkinleştirilmiş sandbox'lar gerektirirler. Bir aracı, Anthropic'in API'si ile ortamı oluşturabilir, ancak yalnızca Claude Console ortam anahtarını oluşturur; bu nedenle aracı kullanıcıdan bunu ister. Tuist, oturumları bir Anthropic API anahtarı veya iş yükü kimlik federasyonu ile başlatır ve kaydetmeden önce o kimlik bilgisiyle ortamı getirir. Anthropic tarafındaki kurulum, kullanıcının kendi Anthropic kimlik bilgilerini kullanır; Tuist bunları asla almaz. Anahtarlar istemci ve model üzerinden geçtiğinden, bunları yalnızca açıkça sağlayın.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_claude_environments` | Bağlı ortamları ve her birinin kullandığı kimlik bilgisini, ayrıca bir federasyon kuralının güvenmesi gereken yayıncı URL'sini ve konu önekini listeleyin. | `account_handle` |
| `connect_claude_environment` | `api_key` ile veya `organization_id`, `workspace_id`, `service_account_id` ve `federation_rule_id` kullanarak bir ortam bağlayın. İsteğe bağlı `platform`, `vcpus` ve `memory_mb` sandbox boyutunu belirler. | `account_handle`, `environment_id`, `environment_key` |

#### Webhook'lar

Webhook araçları, pano ile aynı yöneticiye özel izni kullanır. Teslimat denemeleri, uç nokta için kaydedilen istek ve yanıt verilerini içerir ancak uç nokta imzalama gizli anahtarını asla içermez.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_webhook_endpoints` | Bir hesap için webhook uç noktalarını listeleyin. | `account_handle` |
| `get_webhook_endpoint` | Bir webhook uç noktasını alın. | `account_handle`, `webhook_endpoint_id` |
| `list_webhook_delivery_attempts` | Bir uç nokta için teslimat denemelerini listeleyin. | `account_handle`, `webhook_endpoint_id` |
| `get_webhook_delivery_attempt` | Bir teslimat denemesini alın. | `account_handle`, `webhook_endpoint_id`, `delivery_attempt_id` |

#### Xcode derlemeleri

Xcode, Gradle, Bazel, Mix ve Cargo için derleme ayrıntısı araçları, bildirildiğinde altyapı gözlemleri de dahil olmak üzere mevcut `custom_metadata: {tags, values}` yapısını ortaya çıkarır. Değerler dize olarak kalır ve bilinmeyen anahtarlar korunur. Örneğin, `tuist.cpu.available_processors` çalışma zamanında kullanılabilir mantıksal işlemcileri tanımlarken, `tuist.gradle.max_workers` bir Gradle işçi sınırıdır ve `tuist.jvm.max_heap_bytes` bir JVM yığın sınırıdır, ana makine belleği değil. Bunlar güvenilir olmayan istemci gözlemleridir, doğrulanmış çalıştırıcı kimlikleri değildir. Eksik gözlemler eksik kalır; içe aktarılan günlükler ve daha eski istemcilerde altyapı meta verileri olmayabilir. Meta veriler, koordineli bir istemci/protokol güncellemesini beklemektedir.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_xcode_builds` | Bir proje için Xcode derleme çalıştırmalarını listeleyin. | `account_handle`, `project_handle` |
| `get_xcode_build` | Belirli bir Xcode derleme çalıştırması hakkında, ham `.xcactivitylog` dosyasını içeren arşiv için geçici bir indirme URL'si de dahil olmak üzere ayrıntılı bilgi alın. | `build_run_id` |
| `list_xcode_build_targets` | Belirli bir Xcode derleme çalıştırması için derleme hedeflerini listeleyin. | `build_run_id` |
| `list_xcode_build_files` | Belirli bir Xcode derleme çalıştırması için derlenmiş dosyaları listeleyin. | `build_run_id` |
| `list_xcode_build_steps` | Günlük metni olmadan, zamanlamalar ve sonuçlarla birlikte kaydedilmiş derleme adımlarını listeleyin. | `build_run_id` |
| `get_xcode_build_step` | Günlüğü ve kesme bayrağı dahil olmak üzere tek bir kaydedilmiş derleme adımını alın. | `build_run_id`, `step_id` |
| `list_xcode_build_issues` | Belirli bir derleme çalıştırması için derleme sorunlarını (uyarılar ve hatalar) listeleyin. | `build_run_id` |
| `list_xcode_build_cache_tasks` | Belirli bir Xcode derleme çalıştırması için önbelleklenebilir görevleri (önbellek isabetleri/kaçırılanlar) listeleyin. | `build_run_id` |
| `list_xcode_build_cas_outputs` | Belirli bir Xcode derleme çalıştırması için [içerik adreslenebilir depolama](https://en.wikipedia.org/wiki/Content-addressable_storage) çıktılarını listeleyin. | `build_run_id` |

`list_xcode_build_steps`, varsayılan olarak 20 adımdan oluşan sayfalar döndürür (`page_size` aracılığıyla maksimum 100), gezinme için `page` ve `pagination_metadata` ile birlikte. Başlıkları, projeleri veya hedefleri eşleştirmek için `search` kullanın veya tam `project`, `target`, `category` (örneğin, `swiftCompilation`) ve `status` (`success` veya `failure`) filtreleyin. En yavaş olanı önce getirmek için `duration_ms` ile veya kronolojik sıra için `start_ms` ile sıralayın. Adım kimlikleri beraberlikleri bozar ve tam 64 bit hassasiyetlerini korumak için ondalık dizeler olarak döndürülür. Kimlikler bir derlemeyle sınırlıdır ve derlemeler arasında eşleştirilmemelidir.

İsteğe bağlı `start_ms` ve `end_ms`, derleme başlangıcından itibaren milisaniye cinsinden bir zaman aralığıyla örtüşen adımları seçer; bitiş hariçtir. Her iki araç da `build_run_id` olarak bir derleme UUID'sini veya pano URL'sini kabul eder. Günlüğünü almak için döndürülen adım `id` değerini `step_id` olarak değiştirilmeden iletin. Günlükler adım başına 64 KiB'a kadar saklanır, `log_truncated` atlanan çıktıyı gösterir.

Adımlar, Xcode derlemeleri işlendiğinde varsayılan olarak toplanır. Kaydedilmiş adım verileri 90 gün boyunca saklanır. Liste yanıtı `availability` içerir: Filtreler hiçbirini eşleştirmese bile kaydedilmiş adımlar varsa `available`; derleme hala işleniyorsa ve henüz adım yoksa `processing`; veya adımlar kaydedilmediyse veya süresi dolduysa `unavailable`.

Aynı işlemler, aynı filtreler ve sayfalama ile HTTP API üzerinden `GET /api/projects/{account_handle}/{project_handle}/xcode/builds/{build_id}/steps` ve `GET /api/projects/{account_handle}/{project_handle}/xcode/builds/{build_id}/steps/{step_id}` adreslerinde mevcuttur. Her ikisi de derlemenin projesine okuma erişimi gerektirir.

#### Gradle derlemeleri

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `get_gradle_integration_guide` | Tam kimlik doğrulama, proje kurulumu, Gradle eklentisi, önbellek politikası ve iki derlemeli doğrulama iş akışını döndürün. Aracılar, mevcut bir Android veya Gradle projesini düzenlemeden önce bunu çağırmalıdır. | Yok |
| `list_gradle_builds` | Özel meta veriler dahil olmak üzere bir proje için Gradle derleme çalıştırmalarını listeleyin. İsteğe bağlı `tag` parametresi ile özel bir etikete göre filtreleyin. | `account_handle`, `project_handle` |
| `get_gradle_build` | Derleme meta verilerini, görev/önbellek sayılarını ve `failures` öğelerini alın: başarısız olan her görevin ve yapılandırma adımının hata mesajı. | `build_run_id` |
| `list_gradle_build_tasks` | Görev sonuçlarını, bileşik derleme kimliğini, önbelleklenebilirliği, artımlı durumu ve hata mesajlarını listeleyin. | `build_run_id` |
| `list_gradle_build_steps` | Arama, meta veri ve örtüşen zaman filtreleri ile zamanlanmış görevleri, yapılandırmayı ve dönüşümleri listeleyin. | `build_run_id` |
| `get_gradle_build_step` | Opak kimliğe göre kaydedilmiş adım meta verilerini inceleyin; başarısız bir görevin veya yapılandırma adımının `log`, onun hata mesajıdır. | `build_run_id`, `step_id` |

Gradle ve Bazel adım listeleri varsayılan olarak 20 sonuç döndürür (maksimum 100), `search`, tam eşleşen `project`, `target`, `category` ve `status`, örtüşen `start_ms` / `end_ms` filtrelerini (bitiş hariç) ve `duration_ms` veya `start_ms` sıralamasını destekler. Döndürülen kimlikleri değiştirilmeden iletin; bunlar kendi derlemelerine özgüdür. Listeler `time_origin` ve `coverage` sunar. Daha eski Gradle raporları, derleme başlangıcı yüklenmediği için `first_recorded_timestamp` kullanır. Bazel profilleri, `trace_profile` kapsamı ve zaman kaynağı olarak `profile_start` ile tüm kaydedilmiş aralıkları sunar. Daha eski derlemeler, saklanan BEP özetlerine geri döner. Kaynak kayıtlar 90 gün sonra sona erer. Bazel ayrıntıları, yayınlandığında temizlenmiş eylem günlüklerini içerir. Başarısız bir görevin veya yapılandırma adımının Gradle ayrıntıları, Tuist Gradle eklentisinin `log` olarak bildirdiği hata mesajını içerir: istisna mesajı ve Gradle konsolunun yazdırdığı şekilde neden zinciri, yığın izleri veya görev çıktısı olmadan, proje içindeki yollar göreceli hale getirilmiş ve kimlik bilgileri ile diğer yerel yollar sansürlenmiş olarak, adım başına en fazla 16 KiB ve derleme başına 32 başarısız adım. Diğer Gradle adımları, daha eski eklenti sürümleri tarafından bildirilen derlemeler ve kimlik bilgisi içermeyen raporlar için `log` boş değerdir. Yapılandırma adımları başarısız olduklarında `failure`, aksi takdirde `unknown` bildirir. `compare_builds` istemi, tam Bazel izlerini saklanan özetlerden ayırmak için bu kapsamı kullanır ve aracıları, daha geniş çağrı çıktısını kontrol etmeden önce eylem sonuçları ve günlükler için adım ayrıntılarına yönlendirir.

Tek adımlı araçlar `get_gradle_build_step` ve `get_bazel_build_step`, bir adımı kimliğe göre alır ve zaman filtrelerini kabul etmez; adımları zaman aralığına göre filtrelemek için ilgili liste araçlarını kullanın.

Saklanan özetlerden döndürülen Bazel adım kimlikleri, bir adım listelenip alınırken tam bir profil gelirse okunabilir kalır. Adım verilerinin süresi dolmuş indekslenmiş bir profil, kullanılamıyor olarak bildirilir. Gradle adım listeleri, sıfır süreli önbelleğe alınmış ve atlanmış işlemleri içerir.

#### Bazel çağrıları

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `get_bazel_integration_guide` | Kimlik doğrulama, proje kurulumu, Bazel yapılandırması ve doğrulama iş akışını döndürün. | Yok |
| `list_bazel_invocations` | Tamamlanmış [Bazel Build Event Protocol](https://bazel.build/remote/bep) çağrılarını en yeniden eskiye doğru, derleme metrikleri, sınırlı bir yürütme zaman çizelgesi, kritik yol tanılama verileri ve bir proje için ilişkili uzak önbellek toplamlarıyla listeleyin. `status`, `git_branch`, `git_commit_sha`, `is_ci` ve `command` ile filtreleyin. | `account_handle`, `project_handle` |
| `get_bazel_invocation` | Derleme metrikleri, sınırlı bir yürütme zaman çizelgesi, kritik yol tanılama verileri ve ilişkili uzak önbellek toplamları ile tamamlanmış tek bir Bazel çağrısını alın. | `account_handle`, `project_handle`, `invocation_id` |
| `list_bazel_build_steps` | Filtreler ve açık kapsam ile kaydedilmiş Bazel profil aralıklarını listeleyin. | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_build_step` | Kaydedilmiş bir Bazel adımını ve bunun yayınlanan eylem sonucunu ve temizlenmiş günlüğünü inceleyin. | `account_handle`, `project_handle`, `invocation_id`, `step_id` |
| `list_bazel_invocation_logs` | Bir Bazel çağrısı için yakalanan temizlenmiş günlükleri yürütme sırasına göre listeleyin: Bazel'in ilerleme çıktısının sınırlı kuyruğu ve `test.log` yapıtları. İsteğe bağlı `stream` (`stdout` veya `stderr`), `source` (`progress` veya `test_log`), `target_label` ve `errors` filtreleri sonuçları daraltır. | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_invocation_log` | Bir Bazel çağrısı için yakalanan tek bir temizlenmiş günlük parçasını alın. | `account_handle`, `project_handle`, `invocation_id`, `invocation_log_id` |
| `list_bazel_cache_events` | İşlemi, uç noktası ve gözlem zamanı ile ham Bazel uzak önbellek gözlemlerini listeleyin; isteğe bağlı olarak bir çağrı, sonuç veya işlemle daraltılabilir. | `account_handle`, `project_handle` |
| `get_bazel_cache_event` | Tek bir ham Bazel uzak önbellek gözlemini alın. | `account_handle`, `project_handle`, `cache_event_id` |

`list_bazel_invocations` filtreleri tam eşleşmedir ve aynı saniyede biten çağrılar çağrı kimliğine göre sıralanır. Bir dalda en son başarısız olan çağrıyı bulmak için `status: "failure"`, `git_branch` ve `page_size: 1` ile çağırın. REST uç noktası `GET /api/projects/{account_handle}/{project_handle}/bazel/invocations` aynı filtreleri kabul eder.

Test günlükleri, geldikleri test sonucunun `target_label` ve deneme `status` değerlerini taşır, bu nedenle `target_label: "//foo:bar_test"` yalnızca o hedefin test günlüklerini döndürür. `errors: true`, başarısız denemelerin test günlüklerini ve Bazel raporlayıcısının `ERROR:`, `FAIL:` veya `TIMEOUT:` ile başladığı bir satır içeren stderr ilerleme parçalarını döndürür. İlerleme çıktısı hedeflere atanmaz ve atama kaydedilmeden önce yazılan günlüklerin alanları boştur. Başarısız eylemler ve kendi çıktıları `list_bazel_build_steps` üzerinden hedef bazında, test senaryosu bazındaki hatalar ise test çalıştırma araçlarından erişilebilir.

#### Cargo derlemeleri

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_cargo_builds` | Bir proje için Cargo derlemelerini en yeniden eskiye doğru listeleyin. `git_branch`, `status`, `is_ci` veya `command` ile filtreleyin. Cargo test yürütme sonuçları bu derleme listesi üzerinden değil, test araçları üzerinden erişilebilir. | `account_handle`, `project_handle` |
| `get_cargo_build` | Derleme meta verilerini, toplam önbellek sayaçlarını ve tanılama verileriyle birlikte en fazla 500 kaydedilmiş derleyici işini alın. `compilations_truncated` atlanan işleri gösterir; tanılama verileri yalnızca döndürülen işleri kapsar. | `account_handle`, `project_handle`, `build_id` |

Doğrulanmış görev kararlarını ve CAS işlemlerini almak için `get_cargo_build` üzerinde `include_cache_inspection: true` ayarlayın; bu veri 4 MB ile sınırlıdır. Varsayılan olarak ve kayıtlar eksik veya geçersiz olduğunda `cache_inspection` boş değerdir. Kısmi yakalama `truncated` bayrağına saygı gösterin; aktarımlar her görev isabetinin yerel/uzak kökenini belirlemez. HTTP ayrıntı uç noktası aynı sorgu parametresini kabul eder.

#### Mix derlemeleri

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_mix_builds` | Bir proje için Mix (Elixir) derleme derlemelerini, özel meta veriler dahil olmak üzere en yeniden eskiye doğru listeleyin. `git_branch`, `status`, `is_ci` veya `mix_env` ile filtreleyin. | `account_handle`, `project_handle` |
| `get_mix_build` | Derleme meta verilerini, tanılama sayılarını ve bağımlılık önbellek özetini alın. | `account_handle`, `project_handle`, `build_id` |

#### Derleme izleri

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `get_build_trace` | [Perfetto](https://ui.perfetto.dev) içinde açabileceğiniz bir iz dosyası olarak bir Xcode, Gradle, Bazel veya Mix derlemesinin zaman çizelgesi için bir indirme bağlantısı alın. | `account_handle`, `project_handle`, `build_id` |

`build_id`, derleme çalıştırma kimliğidir (Bazel için çağrı kimliği) veya derlemenin pano URL'sidir. Döndürülen `trace_url`, bir [Chrome Trace Event](https://docs.google.com/document/d/1CvAClvFfyA5R-PhYUmn5OOQtYMH4h6I0nSsKchNAySU) JSON dosyası sunar. Bağlantıya sahip olan herkes, çağrıdan bir saat sonra gelen `expires_at` tarihine kadar başka kimlik bilgisi olmadan o derlemenin izini indirebilir. Aracılar bunu `curl` ile indirebilir, Perfetto'da açmanız için size verebilir veya Perfetto'nun `trace_processor` ile sorgulayabilir. İz, paralellik ile şeritlere paketlenmiş kaydedilmiş adımları, tüm derlemeyi kapsayan bir parçayı ve derleme makine metriklerini kaydettiğinde CPU ve bellek sayaçlarını içerir. Günlükler hariç, yukarıdaki adım araçlarıyla aynı veriyi tutar. Pano, her derlemenin Zaman Çizelgesi sekmesinden aynı dosyayı sunar.

#### Once çalıştırmaları

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_once_runs` | Bir proje için Once çalıştırmalarını, en yeniden eskiye doğru listeleyin. `kind` (`build`, `test` veya `generic`), `status`, `is_ci` veya `git_branch` ile filtreleyin. Tamamlanmamış çalıştırmaların durumu `in_progress` olur. | `account_handle`, `project_handle` |
| `get_once_run` | Bir çalıştırmayı, eylem toplamları, önbellek özeti ve test çalıştırmaları için test toplamlarıyla birlikte alın. | `account_handle`, `project_handle`, `run_id` |

Cargo derlemesi, Mix derlemesi ve Once çalıştırma kimlikleri bir proje içinde benzersizdir. Aynı okumalar HTTP API üzerinden `GET /api/projects/{account_handle}/{project_handle}/cargo/builds`, `.../mix/builds` ve `.../once/runs` uç noktalarında mevcuttur; her biri tek bir kimlik için bir ayrıntı uç noktasına sahiptir.

#### Görevler, eylemler, modüller ve dosyalar

Bu proje kapsamındaki araçlar, çalıştırmalar arasındaki kalıcı derleme kimliklerini inceler. `list_build_entities` ile başlayın, ardından döndürülen kararlı `id` değerini aynı `kind` ile birlikte `get_build_entity` veya `list_build_entity_history` uç noktalarına, `account_handle` ve `project_handle` ile birlikte iletin. Derleme veya çağrı kimliği gerekmez.

| Araç | Açıklama | Gerekli parametreler |
| --- | --- | --- |
| `list_build_entities` | Bir projenin derlemeleri arasında görülen tek bir türdeki görevleri, modülleri, eylemleri veya dosyaları listeleyin. | `account_handle`, `project_handle`, `kind` |
| `get_build_entity` | Seçilen dönem için yerel kimliği ve analitik verileriyle birlikte tek bir derleme varlığını alın. | `account_handle`, `project_handle`, `kind`, `id` |
| `list_build_entity_history` | Tek bir derleme varlığının kaydedilmiş yürütmelerini, derlemelerini veya önbellek olaylarını, en yeniden eskiye doğru listeleyin. | `account_handle`, `project_handle`, `kind`, `id` |

| `kind` | Araç zinciri | Geçmiş listeleri |
| --- | --- | --- |
| `bazel_actions` | Bazel eylemleri | BEP tarafından bildirilen eylem yürütmeleri |
| `gradle_tasks` | Gradle görevleri | Görev yürütmeleri |
| `xcode_modules` | Xcode modülleri | Derlemeler ve modül önbelleği olayları |
| `once_actions` | Once eylemleri | Yürütmeler |
| `mix_files` | Mix derlenmiş dosyalar | Derlemeler |
| `mix_modules` | Mix derlenmiş modüller | Derlemeler |
| `cargo_crates` | Cargo paketleri | Kaydedilmiş rustc çağrıları |

Bu araçlar kademeli olarak sunulmaktadır ve yalnızca etkinleştirildiği projeler için veri döndürür; diğer projeler için boş sonuç yerine hata döndürür. Bir tür, yalnızca ilgili derleme araç zincirini kullanan projeler için kullanılabilir. Araçlar sınırlı `start_at`/`end_at` filtrelerini, `environment` (`any`, `ci` veya `local`) ve tam eşleşen `branch` kabul eder. `list_build_entities`, `q` kabul eder; `list_build_entity_history` opak `after`/`before` imleçlerini destekler. Bilinmeyen zamanlama veya önbellek gözlemleri sıfır veya isabetsizlik olarak değil, kullanılamaz olarak kalır. Geçmiş, mevcut çalıştırma araçlarını kullanarak detaylı inceleme için kaydedilen üst öğeyi ve yerel yürütmeyi referans alır.

`get_build_entity` metrikleri, zamanlaması kaydedilmiş gözlem sayısını içeren `duration_samples` değerini içerir: gerçek sıfır süreler sayılır, eksik zamanlama sayılmaz. Bu sayı, gözlem sayısından daha düşük olabilir; kullanılamayan süre istatistikleri boş değer olarak kalır.

Xcode modül süreleri, derleme günlüklerindeki ölçülen hedef derlemelerden gelir. Modül önbelleği çözümleri ve derleme işi olmayan hedefler süre örneklerine katkıda bulunmaz. Derleme gözlemleri Xcode derlemesini referans alır; önbellek olayları oluşturma veya önbellek komutunu referans alır.

Bazel eylemleri, hedef etiketi, anımsatıcı ve yapılandırılmış birincil çıktı ile tanımlanır; girişe bağlı önbellek özetlerine güvenmeden ayrı eylemleri ve yapılandırmaları birbirinden ayırır. Geçmiş, BEP tarafından bildirilen yürütmeleri kaydeder, önbellek aramalarını veya iz profili aşamalarını değil. Tam yürütme kapsamı `--build_event_publish_all_actions` gerektirir; yapıt teslimi en iyi çabayla yapılır, bu nedenle eksik gözlemler iş yapılmadığının kanıtı değildir. Kararlı kimliği veya yürütme başlangıcı olmayan eski Kura yükleri kabul edilir ancak dizine eklenmez. Eksik bitiş zamanı ölçümleri kullanılamaz olarak kalır ve gerçek sıfır süreler sayılır.

Mix modül süreleri, bağımsız olarak ölçülen modül işini değil, kapsayan dosyanın derlenmesini ölçer. Once eylemleri, istemci hedef eşlemelerini bildirdiğinde bildirilen hedef/yetenek/dizin yuvalarını kullanır; yalnızca tanılama etiketleri kararlı kimlikler değildir. Mevcut istemciler ve çalıştırma düzeyi araçları değişmeden desteklenmeye devam eder.

Cargo paketleri, tam olarak kaydedilen paket kökü, adı ve türüne göre gruplanır. Çıkış yolu değişiklikleri geçmişleri bölebilir ve derleme profilleri, özellikler ve hedef üçlüleri ayırt edilmez. Geçmiş, dosya başına işi veya önbellek isabetlerini değil, rustc çağrılarını ölçer; eksik işler kaldırmaları veya tam çalışma alanı envanterini göstermez.

Analitik okumaları sınırlı bellek ve yürütme süresine sahiptir. Bir sorgu bu sınırları aşarsa, araç boş bir sonuç uydurmak yerine hata döndürür.

Yeni gözlemler dağıtımdan sonra dizine eklenir; bu özellik mevcut çalıştırma telemetrisini geriye dönük doldurmaz. Kimlik meta verileri, <.localized_link href="/guides/server/data-retention">veri saklama politikası</.localized_link> kapsamında bireysel gözlemlerden daha uzun süre saklanır.

#### Testler

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_test_runs` | Bir proje için test çalıştırmalarını listeler. `query` alanları `git_branch`, `scheme` ve `status` şeklindedir: `field:"value"` tam eşleşme yapar, `field~"value"` büyük/küçük harfe duyarlı olmayan alt dize eşleşmesi yapar ve baştaki `-` her iki işleci de olumsuzlar. Örneğin, `-git_branch~"gh-readonly-queue"` birleştirme kuyruğu dallarını hariç tutar. Boşlukla ayrılmış sorgu filtreleri ve açık argümanlar AND mantığıyla birleştirilir. | `account_handle`, `project_handle` |
| `get_test_run` | Sonuç paketi (`.xcresult`) ve oturum arşivi için geçici indirme URL'leri dahil olmak üzere bir test çalıştırması için ayrıntılı ölçümleri alır. | `test_run_id` |
| `list_test_module_runs` | Belirli bir test çalıştırması için test modülü çalıştırmalarını listeler. | `test_run_id` |
| `list_test_suite_runs` | Belirli bir test çalıştırması için test paketi çalıştırmalarını, isteğe bağlı olarak modüle göre filtrelenmiş şekilde listeler. | `test_run_id` |
| `list_test_cases` | Bir proje için test senaryolarını listeler (`flaky` gibi filtreleri destekler). | `account_handle`, `project_handle` |
| `get_test_case` | Güvenilirlik oranı, kararsızlık oranı ve çalıştırma sayıları dahil olmak üzere bir test senaryosu için ayrıntılı ölçümleri alır. | `test_case_id` veya `identifier` + `account_handle` + `project_handle` |
| `list_test_case_runs` | Test senaryosu çalıştırmalarını, isteğe bağlı olarak test senaryosuna veya test çalıştırmasına göre filtrelenmiş şekilde listeler. | `account_handle`, `project_handle` |
| `get_test_case_run` | Belirli bir test senaryosu çalıştırması için hata ayrıntılarını ve tekrarlamaları alır. | `test_case_run_id` |
| `list_test_case_run_attachments` | Bir test senaryosu çalıştırması için ekleri listeler. Her ek, geçici bir indirme URL'si içerir. | `test_case_run_id` |
| `list_test_case_events` | Susturma veya atlama gibi bir test senaryosundaki durum değişikliklerini listeler. | `test_case_id` |
| `update_test_case` | Bir test senaryosunun durumunu veya kararsız sınıflandırmasını günceller. Bir değişiklik, harici hizmetler dahil yapılandırılmış webhook uç noktalarına bir olay gönderebilir. | `test_case_id` veya `identifier` + `account_handle` + `project_handle` |
| `list_xcode_test_targets` | Bir test çalıştırması için seçici test hedefi sonuçlarını listeler. | `test_run_id` |
| `get_coverage` | Bir projenin kod kapsamını hedefleriyle birlikte, bir commit'te veya bir dalın en son tamamlanan commit'inde alır. `git_commit_sha` veya `branch` olmadan, varsayılan dalı okur. | `account_handle`, `project_handle` |
| `list_coverage_files` | Bir commit'in kod kapsamının ölçtüğü dosyaları, satır kapsamlarıyla birlikte, bir commit'te veya bir dalın en son tamamlanan commit'inde listeler. `search`, sıralama ve sayfalama desteği sunar. | `account_handle`, `project_handle` |
| `get_coverage_file` | Bir dosyanın kod kapsamını ve fonksiyonlarını, bir commit'te veya bir dalın en son tamamlanan commit'inde alır. Her satırın yürütme sayısını almak için `include_lines` ayarlayın. | `account_handle`, `project_handle`, `path` |

Kod kapsamı araçları, kod kapsamı etkinleştirilmiş hesaplara sunulur.

#### Paketler

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_bundles` | Bir proje için paketleri (uygulama ikili dosyalarını) listeler. İsteğe bağlı olarak `git_branch` ve `tags` ile filtreleyin (tüm etiketler tam eşleşmelidir). | `account_handle`, `project_handle` |
| `get_bundle` | Özel etiketler dahil olmak üzere belirli bir paket hakkında ayrıntılı bilgi alır. | `bundle_id` |
| `get_bundle_artifact_tree` | Bir paketin tam yapıt ağacını, yola göre sıralanmış düz bir liste olarak alır. | `bundle_id` |

`list_bundles`, derleme çeşitlerini veya ortamları ayırt etmek için `tags: ["paid", "production"]` kabul eder. Etiketler; harf, rakam, tire veya alt çizgi içeren, büyük/küçük harfe duyarlı etiketlerdir; etiket başına en fazla 10 etiket ve 50 karakter bulunur. Liste ve ayrıntı sonuçları `custom_metadata.tags` içerir. Sayfalama sayıları ve dal filtreleri etiketlenmiş sonuçlara uygulanır; `tags` atlandığında filtrelanmamış davranış korunur. Geçersiz etiket filtreleri, sorguyu genişletmek yerine hata döndürür.

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
| `list_xcode_module_cache_targets` | Bir oluşturma veya önbellek çalıştırması için modül önbelleği hedeflerini listeler; hedef başına önbellek isabeti/ıska durumu ve ek karma girişleri dahil tanılama bileşeni karmalarını gösterir. | `run_id` |

#### Önizlemeler

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_previews` | Bir proje için paylaşılabilir uygulama önizlemelerini listeler. | `account_handle`, `project_handle` |
| `get_preview` | Bir önizlemeyi ve yapılarının geçici indirme URL'lerini alır. | `preview_id` |
| `get_latest_preview` | Çalışan bir uygulama ikili dosyası için en son önizlemeyi bulur. | `account_handle`, `project_handle`, `binary_id`, `build_version` |

#### Otomasyonlar

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_automation_alerts` | Bir proje için otomasyon uyarılarını listeler. | `account_handle`, `project_handle` |
| `get_automation_alert` | Bir otomasyon uyarısını alır. | `alert_id` |
| `list_automation_alert_revisions` | Bir otomasyon uyarısının revizyon geçmişini listeler. Eylem kimlik bilgileri gizlenir. | `alert_id` |
| `list_project_notification_alerts` | Proje bildirim uyarı kurallarını listeler. Kontrol paneli ayarları sayfasıyla aynı yönetici iznini gerektirir. Webhook adresleri gizlenir. | `account_handle`, `project_handle` |

### Olaylar

Durumsuz `2026-07-28` Model Bağlam Protokolü yaşam döngüsünü kullanan istemciler, olayları ve yük şemalarını keşfetmek için `events/list` çağrısı yapabilir:

| Olay | Gönderilme zamanı | Abonelik filtresi |
|-------|-----------------|---------------------|
| `test_case.marked_flaky` | Bir test senaryosu kararsız olmayan durumdan kararsız duruma geçer. | `account_handle`, `project_handle` |
| `build.failed` | Yerel veya sürekli entegrasyon Xcode, Gradle ya da Bazel derlemesi başarısızlıkla sonuçlanır. | `account_handle`, `project_handle` |
| `test_run.failed` | Yerel veya sürekli entegrasyon test çalıştırması başarısızlıkla sonuçlanır; birleştirilmiş parçalı çalıştırma veya terk edilmiş çalıştırma dahil. | `account_handle`, `project_handle` |
| `ci_job.failed` | Bir Tuist runner işi başarısızlıkla tamamlanır. | `account_handle` |

Abone olmak için istemci, olay adını, yukarıda `arguments` içinde listelenen tanıtıcıları ve `https://` geri çağırma URL'si ile `whsec_` imzalama sırrı içeren bir `webhook` teslimatıyla `events/subscribe` çağrısı yapar. Proje olayları hesap üyeliği ve ilgili test veya derleme verilerine okuma erişimi gerektirir; runner işi olayları hesap üyeliği ve runner okuma erişimi gerektirir. Talep edilmiş [`auth.md`](https://workos.com/auth-md) erişim belirteçleri, talep edilmiş hesap belirteçleri ve tarayıcı yetkilendirme izinleri abonelik oluşturabilir; ilişkili kimlik bilgisi artık etkin olmadığında teslimat durur. Her kullanıcı en fazla 25 etkin abonelik tutabilir. Tuist, aboneliği kaydetmeden önce geri çağırmaya bir doğrulama zorluğu gönderir. Geri çağırma, aynı `challenge` değerini içeren bir nesne döndürmelidir. Abonelik varsayılan olarak yedi gün sürer, tekrar abone olunarak yenilenebilir ve kullanıcının erişimi veya kimlik bilgisi kaldırıldığında teslimat durur. İsteğe bağlı `ttlMs` bir saat ile 30 gün arasında sınırlıdır. Tuist zaman aşımına uğramış bir geri çağırmayı yeniden dener ve beş dakikayı kapsayan en az üç ardışık zaman aşımından sonra aboneliği iptal eder; geri çağırmayı restore ettikten sonra tekrar abone olun.

Bir olay gerçekleştiğinde Tuist, kaynak tanımlayıcısını ve kontrol paneli URL'sini geri çağırmaya gönderir. Derleme ve test çalıştırması hataları ayrıca `is_ci` ve `git_branch` içerir, böylece istemciler yerel hataları yok sayabilir veya dala göre filtreleyebilir. Derleme olayları `build_system` içerir; runner işi olayları hem `workflow_job_id` hem de `workflow_run_id` içerir. İstek, istemcinin kaynağını doğrulayabilmesi için bir abonelik tanımlayıcısı ve [Standard Webhooks](https://www.standardwebhooks.com/) imza başlıkları içerir. Tuist başarısız teslimatları yeniden dener, bu nedenle istemciler yinelemeleri atmak için kararlı `eventId` kullanmalıdır. Yük, test adlarını, günlükleri ve hata mesajlarını içermez; istemci bu ayrıntıları yukarıdaki araçlarla alabilir ve bir ekibi bilgilendirmeye veya hata ayıklamaya başlamaya karar verebilir. İstemciler teslimatı `events/unsubscribe` ile durdurabilir.

### İstemler

| İstem | Açıklama |
|--------|-------------|
| `fix_flaky_test` | Başarısızlık kalıplarını analiz ederek, kök nedeni belirleyerek ve hedefe yönelik bir düzeltme uygulayarak kararsız bir testi düzeltmenize rehberlik eder. |
| `compare_builds` | Performans gerilemelerini, önbellek değişikliklerini ve derleme sorunlarını belirlemek için derlemeleri karşılaştırmanıza rehberlik eder. Xcode, Gradle, Bazel ve Cargo projeleri için yerel araçları kullanır. Cargo karşılaştırmaları kısmi derleyici kapsamını korur ve tahmini derleyici işini geçen süreden tasarruflardan ayırır. |
| `compare_test_runs` | Gerilemeleri, yeni hataları ve kararsız testleri belirlemek için iki test çalıştırmasını karşılaştırmanıza rehberlik eder. |
| `compare_bundles` | Yapıt ağacındaki boyut değişikliklerini belirlemek için iki paketi karşılaştırmanıza rehberlik eder. |
| `compare_test_case` | Bir test senaryosunun davranışını iki dal veya zaman dilimi arasında karşılaştırmanıza rehberlik eder. |
| `compare_generations` | Performans gerilemelerini ve modül önbelleği değişikliklerini belirlemek için iki oluşturma çalıştırmasını karşılaştırmanıza rehberlik eder. |
| `compare_cache_runs` | Önbellek etkinliği değişikliklerini ve hedef düzeyindeki gerilemeleri belirlemek için iki önbellek çalıştırmasını karşılaştırmanıza rehberlik eder. |
| `integrate_gradle_project` | Tuist'i mevcut bir Gradle projesine entegre etmenize rehberlik eder. Ayrı araç ve Gradle kimlik doğrulaması, hesap keşfi, proje oluşturma, uzak önbellek politikası, derleme içgöruları ve geri okuma doğrulamasını içerir. |
| `integrate_bazel_project` | Bir Bazel projesi oluşturmanıza veya seçmenize, komut satırını kimlik doğrulamanıza, uzak önbelleği ve derleme içgörülerini yapılandırmanıza ve entegrasyonu Tuist derleme verileri aracılığıyla doğrulamanıza rehberlik eder. |
| `integrate_xcode_project` | Tuist'i mevcut bir Xcode projesine entegre etmenize rehberlik eder. Xcode önbelleği, derleme içgöruları, test içgöruları ve test parçalama desteği sunar. |
| `ask_tuist` | Bağlam için genel materyalleri ve mevcut davranışın doğruluk kaynağı olarak odaklanmış uygulama ve test kanıtlarını kullanarak bir Tuist sorusunu yanıtlar. Bir `question` gerektirir ve revizyon sabitli kanıtlara atıfta bulunur. |

Proje verisi istemleri, incelemeyi belirli bir projeye daraltmak için `account_handle` ve `project_handle` kabul eder. Karşılaştırma istemleri ayrıca karşılaştırılacak iki öğeyi (ID, kontrol paneli URL'si veya dal adı ile) belirtmek üzere `base` ve `head` bağımsız değişkenlerini kabul eder. `ask_tuist`, proje parametreleri yerine bir `question` kabul eder. `integrate_gradle_project` ayrıca uygulanacak Gradle entegrasyonlarının virgülle ayrılmış bir listesi olan `features` kabul eder: `remote_cache`, `build_insights`, `test_insights`, `flaky_tests` ve `test_sharding`. `integrate_bazel_project`, kendi kendine barındırılan veya yerel kurulumlar için isteğe bağlı bir `server_url` kabul eder. `integrate_xcode_project`, `xcode_cache`, `build_insights`, `test_insights` ve `test_sharding` içeren `features` kabul eder.

#### Gradle entegrasyonu istemi özellikleri

`integrate_gradle_project` istemi ve `get_gradle_integration_guide` aracı, eksiksiz kurulum iş akışını belgeler. Araç ayrıca sunucunun başlatma talimatlarında da referans verilir; bu da istemleri numaralandırmayan ajanlar tarafından keşfedilmesini sağlar.

| Özellik | Ajanın yapılandırdığı şey |
|---------|---------------------------|
| `remote_cache` | Gradle'ın derleme önbelleğini etkinleştirir, Tuist uzak önbellek yükleme politikasını yapılandırır ve yalnızca yerel salt okunur kullanıma sahip sürekli entegrasyon çalıştırıcılarından yüklemeleri önerir. |
| `build_insights` | Tuist Gradle eklentisini uygular ve gerektiğinde derleme analitiği yükleme davranışını yapılandırır. |
| `test_insights` | Gradle `Test` görevi sonuçlarının otomatik olarak yüklenmesi için Tuist Gradle eklentisini uygular. |
| `flaky_tests` | Kararsız test tespiti kurulumuna, isteğe bağlı Gradle Test Retry eklentisi kullanımına ve test karantina yapılandırmasına rehberlik eder. |
| `test_sharding` | `tuistPrepareTestShards` için sürekli entegrasyon iş akışını, parça matrisi oluşturmayı ve `TUIST_SHARD_INDEX` tabanlı test yürütmeyi ekler. |

`features` atlandığında, istem ajandan Gradle projesini düzenlemeden önce kullanıcının hangi entegrasyonları istediğini netleştirmesini veya talepten en küçük faydalı seti çıkarmasını ister.

#### Xcode entegrasyonu istemi özellikleri

`integrate_xcode_project` istemi, Tuist'in desteklediği her Xcode entegrasyonunu belgeler:

| Özellik | Ajanın yapılandırdığı şey |
|---------|---------------------------|
| `xcode_cache` | `tuist setup cache` öğesini, oluşturulan proje önbellek ayarlarını, manuel Xcode önbellek derleme ayarlarını ve yalnızca sürekli entegrasyon çalıştırıcılarıyla sınırlı bir yükleme politikasını yapılandırır. |
| `build_insights` | `tuist inspect build`, `tuist xcodebuild`, `-resultBundlePath` ve `tuist setup insights` aracılığıyla isteğe bağlı makine metriklerini yapılandırır. |
| `test_insights` | `tuist inspect test`, şema test sonrası eylemlerini ve sürekli entegrasyon test çalıştırmaları için sonuç paketi oluşturmayı yapılandırır. |
| `test_sharding` | `TUIST_SHARD_INDEX` ile Xcode veya oluşturulan proje parça planlamasını ve parça yürütme iş akışını ekler. |

`features` atlandığında, istem ajandan Xcode projesini düzenlemeden önce kullanıcının hangi entegrasyonları istediğini netleştirmesini veya talepten en küçük faydalı seti çıkarmasını ister.
