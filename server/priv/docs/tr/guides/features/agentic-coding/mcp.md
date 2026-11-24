---
{
  "title": "Model Context Protocol (MCP)",
  "titleTemplate": ":title · Ajan tabanlı kodlama · Özellikler · Kılavuzlar · Tuist",
  "description": "Yapay zeka ajanlarına Tuist'in MCP uç noktası üzerinden test içgörülerine ve daha fazlasına erişim sağlayın."
}
---
# Model Context Protocol

[Model Context Protocol (MCP)](https://modelcontextprotocol.io/docs/getting-started/intro), yapay zeka ajanlarının harici hizmetler ve veri kaynaklarıyla etkileşime girmesini sağlayan açık bir standarttır. [Claude](https://claude.ai/), [Claude Code](https://docs.anthropic.com/en/docs/claude-code), [Codex](https://developers.openai.com/codex/) gibi uygulamaların ve [Zed](https://zed.dev), [Cursor](https://www.cursor.com) veya [Visual Studio Code](https://code.visualstudio.com) gibi editörlerin Tuist ile birlikte çalışabilmesini sağlar.

Tuist, sunucu tarafında bir Model Context Protocol uç noktasını `https://tuist.dev/mcp` adresinde barındırır. İstemcinizi bu uç noktaya bağlayarak ajanların test içgöruları, kararsız test analizi ve daha fazlası dahil olmak üzere Tuist proje verilerinize erişmesini sağlayabilirsiniz. Çoğu araç, kimliği doğrulanmış kullanıcının panoda zaten görebildiği Tuist verilerini okur. Her araç, salt okunur olup olmadığını, geri alınması zor bir değişikliğe neden olup olamayacağını (`destructiveHint`) ve Tuist dışına erişip erişemeyeceğini (`openWorldHint`) belirten açıklamalar sunar. Durumu değiştiren araçlar, her biri hesabın veya projedeki kullanıcı izinleriyle sınırlı olmak üzere şunlardır:

- **Organizasyonlar ve üyeler**: `create_organization`, `add_organization_member` (mevcut bir kullanıcı ekler veya bir üyenin rolünü değiştirir), `invite_organization_member` (herhangi bir adrese davetiye e-postası gönderir) ve `cancel_organization_invitation`.
- **Projeler**: `create_project`, `start_project_logo_upload` ve `complete_project_logo_upload` (logoyu değiştirir), `connect_project_repository` ve `disconnect_project_repository` (GitHub depo bağlantıları).
- **Testler**: `update_test_case` (bir test senaryosunu sessize alır, atlar, yeniden etkinleştirir veya kararsız olarak işaretler; değişiklik hesabın webhook uç noktalarına ulaşabilir).
- **Bildirim kuralları**: `create_notification_rule`, `update_notification_rule` ve `delete_notification_rule`.
- **Sürekli entegrasyon çalıştırıcıları**: `create_runner_profile`, `update_runner_profile` (hangi işlerin önbellek birimlerini kaydedeceğini daraltmak bekleyen kayıtları iptal eder), `delete_runner_profile` ve `delete_runner_volume` (birimin kaydedilen içeriğini siler).
- **Sandbox'lar**: `create_sandbox`, `pause_sandbox`, `resume_sandbox`, `extend_sandbox`, `archive_sandbox` ve `delete_sandbox` (disklerini siler).
- **Geri bildirim**: `report_feedback` (bir araç veya istem hakkında Tuist ekibine rapor gönderir; yalnızca tuist.dev üzerinde).
- **Organizasyon Yapay Zekası**: `save_organization_ai_model`, `remove_organization_ai_model`, `set_organization_ai_default_model`, `save_organization_ai_task_route`, `remove_organization_ai_task_route` ve `remove_organization_ai_provider` (sağlayıcının anahtarını ve modellerini siler ve Anthropic'te bağlı bir Claude organizasyonunun bağlantısını kaldırır).
- **Ajan entegrasyonları**: `connect_amp_workspace` (çalışma alanının orb'larına hesaba CI erişimi verir), `disconnect_amp_workspace` ve `connect_claude_environment` (Claude Managed Agents ortamının Tuist sandbox'larında oturumlar çalıştırmasına olanak tanır).

`add_organization_member`, `cancel_organization_invitation`, `complete_project_logo_upload`, `disconnect_project_repository`, `update_test_case`, `update_notification_rule`, `delete_notification_rule`, `update_runner_profile`, `delete_runner_profile`, `delete_runner_volume`, `delete_sandbox`, `disconnect_amp_workspace`, `remove_organization_ai_provider`, `remove_organization_ai_model` ve `remove_organization_ai_task_route` mevcut durumu değiştirdiği veya kaldırdığı için `destructiveHint: true` bildirir. `invite_organization_member`, `update_test_case`, `connect_claude_environment`, `remove_organization_ai_provider` ve `report_feedback` e-posta gönderdiği, harici webhook uç noktalarını bilgilendirdiği, Anthropic'i çağırdığı veya Tuist ekibine rapor gönderdiği için `openWorldHint: true` bildirir.

Kişisel Claude ve ChatGPT abonelikleri yalnızca panonun Yapay Zeka ayarlarında bağlanır, bu nedenle abonelik jetonları ve oturum açma işlemleri asla bir Model Context Protocol istemcisinden geçmez. Hesap kurulum araçları kullanıcı kimlik doğrulaması gerektirir. Proje jetonları veya normal hesap jetonları tarafından kullanılamazlar. Bir kullanıcı tarayıcıda bir istemciyi yetkilendirdiğinde veya bir `auth.md` kaydını talep ettiğinde, Tuist bu kimlik bilgisini yalnızca Model Context Protocol uç noktasında kullanıcıyla ilişkilendirir, böylece kurulum araçları istenen iş akışını tamamlayabilir. Herkes bir istemci kaydedebileceğinden, tarayıcıda birini yetkilendirmek istemcinin adını ve erişiminin gönderildiği ana bilgisayarı belirten bir onay sayfası gösterir ve Tuist kimlik bilgisini yalnızca orada onayladıktan sonra verir. Kapsam istemeyen bir istemci `mcp` kapsam grubunu alır. İstemciler `S256` ile PKCE kullanmalıdır ve yönlendirme URI'leri HTTPS, loopback adresinde HTTP veya uygulamanın kendi şemasını kullanmalıdır.

Tuist [2026-07-28 protokolünü](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http) uygular. İstekler durumsuzdur: istemciler protokol meta verilerini her istekle birlikte gönderir ve araçları başlatma olmadan doğrudan çağırabilir. `server/discover` sunucunun kimliğini, yeteneklerini, desteklenen sürümleri ve talimatları döndürür. Oturum tanımlayıcıları veya bağımsız olay akışları yoktur. 2025-06-18 veya 2025-03-26 başlatma akışını kullanan istemciler desteklenmeye devam eder; bunlar da sunucu oturumları olmadan çalışır.

## Model Context Protocol ile beceriler arasındaki fark

Model Context Protocol araçları ve <.localized_link href="/guides/features/agentic-coding/skills">beceriler</.localized_link> yaptıkları iş açısından örtüşebilir. İkisi arasındaki mevcut örtüşme göz önüne alındığında, her iş akışı için tek bir yaklaşım seçin ve aynı akışta ikisini karıştırmak yerine tutarlı bir şekilde kullanın.

Eklenti yüklemeyi destekleyen istemciler için, her ikisini birlikte yüklemek amacıyla <.localized_link href="/guides/features/agentic-coding/plugins">Tuist eklentilerini</.localized_link> kullanın.

## Yapılandırma

İstemcinize uzak bir Model Context Protocol sunucusu olarak `https://tuist.dev/mcp` ekleyin. Sunucunun başlatma talimatları ve genel sunucu kartı, aracıların harici kimlik doğrulama belgelerini almasını veya takip etmesini istemeden, dinamik istemci kaydı ve standart tarayıcı yetkilendirme akışı ile OAuth 2.0'ı satır içinde açıklar. Bu sunucu çapındaki talimatlar iş akışı rehberliğini genel tutar: araç kimlik doğrulaması yerel komut satırı araçlarını veya derleme sistemi entegrasyonlarını kimlik doğrulamaz ve ajanlar istenen değişiklikleri ilgili Tuist araçları aracılığıyla doğrulamalıdır. Derleme sistemine özel kurulum ve kimlik doğrulama kontrolleri entegrasyon kılavuzlarında ve istemlerde belgelenmiştir. Tuist ayrıca hem [Open Authorization](https://oauth.net/2/) keşif meta verilerini hem de mevcut [auth.md protokolünü](https://workos.com/auth-md) ayrı olarak `https://tuist.dev/auth.md` adresinde duyurmaya devam eder.

Organizasyonlarınızdan biri tek oturum açmayı (SSO) zorunlu kılıyorsa, tarayıcıda bir istemciyi yetkilendirmek o organizasyon üzerinden oturum açılmış bir oturum gerektirir ve Tuist gerektiğinde sizi önce sağlayıcıya yönlendirir. Bkz. <.localized_link href="/guides/integrations/authentication/sso#choose-an-enrollment-policy">tek oturum açma</.localized_link>.

Uç nokta, eski oturum tabanlı yaşam döngüsünün yanı sıra, `server/discover` dahil olmak üzere durumsuz `2026-07-28` Model Context Protocol istek yaşam döngüsünü kabul eder. Mevcut istemciler mevcut bağlantı yöntemlerini kullanmaya devam edebilir.

Model Context Protocol olaylarını destekleyen istemciler proje olaylarına abone olabilir. Mevcut olay ve teslimat gereksinimleri için bkz. [Olaylar](#events).

Zaten uzak tarayıcı kimlik doğrulamayı destekleyen istemciler, tarayıcıda kimlik doğrulamaya devam edebilir. `auth.md` destekleyen istemciler ve ajanlar anonim olarak kayıt olabilir, güvenilir bir sağlayıcı kimlik beyanı sunabilir veya hizmetle kimliği doğrulanmış bir e-posta talebi başlatabilir. Kayıt, Tuist tarafından imzalanmış bir kimlik beyanı döndürür; ajan bu beyanı standart jeton uç noktasında bir saatlik erişim jetonu ile takas eder. Tuist genel imzalama anahtarını yayımlar ve standart jeton iptalini ile sağlayıcı güvenlik olayı teslimatını destekler.

Kimliği doğrulanmamış bir ajan, Model Context Protocol uç noktasının döndürdüğü `WWW-Authenticate` başlığını okumalı, korunan kaynak meta verilerini almalı, yetkilendirme sunucusu meta verilerini almalı ve bunun `agent_auth.skill` URL'sini takip etmelidir. Tuist ayrıca yetkisiz yanıt gövdesinde aynı yerel `auth_md` URL'sini döndürür, böylece dil modeli tabanlı istemciler yerel bir istemci entegrasyonuna güvenmeden akışı keşfedebilir. Dağıtım yerel belgesi, uç nokta adları, istek gövdeleri, talep yoklaması ve beyan değişimi için tek doğrudur.

Bir ajan e-posta talebini başlatmadan önce, kullanıcının Tuist hesabı için e-posta adresini onaylamasını istemelidir. Bu adresi bir sağlayıcı profilinden, Git yapılandırmasından, ortam değişkeninden veya oturum meta verilerinden çıkarmamalıdır.

Uç nokta `mcp` kapsam grubunu kullanır. Anonim, talep öncesi bir kimlik bilgisi yetenekleri keşfedebilir ve genel entegrasyon rehberliğini okuyabilir, ancak oturum açmış bir kullanıcı olarak değerlendirilmez. Tarayıcı yetkilendirmesinden veya talepten sonra, kimlik bilgisi kullanıcı kapsamına alınır ve her araç panodakiyle aynı yetkilendirme kontrollerini uygular. Ayrıntılar için <.localized_link href="/guides/server/authentication#scope-groups">kapsam grupları belgelerine</.localized_link> bakın.

Araçlar, kimliği doğrulanmış kullanıcının zaten okuma erişimine sahip olduğu projelere çözülür. Xcode ve Gradle derleme araçları bir derleme UUID'si veya pano URL'si kabul eder. UUID tam olarak bir projeyi tanımlamalıdır; birden fazla projede görünüyorsa, araç başka bir projenin raporunu seçmek yerine bulunamadı döndürür. Proje kapsamındaki pano ve API okumaları kullanılabilir durumda kalır. Bildirilen aktör tanımlayıcıları doğrulanmamış etiketlerdir, kimlik bilgileri veya ek erişim hakları değildir.

Derleme listesi ve ayrıntı araçları isteğe bağlı `tuist_version` meta verilerini sunar: Xcode ve Cargo için raporlayan Tuist CLI, Gradle için Tuist Gradle eklentisi ve Mix için `tuist_ex` kütüphanesi. Xcode ayrıca bağlı proje oluşturma olayından `tuist_generation_version` değerini sunar; bu değer yükleyen CLI'den farklı olabilir. Eksik gözlemler null olarak bildirilir, sunucudan veya başka bir rapordan çıkarılmaz. Bazel mevcut `bazel_version` değerini kullanır; Struo çalıştırma ayrıntıları `once_version` değerini sunar. Bu alanlar bildirilen sürümleri tanımlar, doğrulanmış kimlik veya ağ sözleşmesi sürümlerini değil. REST derleme uç noktaları aynı meta verileri sunar. Mevcut entegrasyon ve kararsız test becerileri sürüm alanlarına bağlı değildir ve iş akışı değişikliği gerektirmez.

Bir müşterinin hesabını inceleyen Tuist operatörleri bunu, her çağrıyı kaydeden Tuist'in dahili operasyon araçları aracılığıyla yapar; bu uç noktaya doğrudan bağlantı, kullanıcının kendi üyelikleri ötesinde hiçbir erişim sağlamaz.

### Pulse

Pulse, hesabın operasyonel metrikleri, günlükleri, izlemeleri ve hataları için salt okunur araçları sunar; tümüne `account_handle` ile erişilir. İlk üçü Pulse sayfalarını ve REST API'lerini yansıtır; diğer beşi bir ajanın telemetriyi doğrudan keşfetmesine olanak tanır ve REST eşdeğeri yoktur:

| Araç | Amaç | `/api/accounts/:account_handle/pulse` altındaki REST eşdeğeri |
| --- | --- | --- |
| `query_pulse` | Pulse sayfa tabloları | `GET /:signal` |
| `get_pulse_analytics` | Pulse sayfa widget'ları | `GET /:signal/analytics` |
| `get_pulse_error_issue` | Bir hata sorunu ve olayları | `GET /errors/issues/:fingerprint` |
| `query_pulse_metrics` | Anlık veya aralık PromQL | Yok |
| `list_pulse_labels` | Etiket adları veya bir etiketin değerleri | Yok |
| `search_pulse_logs` | Filtrelenmiş günlük girdileri | Yok |
| `search_pulse_traces` | Filtrelenmiş kapsamlar | Yok |
| `get_pulse_trace` | Bir izlemenin tüm kapsamları | Yok |

Pulse, bir hesap veya proje herkese açık olsa bile, sunucu tarafından yapılandırılan organizasyonun mevcut üyeleriyle sınırlıdır. Kullanıcı kimlik doğrulaması veya kullanıcıyla ilişkili bir `mcp` kimlik bilgisi ve hesap okuma yetkisi gerektirir. Proje jetonları, normal hesap jetonları, anonim kayıtlar ve organizasyon üyeliği olmayan operatör erişimi Pulse erişimi sağlamaz. Kimlik bilgileri başka bir arka uç veya telemetri kiracısı seçemez ve yalnızca sunucu tarafından yapılandırılan hesap Pulse telemetrisine sahiptir, bu nedenle hiçbir araç başka bir hesabın verilerini okuyamaz. Tarayıcı ajanları bu araçları yalnızca Pulse sayfalarında, o sayfanın hesap kapsamında alır.

REST bir kullanıcı kimlik bilgisi gerektirir. OAuth ve `auth.md` kullanıcı ilişkileri yalnızca `/mcp` uç noktasında kullanılabilir; ilişkili hesabın üyeliği veya görünürlüğünden bağımsız olarak, geçerli bir kullanıcı içermeyen bir hesap kimlik bilgisi reddedilir.

`query_pulse`, `signal` (`metrics`, `logs`, `traces` veya `errors`), isteğe bağlı `query` ve `range` (`15m`, `1h`, `6h` veya `24h`, varsayılan `1h`) parametrelerini alır. Metrikler PromQL ifadelerini kabul eder. Günlükler, izlemeler ve hatalar, günlük gövdeleri, kapsam adları ve hata sorun başlıklarına karşı eşleştirilen büyük/küçük harf duyarsız değişmez metni kabul eder; varsayılan olan `*` her şeyi seçer. İzleme satırları bireysel kapsamlardır. Hata satırları sorunlardır: hizmete ve parmak izine göre gruplandırılmış olaylar, olay sayıları, etkilenen hesaplar, penceredeki ilk ve son oluşum ve en son olaylarının başlığı, sorumlusu, düzeyi ve platformu ile birlikte. Tablolar `search`, `page` (varsayılan `1`), `page_size` (`1`–`100`, varsayılan `20`), `sort_by` ve `sort_order` (`asc` veya `desc`) kabul eder. Sıralama sütunları sinyale bağlıdır ve araç şemasında listelenir. Filtrelere `service` ve günlükler ile hatalar için `level` dahildir. Filtre operatörleri karşılık gelen `_op` argümanını (`eq`, `contains` veya `not_contains`) kullanır; varsayılan olarak tam eşitlik uygulanır.

Sıralama sütunları metrikler için `name`/`value`; günlükler için `timestamp`/`service`/`level`/`message`/`trace_id`; izlemeler için `timestamp`/`service`/`name`/`duration_ms`/`trace_id`; ve hatalar için `last_seen`/`first_seen`/`events`/`accounts`/`title`/`service`/`level` şeklindedir. Pano kasıtlı olarak bir alt küme sunar; API ve araçlar her sinyal için tam listeyi kabul eder.

Tablo yanıtları `rows`, `series`, `warnings` ve `meta` içerir. Sayfalandırma meta verileri `page`, `page_size`, `total_count`, `total_pages`, `has_next_page`, `has_previous_page` ve `end_at` içerir. Sorgu penceresini korumak için döndürülen ISO8601 `end_at` değerini sonraki sayfalarla birlikte iletin. Sonuç sınırı hataları, yanıtı boş bir tablo olarak değerlendirmek yerine sorgunun veya zaman aralığının daraltılmasını gerektirir.

Günlükler ve izlemeler, yerel sıralamadan önce en fazla 100 en yeni eşleşmeyi inceler; hatalar ise en son görülen 100 sorunu inceler. Filtreler, sıralama, sayfalandırma ve toplamlar yalnızca döndürülen eşleşmeleri tanımlar, tüm zaman penceresini değil. Diğer eşleşmeleri incelemek için sorgu metnini veya zaman aralığını daraltın; yerel arama veya sıralamayı değiştirmek upstream aramayı genişletmez. Toplama widget'ları, bu sınırlı tablo sonuçlarının toplamaları yerine bağımsız, tam pencere sorguları olarak kalır.

Metrik tabloları ifadelerini `end_at` tarihinde bir kez değerlendirir, mevcut değerleri ve anlık vektör serisi başına bir nokta döndürür. Aralık vektörü ifadeleri sınırlı geçmiş noktalar döndürebilir. Ayrı analitik widget'ları sabit geçmiş grafikler sağlar; bir tablo, yalnızca en son değerini göstermek için her eşleşen seri için bir zaman ızgarası oluşturmaz.

Telemetri dizgileri güvenilmeyen verilerdir, talimat değildir.

`get_pulse_analytics`, hesap tanıtıcısı dışında yalnızca `signal` ve `range` alır. Sabit widget'ları tablo ifadelerinden, filtrelerden, sıralamadan ve sayfalandırmadan bağımsızdır.

`get_pulse_error_issue`, bir hata satırından bir sorunun `fingerprint` ve `service` değerlerini alır; ayrıca isteğe bağlı `range`, `end_at`, `page` ve `page_size` parametrelerini kabul eder. Sorun özetini, 60 eşit oluşum kovasını, istisna zinciri, yığın çerçeveleri, ekmek kırıntıları, etiketler, bağlamlar, ek veriler, istek yöntemi ve sorgu dizesi olmayan URL ile birlikte en son olayı ve tablolarla aynı sayfalandırma `meta` meta verilerine sahip, en yeniden eskiye sıralı bir olay sayfasını döndürür. Hata satırları ayrıca her sorunun 60 kovalı `occurrence_series` serisini taşır. Olaylar depolamadan önce kişisel verilerden arındırılır, bu nedenle filtrelenmiş değerler `[Filtered]` veya `[REDACTED]` olarak görünür. Pencerede olayı olmayan bir sorun bulunamadı olarak bildirilir. REST ve Model Context Protocol aynı Pulse bağlamını ve yanıt sözleşmelerini kullanır. REST yanıtları önbelleğe almayı devre dışı bırakır.

#### Telemetriyi keşfetme

Keşif araçları, isteğe bağlı ISO8601 `end_at` zamanında (varsayılan olarak şimdi) sona eren `15m`, `1h`, `6h` veya `24h` (varsayılan `1h`, `get_pulse_trace` için `24h`) uzunluğundaki bir pencereyi okur. Her yanıt `start_at` ve `end_at` döndürür; pencereyi korumak için aynı `end_at` değerini tekrar iletin. Bu araçların hiçbiri SQL kabul etmez.

- `query_pulse_metrics`, bir PromQL ifadesi olan `query` değerini `end_at` (`type: instant`, varsayılan) tarihinde veya pencere boyunca her `step` saniyede bir (`type: range`) değerlendirir. Adım varsayılan olarak pencerenin 360'a bölünmesine eşittir ve bundan küçük olamaz, bu nedenle bir seride en fazla 361 nokta olur. Sonuçlarda en fazla 5.000 seri bulunur. Noktalar `[unix_seconds, value]` şeklindedir; `NaN` ve sonsuz değerler dizgidir. Anlık sorgular `range` ve `step` parametrelerini reddeder.
- `list_pulse_labels`, bir `signal` alır. `label` olmadan etiket adlarını listeler; `label` ile o etiketin değerlerini listeler. Metrikler için `__name__` metrik adlarını listeler ve diğer herhangi bir etiketin değerleri `match` gerektirir; bu, `up` gibi bir seri seçicidir. Günlük ve izleme etiketi değerleri `filters` kabul eder; izleme etiket adları izleme şemasından gelir ve bunu yapmaz. Günlük ve izleme değerleri, penceredeki giriş sayılarını içerir; en sık olanlar önce gelir, bu nedenle hizmete göre hatalar gibi ayrıştırmalar olarak da hizmet ederler. `search` yalnızca değişmez metin içeren adları veya değerleri tutar ve `limit` `1`–`1000` (varsayılan `100`) kabul eder. Günlük etiket adı keşfi, her türden en fazla 1.000 farklı özellik kümesini inceler ve yalnızca filtrelerin kabul ettiği anahtarları listeler.
- `search_pulse_logs`, gövdesi `text` içeren ve her filtreyi eşleştiren, `newest` veya `oldest` öncelikli olarak en fazla `limit` girdi (`1`–`100`, varsayılan `50`) döndürür. Her girdi `severity_text`, `body`, `trace_id`, `span_id`, `scope_name` ve birleştirilmiş kaynak ile günlük `attributes` özelliklerini içerir. `span_id` ve `scope_name`, yalnızca OTLP günlük gönderenlerinin ayarladığı Kubernetes'ten toplanan günlükler için `null` değerindedir.
- `search_pulse_traces`, her filtreyi, isteğe bağlı `min_duration_ms` ve `max_duration_ms` ile `root_only` ile eşleşen, `newest`, `oldest` veya `slowest` öncelikli olarak en fazla `limit` kapsam döndürür.
- `get_pulse_trace`, pencerede başlayan `trace_id` kapsamlarını, en eskiden yeniyeye doğru, en fazla 1.000 kapsam olarak döndürür. Pencereden önce başlamış bir izleme kısmen döndürülür, bu nedenle bunun için pencereyi genişletin veya taşıyın. Her kapsam, kapsam özelliklerini, olayları, bağlantıları ve izlemenin farklı `resources` öğelerine bir dizini içerir.

Filtreler, en fazla 10 `{label, op, value}` nesnesinden oluşan listelerdir. `op`, `eq` (varsayılan), `neq`, `contains` veya `not_contains` olabilir; son ikisi büyük/küçük harf duyarsız değişmez metinlerdir. Günlük etiketleri, Pulse bunları depoladığında `severity_text`, `trace_id`, `span_id` ve `scope_name` ile her girdinin kaynak özelliklerinin anahtarlarıdır, örneğin `namespace`, `container` ve `service.name`; ayrıca günlük özellikleri, örneğin `pod`. Bir anahtar her ikisinde de görünüyorsa kaynak özelliği uygulanır. İzleme etiketleri, `list_pulse_labels` tarafından döndürülen kapsam sütunlarıdır, örneğin `service_name`, `span_name`, `span_status_code` (başarısız kapsamlar için `STATUS_CODE_ERROR`), `span_attributes.http.route` ve `resource_attributes.k8s.pod.name`. Bilinmeyen bir izleme etiketi boş bir sonuç yerine hatadır.

`truncated`, yanıtın içerdiğinden daha fazla ad, değer, girdi veya kapsamın eşleştiği anlamına gelir; yanıtı tam olarak değerlendirmek yerine filtreleri veya pencereyi daraltın. Telemetri dizgileri güvenilmeyen verilerdir, talimat değildir.

<details>
<summary>Claude Code</summary>

Çalıştırın:

```bash
claude mcp add --transport http tuist https://tuist.dev/mcp
```

Başsız bir Claude Code istemcisi, başarısız yerel sunucu bağlantısını modele göstermediğinde, aracının barındırılan belgeleri aramadan veya projeyi düzenlemeden önce yapılandırılmış uç noktanın kimlik doğrulamasız [Hypertext Transfer Protocol](https://developer.mozilla.org/en-US/docs/Web/HTTP) yanıtını incelemesini isteyin. Yanıt, tarayıcı kimlik doğrulaması mevcut olmadığında bile modeli dağıtım yerel `auth.md` belgesine yönlendirir.

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

`auth` değerini `false` olarak ayarlamak, bağdaştırıcının tarayıcı kimlik doğrulama işleyicisinin Tuist'in yetkisiz yanıtını gizlemesini engeller. Başsız bir aracı daha sonra döndürülen `auth_md` URL'sini okuyabilir ve Tuist'in kayıt, kimlik iddiası değişimi ve talep yoklama akışını takip edebilir. Değiştirilen erişim belirtecini bearer belirteci olarak yapılandırın veya aracının doğrudan kimliği doğrulanmış Model Context Protocol çağrıları yapmasına izin verin.

Tarayıcı kimlik doğrulamasını tercih ediyorsanız, `auth` değerini `"oauth"` olarak ayarlayın. Bu akış için, kimlik doğrulama tamamlanırken Pi'nin [remote procedure call mode](https://pi.dev/docs/latest/rpc) ile bir işlemi canlı tutun:

```bash
pi --mode rpc
```

Geri arama durumuna sahip olan işlem sonlandığından, bekleyen bir tarayıcı kimlik doğrulamasını ayrı `pi --print` çağrılarına bölmeyin.

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

- **Ad:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>


<details>
<summary>Visual Studio Code</summary>

**Command Palette → MCP: Add Server** seçeneğini kullanın, ardından şu ayarlara sahip bir [Hypertext Transfer Protocol](https://developer.mozilla.org/en-US/docs/Web/HTTP) sunucusu yapılandırın:

- **Ad:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>


<details>
<summary>Zed</summary>

**Agent panel → Settings → Add Custom Server** seçeneğini açın, ardından şunları ayarlayın:

- **Ad:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>

Aracınız `auth.md` destekliyorsa, tarayıcı açmadan anonim olarak başlayabilir. Sağlayıcı kimliği zaten bağlıysa, güvenilir bir sağlayıcı kimliği de tarayıcı olmadan tamamlanabilir. Hizmet tarafından kimliği doğrulanmış e-posta, anonim talep veya ilk sağlayıcı bağlantısı için aracı size bir Tuist doğrulama bağlantısı ve altı haneli bir kod gösterir. Bağlantıyı açın, oturum açın ve Tuist sayfasında aracının kodunu girin. Kodu asla geriye, aracıya göndermeyin. Tuist'in yetkilendirme sunucusu meta verileri, doğrudan dağıtımın kendi `/auth.md` dosyasına işaret eder; bu dosya kesin istek ve yoklama şekillerini içerir.

## Amp orbs ve Claude Code bulut oturumlarında aracılar

Bir Tuist hesabına bağlı alan kutularında çalışan kodlama aracıları, tarayıcı veya kaydedilmiş bir Tuist kimlik bilgisi olmadan, kendi kimlik belirteçleriyle uç noktaya kimlik doğrulaması yapabilir:

- Hesabın **Ayarlar → Entegrasyonlar → Amp** altında bağladığı bir Amp çalışma alanının veya projesinin **Amp orbs** özelliği, orb'un kimlik belirtecini gönderir. Amp'de sunucunun `Authorization` başlığını `Bearer ${amp:id-token}` olarak ayarlayın. Amp, belirteci sunucu URL'sinin kaynağı için basar, bu nedenle URL bu Tuist örneğinin kendi adresi olmalıdır ve süresi dolmadan önce yeniler. Başka bir kaynak için basılan belirteçler reddedilir.
- Bağlı bir Claude Code ortamının **Claude Code cloud sessions** özelliği, Tuist'in onlara `TUIST_OIDC_TOKEN` olarak ilettiği oturum belirtecini gönderir. Başlığı `Bearer ${TUIST_OIDC_TOKEN}` olarak ayarlayın.

Tuist'in Linux alan kutuları sunucuyu sizin için eklemez: Aynı kimlikle oturum açan Tuist CLI'yi ve aracıya sonuçlarını projenin geçmişine karşı ne zaman kontrol etmesi gerektiğini söyleyen bir beceriyi sunarlar. Aracılara MCP araçlarını da sağlamak için, yukarıdaki başlıkla birlikte sunucuyu Amp veya Claude Code ayarlarınıza ya da projenin `.mcp.json` dosyasına ekleyin.

Bu belirteçler, bağlı hesabın her projesine salt okunur erişim sağlar: `mcp` grubunun okuma kapsamlarını taşırlar ve testleri sessize alma veya atlama gibi veri oluşturan, değiştiren veya silen hiçbir kapsamı taşımazlar. Çalışma alanının veya ortamın bağlantısını kesmek, bir sonraki istekte erişimi durdurur ve erişim asla belirtecin kendisinden daha uzun sürmez. Birden fazla Tuist hesabına bağlı bir Amp çalışma alanı reddedilir çünkü belirteci bunlardan birini adlandırmaz. Bir bağlantı eksik olduğunda, yetkisiz yanıtın `error_description` alanı bunu belirtir.

Bu salt okunur erişim yalnızca Model Context Protocol uç noktası için geçerlidir. Aynı alan kutusundaki komut satırı aracı ve derleme sistemi entegrasyonları, bağlantının CI erişimi için belirteci değiştirmeye devam eder.

## WebMCP

[WebMCP](https://webmachinelearning.github.io/webmcp) destekleyen tarayıcılarda, Tuist'in sayfaları araçları `document.modelContext` ile kaydeder, böylece tarayıcıya yerleşik aracılar herhangi bir ek yapılandırma olmadan bunları çağırabilir. Çağrılar Tuist sunucusunda çalışır.

- **Website and documentation pages**, belgeleme ve kaynak araçlarını (`search_tuist`, `search_tuist_code`, `list_tuist_files` ve `read_tuist_file`) kaydeder. Oturum açmanıza gerek yoktur.
- Oturum açtığınızda, **An account's dashboard pages** o hesap için Tuist'in salt okunur araçlarını kaydeder. Her sayfa yalnızca gösterdiği şeyler için, projenin derleme sistemine göre araçları kaydeder: bir Gradle projesinin derlemeler sayfası Gradle derleme araçlarını, test sayfaları test ve kapsam araçlarını, çalıştırıcılar sayfaları çalıştırıcı araçlarını ve alan kutuları sayfaları alan kutusu araçlarını alır. Her sayfa ayrıca belgeleme araçlarını, `list_projects` ve `get_project` araçlarını da alır. Araçlar, oturum açmış kullanıcı olarak çalışır, bu nedenle yalnızca panoda okuyabileceğiniz verilere ve yalnızca baktığınız hesaba erişirler. Başka bir sayfaya veya hesaba geçtiğinizde, araçlar o sayfanın araçlarıyla değiştirilir.

Veri oluşturan, değiştiren veya silen araçlar WebMCP üzerinden kullanılamaz, çünkü bir tarayıcı aracı bu araçları siz eklemeden alır ve derlemeler ile testlerin ürettiği içeriği okur. Bu araçları kullanmak için bir MCP istemcisini `/mcp` uç noktasına bağlayın.

Kuruluş tek oturum açmayı zorunlu kılıyorsa, araçlarını kullanmak için panoya sağlayıcısıyla oturum açın.

## Derleme sistemi entegrasyonları iki kimlik bilgisi kullanır

Model Context Protocol araçları için kullanılan kimlik bilgisi, Gradle eklentisini veya Bazel'in uzak hizmetlerini kimlik doğrulamaz. Bir aracı bir Gradle veya Bazel entegrasyonunu düzenlemeden veya doğrulamadan önce şunu çalıştırmalıdır:

```bash
tuist auth whoami --url https://tuist.dev
```

Bu komut kimlik doğrulaması yapılmamışsa, aracı durmalı ve kullanıcıdan şunu çalıştırmasını istemelidir:

```bash
tuist auth login --url https://tuist.dev
```

Yerel veya kendi kendine barındırılan bir dağıtım için, her iki komuttaki ve `tuist.toml` dosyasındaki URL'yi değiştirin. Ana bilgisayar adının yazımını her yerde aynı tutun. Örneğin, `localhost` ve `127.0.0.1` ayrı kaydedilmiş kimlik bilgileri kullanır.


## Yetenekler

### Araçlar

Aşağıdaki araçlar Tuist Model Context Protocol sunucusu üzerinden kullanılabilir:

Her araç, açık giriş ve çıkış şemalarıyla birlikte insan tarafından okunabilir bir açıklama yayımlar. Başarılı çağrılar, duyurulan çıkış şemasına uyan yapılandırılmış içerik döndürür; ayrıca henüz yapılandırılmış içeriği tüketmeyen istemciler için metin olarak serileştirilmiş aynı sonucu döndürür.

`build_run_id`, `test_run_id`, `test_case_id`, `bundle_id`, `run_id`, `generation_id` veya `cache_run_id` gibi tek bir kaydın tanımlayıcısını alan araçlar, o kaydın Tuist pano URL'sini de kabul eder. Tanımlayıcıyı ayıklamak yerine URL'yi doğrudan tarayıcıdan kopyalayıp yapıştırın.

`get_xcode_build`, `get_test_run`, `get_gradle_build` ve `get_project` araçları `side_quests` içerebilir: projenin kullanmadığı ancak kaydın yardımcı olacağını gösterdiği Tuist yetenekleri. Her birinin bir `id`, dayandığı kanıtı belirten bir `tip` ve bir `docs` bağlantısı vardır. Aracılardan önce kullanıcının isteğini tamamlamaları, geçerli olan yan görevlerden bahsetmeleri ve yalnızca kullanıcı onayladığında bunlardan birini gerçekleştirmeleri istenir. Bunlar yalnızca projenin hesabının üyelerine döndürülür; kullanıcı oturumu, MCP belirteci veya aracı kimliğiyle bağlansalar bile:

| Kimlik | Araç | Önerildiği durum |
|----|------|----------------|
| `xcode_compilation_cache` | `get_xcode_build` | Xcode 26 veya sonraki bir sürümle işlenen temiz bir derleme, önbelleğe alınabilir derleme görevi çalıştırmadı. |
| `gradle_build_cache` | `get_gradle_build` | Bir derleme, Gradle'ın derleme önbelleği bunlardan herhangi biri için bir anahtar hesaplamadan önbelleğe alınabilir görevleri yürüttü; bu, derleme önbelleğinin kapalı olduğu anlamına gelir. |
| `flaky_test_quarantine` | `get_test_run` | Bir çalıştırma kararsız testler içeriyordu ve projede etkinleştirilmiş hiçbir otomasyon bunları sessize almıyor veya atlamıyor. Struo projeleri için önerilmez. |
| `test_sharding` | `get_test_run` | Tuist'in parçalara ayırabildiği bir derleme sisteminde, parçalara ayrılmamış bir CI çalıştırması 10 dakika veya daha uzun sürdü. İpucu, seçici testin ne zaman yaptığına bağlı olarak zaten kaç testi atladığını belirtir. |
| `tuist_runners` | `get_xcode_build`, `get_test_run` | Bir CI çalıştırması GitHub Actions, Bitrise, GitLab CI veya Buildkite makinelerini kullandı ve hesap hiçbir zaman Tuist Runners üzerinde bir iş çalıştırmadı. Yalnızca tuist.dev'de. |
| `pull_request_comments` | `get_xcode_build`, `get_test_run` | Bir GitHub Actions çalıştırması, GitHub deposuna bağlı olmayan bir projeye aittir. |
| `other_build_systems` | `get_project` | Hesap, Tuist'i desteklenen her derleme sistemiyle kullanmıyor. İpucu, diğerlerini tanımlayan dosyaları listeler, böylece aracı depoyu kontrol edebilir. |

#### Belgelendirme ve topluluk araması

Bu salt okunur araç, belgeler web sitesini güçlendiren aynı arama motoru aracılığıyla Tuist'in belgelerini, [uygulama programlama arayüzü](https://en.wikipedia.org/wiki/API) referansını, GitHub sürümlerini, topluluk forumunu ve GitHub sorunlarını arar. Sürüm sonuçları ürünü, sürümü, yayın tarihini ve ön sürüm durumunu içerir. Varsayılan olarak kararlı sürümler aranır ve ön sürümler `include_prereleases` ile dahil edilebilir. Bu araç yalnızca `https://tuist.dev/mcp` adresindeki Tuist tarafından barındırılan sunucuda kullanılabilir.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `search_tuist` | Genel Tuist belgelerini, uygulama programlama arayüzü referansını, GitHub sürümlerini, topluluk tartışmalarını ve GitHub sorunlarını arayın. İsteğe bağlı olarak tek bir `source` (`docs`, `api_reference`, `releases`, `forum`, `issues`) ile sınırlayın. | `query` |

#### Geri bildirim

Aracılar, bir Tuist aracının veya isteminin bekledikleri şekilde çalışmadığı durumlarda (kafa karıştırıcı bir sonuç, hata, eksik veri veya eksik bir yetenek gibi) Tuist ekibine bildirebilir. Aracılardan bir rapor önermeleri ve bunu yalnızca siz onayladıktan sonra göndermeleri istenir. Her rapor, Tuist desteğiyle bir konuşma başlatır; destek ekibi size e-posta ile yanıt verebilir. Bir rapor, aracının beklediği şeyi, olanları, isteğe bağlı bir öneriyi, Tuist kullanıcı kimliğinizi, kullanıcı adınızı ve e-postanızı ile ait olduğunuz kuruluşları içerir. Aracılar ayrıca sorunun gerçekleştiği hesabı ve projeyi de belirtebilir, böylece ekip hangi kuruluşla iletişime geçeceğini bilir; yalnızca ait olduğunuz hesaplar kabul edilir. Raporları yalnızca Tuist kullanıcısı olarak oturum açmış aracılar gönderebilir ve her kullanıcı saatte en fazla 10 rapor açabilir. Bu araç yalnızca `https://tuist.dev/mcp` adresindeki Tuist tarafından barındırılan sunucuda kullanılabilir.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `report_feedback` | Bir Tuist aracı veya istemiyle ilgili bir sorunu bildirin. İsteğe bağlı olarak `tool_name`, gerçekleştiği `account_handle` ve `project_handle` öğelerini belirtin ve bir `suggestion` ekleyin. | `category`, `expected`, `actual` |

#### Kaynak destekli yanıtlar

Bu salt okunur araçlar, aracıların mevcut davranışa bağlı yanıtlar için doğruluk kaynağı olarak barındırılan sunucuyla birlikte dağıtılan kesin genel Tuist kaynak revizyonunu kullanmasına olanak tanır. Yalnızca `https://tuist.dev/mcp` adresinde kullanılabilirler.

Uyumlu istemciler, satır içi OAuth kimlik doğrulama bilgilerinin yanı sıra başlatma sırasında araçların kaynak revizyonuna ilişkin olgusal açıklamaları, bağlantıları ve sonuç sınırlarını alır. Bu açıklamalar yanıt stilini veya bir doğrulama iş akışını belirlemez. Kullanıcılar, önce `ask_tuist` istemini çağırmadan doğrudan bir soru sorabilir; istem, açık kaynak destekli bir iş akışı için kullanılmaya devam eder.

Her işlem için eşzamanlılık, süre, gezinme, okunan bayt ve yanıt boyutu açısından sabit sınırlar vardır. Arama ve listeleme sonuçları `truncated` ve `truncation_reason` alanlarını içerir. Bir sonuç kısaltıldığında, sonucu kapsamlı olarak değerlendirmek yerine yolu, dosya kalıbını veya arama terimini daraltın.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `search_tuist_code` | Kaynak dosyaları arayarak mevcut davranış, varsayılanlar, yapılandırma, özellik kapıları, hata işleme veya belgelenmemiş ayrıntılar hakkındaki soruları yanıtlayın. Sonuçlar çevreleyen satırları, revizyonla sabitlenmiş kaynak bağlantılarını ve tarama istatistiklerini içerir. | `pattern` |
| `list_tuist_files` | İlgili yol bilinmediğinde bir kaynak alt sistemini veya yakındaki testleri keşfedin. Listelemelerin sınırlı derinliği ve sonuç sayıları vardır. | Yok |
| `read_tuist_file` | İlgili yolu bulduktan sonra bir uygulama dosyasındaki, çağrı noktasındaki veya testteki odaklanmış satır aralığını inceleyin. Kısaltılmış yanıtlar, devam etmek için `next_start_line` sağlar. | `path` |

#### Projeler

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_accounts` | Kimliği doğrulanmış kullanıcı için可用的 kişisel ve kuruluş hesap kullanıcı adlarını, her hesabın proje oluşturup oluşturamayacağı dahil olmak üzere listeleyin. | Yok |
| `get_organization` | Bir kuruluşun üye dizinini alın. Bekleyen davetler, gösterge paneliyle aynı yönetici iznini gerektirir; davet kabul jetonları asla döndürülmez. | `account_handle` |
| `create_organization` | Kimliği doğrulanmış kullanıcı için bir Tuist kuruluşu oluşturun. | `handle` |
| `create_project` | Kimliği doğrulanmış kullanıcının erişebileceği bir hesap altında bir Tuist projesi oluşturun. | `account_handle`, `project_handle` |
| `add_organization_member` | Mevcut bir Tuist kullanıcısını bir kuruluşa ekleyin veya mevcut bir üyenin rolünü güncelleyin. `user` (varsayılan), `admin` veya `viewer` kabul eder; burada görüntüleyici panoları ve çalıştırmaları okuyabilir ancak hiçbir şeyi değiştiremez. | `organization_handle`, `email` |
| `invite_organization_member` | Bir e-posta adresini, mevcut bir Tuist kullanıcısına ait olup olmadığına bakmaksızın bir kuruluşa davet edin. Tuist, 14 gün sonra sona eren bir kabul bağlantısı e-postası gönderir; sunucu e-posta gönderemediğinde `email_sent` değeri `false` olur ve bağlantının panodan kopyalanması gerekir. `user` (varsayılan), `admin` veya `viewer` kabul eder. Kuruluş yöneticisi izni gerektirir. | `organization_handle`, `email` |
| `cancel_organization_invitation` | Bekleyen bir kuruluş davetini iptal edin, böylece bağlantısı artık kabul edilemez. Kuruluş yöneticisi izni gerektirir. | `organization_handle`, `email` |
| `list_projects` | Kimliği doğrulanmış kullanıcının erişebileceği tüm projeleri listeleyin. | Yok |
| `get_project` | Bir projenin yapılandırmasını ve bağlı depo URL'sini alın. | `account_handle`, `project_handle` |
| `connect_project_repository` | Bir projeyi, hesabın GitHub Uygulaması yüklemesinin erişebileceği bir GitHub deposuna bağlayın. Proje, deponun varsayılan dalını benimser. Proje yöneticisi izni gerektirir. | `account_handle`, `project_handle`, `repository_full_handle` |
| `disconnect_project_repository` | Bir projenin GitHub deposuna olan bağlantısını kaldırın. Proje yöneticisi izni gerektirir. | `account_handle`, `project_handle` |

#### Hesap jetonları

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_account_tokens` | Jeton değerlerini açığa çıkarmadan hesap jetonu meta verilerini listeleyin. | `account_handle` |
| `get_account_token` | Değerini açığa çıkarmadan hesap jetonu meta verilerini alın. | `account_handle`, `token_id` |
| `list_project_tokens` | Jeton değerlerini açığa çıkarmadan proje jetonu meta verilerini listeleyin. | `account_handle`, `project_handle` |

#### Bildirim kuralları

Bu araçlar, kimliği doğrulanmış kullanıcının kendi bildirim kurallarını yönetir: Yeni bir önizleme gibi bir olay, kuralın projelerinde (veya hiçbiri listelenmediğinde bildirim alabileceğiniz herhangi bir projede) gerçekleştiğinde ve koşullarını karşıladığında, Tuist uygulama cihazlarınıza push bildirimi gibi eylemlerini yürütür. Kurallar olmadan bildirim almazsınız. Kullanıcı kimlik doğrulaması gerektirirler, yalnızca kendi kurallarınız üzerinde işlem yaparlar ve yalnızca ait olduğunuz hesaplara ait projeleri kabul ederler. Kurallar tüm hesaplarınızı kapsadığından gösterge paneli sayfalarında sunulmazlar.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_notification_events` | Kuralların abone olabileceği olay türlerini, her biri için koşullarına ilişkin bir JSON Şemasıyla birlikte listeleyin. | Yok |
| `list_notification_condition_options` | Bir projedeki bir olay için koşul değerleri önerin; örneğin, son önizlemelerinin kanalları ve dalları. | `event`, `account_handle`, `project_handle` |
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
| `get_runner_catalog` | Bir çalıştırıcı profilinin kullanabileceği makine yapılandırmalarını ve Xcode sürümlerini listeleyin. | `account_handle` |
| `create_runner_profile` | Bir platform, bir makine yapılandırması ve macOS üzerinde bir Xcode sürümü ile bir çalıştırıcı profili oluşturun. İsteğe bağlı olarak hangi dalların önbellek birimlerini kaydedeceğini ayarlayın. Hesap yönetimi veya `account:runners:write` kapsamı gerektirir. | `account_handle`, `name`, `platform`, `vcpus`, `memory_gb` |
| `update_runner_profile` | Bir çalıştırıcı profilinin makine yapılandırmasını, Xcode sürümünü veya özel önbellek birimi değişikliklerini hangi dalların kaydedeceğini değiştirin. Atlanmış alanlar değerlerini korur. Hesap yönetimi veya `account:runners:write` kapsamı gerektirir. | `account_handle`, `profile_name` |
| `delete_runner_profile` | Kullanıcı onayından sonra bir çalıştırıcı profilini silin. Varsayılan profiller silinemez. Hesap yönetimi veya `account:runners:write` kapsamı gerektirir. | `account_handle`, `profile_name` |

Çalıştırıcı birim araçları, Birimler gösterge panelindekiyle aynı verileri sunar. Okuma araçları çalıştırıcı erişimi gerektirir; temizleme işlemi hesap yönetimi veya `account:runners:write` kapsamı ve kullanıcı onayı gerektirir.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_runner_volumes` | Birimleri ada ve depoya göre filtreleyin, sıralayın ve sayfalara bölün. | `account_handle` |
| `get_runner_volume` | Depo, platform, kapasite, kullanılan alan ve son kullanım. | `account_handle`, `volume_id` |
| `list_runner_volume_jobs` | Sayfalara bölünmüş iş ve iş akışı referansları, önbellek durumu, isabet sonucu ve bağlama süresi. | `account_handle`, `volume_id` |
| `list_runner_job_volumes` | Bir iş tarafından bağlanan birimler. | `account_handle`, `workflow_job_id` |
| `get_runner_volume_analytics` | Depolama serileri, iş çalıştırmaları, isabet oranı ve eğilimler. İsteğe bağlı `volume_id`, `start` ve `end` (ISO 8601); varsayılan yedi gün, maksimum 90. | `account_handle` |
| `delete_runner_volume` | Bir birimi ve kaydedilen içeriğini silin. Çalışan işler özel kopyalarını tutar ancak bunları kaydedemez; aynı anahtara sahip sonraki işler boş başlar. | `account_handle`, `volume_id` |

Listeler `page` ve `page_size` (en fazla 100) kabul eder. Birim envanteri ayrıca `name` ve `repository` (tam eşleşmeler, AND ile birleştirilmiş), `sort_by` (`volume`, `repository`, `used_space`, `capacity`, `last_used`) ve `sort_order` (`asc`, `desc`) kabul eder. Bilinmeyen ölçümler ve isabet sonuçları `null` olarak kalır. Önbellek durumu, birim değişikliklerinin kaydedilip kaydedilmediğini açıklar, iş başarısını değil.

#### Sanal ortamlar

Sanal ortam araçları, Sanal Ortamlar gösterge panelindekiyle aynı verileri ve eylemleri, [API](https://tuist.dev/api/docs) ile aynı erişimle sunar: hesap üyeleri hesaptaki her sanal ortamda her aracı kullanabilir. Salt okunur görüntüleyiciler bunları kullanamaz. Hesabın sanal ortamların etkinleştirilmiş olması gerekir. Gösterge panelinin sanal ortam sayfaları salt okunur araçları kaydeder.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_sandboxes` | Sanal ortamları durumları, yapılandırmaları ve zaman damgalarıyla sayfalara bölün. İsteğe bağlı `search` (sanal ortamdaki metin, Amp Orb veya Anthropic oturum kimliği), `status`, `vcpus`, `sort_by` (`created`, `last_active`, `identifier`) ve `sort_order`. | `account_handle` |
| `get_sandbox` | Bir sanal ortamın durumu, yapılandırması, düğümü, arşivi ve zaman damgaları. | `account_handle`, `sandbox_id` |
| `get_sandbox_analytics` | vCPU-saatleri, oluşturulan sanal ortamlar, oturum, kurulum ve başlama süreleri ve hesabın sınırlarına göre tepe vCPU'lar, bellek ve disk, eğilimlerle birlikte. İsteğe bağlı `start` ve `end` (ISO 8601); varsayılan 30 gün, maksimum 90. | `account_handle` |
| `create_sandbox` | Boş bir sanal alanı başlatın ve çalışmaya başladığında döndürün. İsteğe bağlı `platform` (`linux` veya `darwin`), `xcode_version` (bir macOS sanal alanının tam Xcode sürümü; aracın açıklamasında listelenenlerden; `darwin` anlamına gelir), `repository` (bir macOS sanal alanının github.com `owner/name`, hesabın projelerinden birine bağlı: Bir Linux Claude Code ortamında bir macOS kurulum betiği olduğunda Mac <.localized_link href="/guides/features/sandboxes/claude#remote-mac-snapshots">hazır anlık görüntüsünden</.localized_link> önyüklenir), `template`, `vcpus` ile `memory_mb` (Linux: 2x4096, 4x8192 veya 8x16384, varsayılan 2x4096; macOS: 8x8192, 8x16384 veya 8x24576, varsayılan 8x8192) `workspace_gb` ve `lifetime_seconds` (çalışan komutları iptal edilip duraklatılıp arşivlenmeden önce ne kadar süre çalışabileceği, dosyalarını koruyarak: varsayılan olarak iki saat, en fazla bir gün). Açıklaması, aracıya deponun kullandığı Xcode'u bulmasını (`.xcode-version`, mise, CI yapılandırması veya belgeler) ve bunu iletmesini söyler, çünkü başka bir Xcode deponun önbelleklerini ve anlık görüntüsünü kaçırır ve Mac'in `/opt/tuist/agent-guide.md` konumunda taşıdığı kılavuzu okumasını sağlar. Mac'teki Tuist, depo bir sürüm sabitlediğinde o sabitlenen sürümü kullanır ve <.localized_link href="/guides/features/sandboxes#tuist-in-sandbox">hesabın önbelleğini</.localized_link> kendi başına kullanır. | `account_handle` |
| `pause_sandbox` | Çalışan bir sanal ortamın anlık görüntüsünü düğümünün diskine alın. | `account_handle`, `sandbox_id` |
| `resume_sandbox` | Duraklatılmış veya arşivlenmiş bir sanal ortamı devam ettirin. | `account_handle`, `sandbox_id` |
| `extend_sandbox` | Bir sanal ortamın yaşam süresini şimdi yeniden başlatın, isteğe bağlı `lifetime_seconds` ile (en fazla bir gün). Bir entegrasyonun sahibi olduğu sanal ortamların yaşam süresi yoktur. | `account_handle`, `sandbox_id` |
| `archive_sandbox` | Duraklatılmış bir sanal ortamın disklerini nesne depolamaya taşımayı sıraya alın. | `account_handle`, `sandbox_id` |
| `delete_sandbox` | Kullanıcı onayından sonra bir sanal ortamı ve disklerini silin. | `account_handle`, `sandbox_id` |

Bir sanal ortam aracının hatası, kendi satırında `code: fleet_busy` gibi kararlı bir kodla başlar, ardından ne yapılacağı gelir; bekleme içeren kodlar bir `retry_after_seconds:` satırı ekler. API, hata gövdesinde aynı `code` kodunu gönderir. Her ana bilgisayar meşgul olduğunda, `create_sandbox` yanıt vermeden önce `fleet_busy` cevabını alana kadar en fazla 25 saniye bekler.

#### Amp çalışma alanları

Bu araçlar, orb'ların jeton olmadan Tuist'e oturum açmasına olanak tanıyan <.localized_link href="/guides/server/authentication#amp-orbs">Amp çalışma alanı bağlantılarını</.localized_link> yönetir. Gösterge panelinin Entegrasyonlar sayfasıyla aynı yalnızca yönetici iznini kullanırlar. Bir orb'daki bir ajan, kendi kimliklerini `$AMP_WORKSPACE_ID` ve `$AMP_PROJECT_ID` üzerinden okuyabilir. Bir bağlantının kabul ettiği her orb, hesaptaki tüm projelere CI erişimi kazanır, bu nedenle ajanlar bağlantı kurmadan önce kullanıcıyla onaylamalıdır.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_amp_workspace_connections` | Hesabın bağlı Amp çalışma alanlarını ve her birinin sınırlandırıldığı projeyi, varsa listeleyin. | `account_handle` |
| `connect_amp_workspace` | Bir Amp çalışma alanını bağlayın. İsteğe bağlı `project_id`, oturum açmayı tek bir Amp projesinin orb'larıyla sınırlar. | `account_handle`, `workspace_id` |
| `disconnect_amp_workspace` | Bir çalışma alanının bağlantısını kesin. Orb'larının zaten sahip olduğu oturumlar, süresi dolana kadar geçerli kalır. | `account_handle`, `connection_id` |

#### Claude ortamları

Bu araçlar, Claude Managed Agents kendi kendine barındırılan ortamlarını bağlar, böylece Ayarlar → Entegrasyonlar → Claude'da olduğu gibi oturumları Tuist sanal ortamlarında çalışır. Hesap yöneticiliği ve sanal ortamların etkinleştirilmesini gerektirirler. Bir ajan, Anthropic'in API'si ile ortamı oluşturabilir, ancak ortam anahtarını yalnızca Claude Konsolu üretir, bu nedenle ajan kullanıcıdan bunu ister. Tuist, bir Anthropic API anahtarı veya iş yükü kimlik federasyonu ile oturumları başlatır ve kaydetmeden önce o kimlik bilgisiyle ortamı getirir. Anthropic tarafındaki kurulum kullanıcının kendi Anthropic kimlik bilgilerini kullanır; Tuist bunları asla almaz. Anahtarlar istemci ve model üzerinden geçtiğinden, bunları yalnızca açıkça sağlayın.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_claude_environments` | Bağlı ortamları ve her birinin kullandığı kimlik bilgisini, ayrıca bir federasyon kuralının güvenmesi gereken veren URL'sini ve konu önekini listeleyin. | `account_handle` |
| `connect_claude_environment` | Bir ortamı `api_key` ile veya `organization_id`, `workspace_id`, `service_account_id` ve `federation_rule_id` ile bağlayın. İsteğe bağlı `platform`, `vcpus` ve `memory_mb` sanal ortamın şeklini belirler. | `account_handle`, `environment_id`, `environment_key` |

#### Organizasyon Yapay Zekası

Bu araçlar, Ayarlar → Yapay Zeka'da olduğu gibi bir organizasyonun sunucu tarafı yapay zeka görevlerinin kullandığı modelleri yönetir ve aynı kuralları paylaşır: yalnızca organizasyon yöneticileri için ve yalnızca yapay zeka ayarlarına sahip organizasyonlar içindir. Her görev, örneğin `pulse_grouping` veya `pulse_explanation`, bir görev rotası varsa onu kullanır, aksi takdirde varsayılan modeli kullanır; ikisi de yoksa hiçbir istek göndermez. Her araç, her görevin mevcut modelini ve bunun rotasından mı, varsayılandan mı yoksa hiçbir yerden mi geldiğini içeren tüm yapılandırmayı döndürür. Bir sağlayıcı eklemek veya düzenlemek bir API anahtarı gerektirdiğinden, bu işlem gösterge panelinde veya REST API'sinde (`/api/accounts/{handle}/ai`) yapılır, bu araçlar aracılığıyla değil.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `get_organization_ai_configuration` | Sağlayıcıları (anahtarlar olmadan), modelleri, varsayılan modeli, görev rotalarını ve her görevin mevcut modelini okuyun. | `account_handle` |
| `save_organization_ai_model` | Bir model ekleyin (`name`, `provider_id`, `upstream_model_id`), veya `id` ile birini güncelleyin. | `account_handle` |
| `remove_organization_ai_model` | Bir modeli ve onun görev rotalarını kaldırın. | `account_handle`, `model_id` |
| `set_organization_ai_default_model` | Varsayılan modeli seçin veya null ile temizleyin. | `account_handle`, `model_id` |
| `save_organization_ai_task_route` | Bir `task` görevini yapılandırılmış bir `model_id` modeline yönlendirin veya `id` ile bir rotayı güncelleyin. Bir görevin en fazla bir rotası olabilir. | `account_handle` |
| `remove_organization_ai_task_route` | Bir rotayı kaldırın, böylece görev tekrar varsayılan modeli kullanır. | `account_handle`, `route_id` |
| `remove_organization_ai_provider` | Anahtarı, modelleri ve onların rotalarıyla birlikte bir sağlayıcıyı kaldırın; bağlı bir Claude organizasyonunun bağlantısını keser. | `account_handle`, `provider_id` |

#### Webhook'lar

Webhook araçları, gösterge paneliyle aynı yalnızca yönetici iznini kullanır. Teslimat denemeleri, uç nokta için kaydedilen istek ve yanıt verilerini içerir, ancak uç nokta imzalama gizli anahtarını asla içermez.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_webhook_endpoints` | Bir hesap için webhook uç noktalarını listeleyin. | `account_handle` |
| `get_webhook_endpoint` | Bir webhook uç noktasını alın. | `account_handle`, `webhook_endpoint_id` |
| `list_webhook_delivery_attempts` | Bir uç nokta için teslimat denemelerini listeleyin. | `account_handle`, `webhook_endpoint_id` |
| `get_webhook_delivery_attempt` | Bir teslimat denemesini alın. | `account_handle`, `webhook_endpoint_id`, `delivery_attempt_id` |

#### Xcode derlemeleri

Xcode, Gradle, Bazel, Mix ve Cargo için derleme detay araçları, raporlandığında altyapı gözlemleri dahil olmak üzere mevcut `custom_metadata: {tags, values}` yapısını ortaya çıkarır. Değerler dize olarak kalır ve bilinmeyen anahtarlar korunur. Örneğin, `tuist.cpu.available_processors` çalışma zamanında kullanılabilir mantıksal işlemcileri tanımlarken, `tuist.gradle.max_workers` bir Gradle işçi sınırıdır ve `tuist.jvm.max_heap_bytes` bir JVM yığın sınırıdır, ana bilgisayar belleği değildir. Bunlar güvenilmeyen istemci gözlemleridir, doğrulanmış çalıştırıcı kimlikleri değildir. Eksik gözlemler eksik kalır; içe aktarılan günlükler ve daha eski istemcilerde altyapı meta verileri olmayabilir. Struo meta verileri koordineli bir istemci/protokol güncellemesini bekliyor.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_xcode_builds` | Bir proje için Xcode derleme çalıştırmalarını listeleyin. | `account_handle`, `project_handle` |
| `get_xcode_build` | Ham `.xcactivitylog` dosyasını içeren arşiv için geçici bir indirme URL'si dahil olmak üzere belirli bir Xcode derleme çalıştırması hakkında ayrıntılı bilgi alın. | `build_run_id` |
| `list_xcode_build_targets` | Belirli bir Xcode derleme çalıştırması için derleme hedeflerini listeleyin. | `build_run_id` |
| `list_xcode_build_files` | Belirli bir Xcode derleme çalıştırması için derlenmiş dosyaları listeleyin. | `build_run_id` |
| `list_xcode_build_steps` | Günlük metni olmadan, zamanlamalar ve sonuçlarla kaydedilmiş derleme adımlarını listeleyin. | `build_run_id` |
| `get_xcode_build_step` | Günlüğü ve kırpma bayrağı dahil olmak üzere tek bir kaydedilmiş derleme adımını alın. | `build_run_id`, `step_id` |
| `list_xcode_build_issues` | Belirli bir derleme çalıştırması için derleme sorunlarını (uyarılar ve hatalar) listeleyin. | `build_run_id` |
| `list_xcode_build_cache_tasks` | Belirli bir Xcode derleme çalıştırması için önbelleklenebilir görevleri (önbellek isabetleri/kaçırmaları) listeleyin. | `build_run_id` |
| `list_xcode_build_cas_outputs` | Belirli bir Xcode derleme çalıştırması için [içerik adreslenebilir depolama](https://en.wikipedia.org/wiki/Content-addressable_storage) çıktılarını listeleyin. | `build_run_id` |

`list_xcode_build_steps` varsayılan olarak 20 adımdan oluşan sayfalar döndürür (`page_size` ile maksimum 100), gezinme için `page` ve `pagination_metadata` sağlar. Başlıkları, projeleri veya hedefleri eşleştirmek ya da tam `project`, `target`, `category` (örneğin, `swiftCompilation`) ve `status` (`success` veya `failure`) değerlerini filtrelemek için `search` kullanın. En yavaş olanı önce getirmek için `duration_ms` ile veya kronolojik sıra için `start_ms` ile sıralayın. Adım kimlikleri beraberlikleri bozar ve 64 bitlik hassasiyetlerini korumak için ondalık dizeler olarak döndürülür. Kimlikler bir derlemeye özeldir ve derlemeler arasında eşleştirilmemelidir.

İsteğe bağlı `start_ms` ve `end_ms`, derleme başlangıcından itibaren milisaniye cinsinden bir zaman aralığıyla örtüşen adımları seçer; bitiş hariçtir. Her iki araç da `build_run_id` olarak bir derleme UUID'sini veya gösterge paneli URL'sini kabul eder. Günlüğünü almak için döndürülen adım `id` değerini `step_id` olarak değiştirilmeden iletin. Günlükler adım başına en fazla 64 KiB tutar ve `log_truncated` atlanan çıktıyı belirtir.

Xcode derlemeleri işlendiğinde adımlar varsayılan olarak toplanır. Kaydedilen adım verileri 90 gün boyunca saklanır. Liste yanıtı `availability` içerir: filtreler hiçbirini eşleştirmese bile kaydedilmiş adımlar varsa `available`; derleme hala işleniyorsa ve henüz adımı yoksa `processing`; veya adımlar kaydedilmediyse ya da süresi dolduysa `unavailable`.

Aynı işlemler, aynı filtreler ve sayfalama ile `GET /api/projects/{account_handle}/{project_handle}/xcode/builds/{build_id}/steps` ve `GET /api/projects/{account_handle}/{project_handle}/xcode/builds/{build_id}/steps/{step_id}` HTTP API uç noktalarında mevcuttur. Her ikisi de derlemenin projesine okuma erişimi gerektirir.

#### Gradle derlemeleri

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `get_gradle_integration_guide` | Tam kimlik doğrulama, proje kurulumu, Gradle eklentisi, önbellek politikası ve iki derlemeli doğrulama iş akışını döndürün. Aracılar, mevcut bir Android veya Gradle projesini düzenlemeden önce bunu çağırmalıdır. | Yok |
| `list_gradle_builds` | Özel meta veriler dahil olmak üzere bir proje için Gradle derleme çalıştırmalarını listeleyin. İsteğe bağlı `tag` parametresi ile özel bir etikete göre filtreleyin. | `account_handle`, `project_handle` |
| `get_gradle_build` | Derleme meta verilerini, görev/önbellek sayılarını ve `failures` öğelerini alın: başarısız olan her görevin ve yapılandırma adımının hata mesajı. | `build_run_id` |
| `list_gradle_build_tasks` | Görev sonuçlarını, bileşik derleme kimliğini, önbelleklenebilirliği, artımlı durumu ve hata mesajlarını listeleyin. | `build_run_id` |
| `list_gradle_build_steps` | Arama, meta veri ve örtüşen zaman filtreleriyle zamanlanmış görevleri, yapılandırmaları ve dönüşümleri listeleyin. | `build_run_id` |
| `get_gradle_build_step` | Opak kimliğe göre kaydedilmiş adım meta verilerini inceleyin; başarısız bir görevin veya yapılandırma adımının `log` değeri onun hata mesajıdır. | `build_run_id`, `step_id` |

Gradle ve Bazel adım listeleri varsayılan olarak 20 sonuç döndürür (maksimum 100), `search`, tam `project`, `target`, `category` ve `status`, örtüşen `start_ms` / `end_ms` filtrelerini (bitiş hariç) ve `duration_ms` veya `start_ms` sıralamasını destekler. Döndürülen kimlikleri değiştirilmeden iletin; bunlar derlemelerine özeldir. Listeler `time_origin` ve `coverage` sunar. Daha eski Gradle raporları, derleme başlangıcı yüklenmediği için `first_recorded_timestamp` kullanır. Bazel profilleri, tüm kaydedilen aralıkları `trace_profile` kapsamı ve zaman kökeni olarak `profile_start` ile ortaya çıkarır. Daha eski derlemeler, saklanan BEP özetlerine geri döner. Kaynak kayıtlar 90 gün sonra sona erer. Bazel ayrıntıları, yayınlandığında sanitize edilmiş eylem günlüklerini içerir. Başarısız bir görevin veya yapılandırma adımının Gradle ayrıntıları, Tuist Gradle eklentisinin `log` olarak bildirdiği hata mesajını içerir: istisna mesajı ve neden zinciri, Gradle konsolunun yazdırdığı gibi, yığın izleri veya görev çıktısı olmadan, proje içindeki yollar göreceli hale getirilmiş ve kimlik bilgileri ile diğer yerel yollar sansürlenmiş şekilde, adım başına en fazla 16 KiB ve derleme başına 32 başarısız adım. Diğer Gradle adımları, daha eski eklenti sürümleri tarafından bildirilen derlemeler ve kimlik bilgisi içermeyen raporlar null `log` değerine sahiptir. Yapılandırma adımları başarısız olduklarında `failure` ve aksi takdirde `unknown` bildirir. `compare_builds` istemi, bu kapsamı tam Bazel izlerini saklanan özetlerden ayırt etmek için kullanır ve aracıları, daha geniş çağrı çıktısını kontrol etmeden önce eylem sonuçları ve günlükler için adım ayrıntılarına yönlendirir.

Tek adımlı araçlar `get_gradle_build_step` ve `get_bazel_build_step` bir adımı kimliğine göre alır ve zaman filtrelerini kabul etmez; adımları zaman aralığına göre filtrelemek için karşılık gelen liste araçlarını kullanın.

Saklanan özetlerden döndürülen Bazel adım kimlikleri, listeleme ve bir adımı getirme arasında tam bir profil gelirse okunabilir kalır. Adım verilerinin süresi dolmuş indekslenmiş bir profil, kullanılamaz olarak bildirilir. Gradle adım listeleri, sıfır süreli önbelleklenmiş ve atlanan işlemleri içerir.

#### Bazel çağrıları

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `get_bazel_integration_guide` | Kimlik doğrulama, proje kurulumu, Bazel yapılandırması ve doğrulama iş akışını döndürün. | Yok |
| `list_bazel_invocations` | Bir proje için derleme metrikleri, sınırlı bir yürütme zaman çizelgesi, kritik yol tanılama ve ilişkili uzak önbellek toplamları ile tamamlanmış [Bazel Build Event Protocol](https://bazel.build/remote/bep) çağrılarını en yeniden eskiye doğru listeleyin. `status`, `git_branch`, `git_commit_sha`, `is_ci` ve `command` ile filtreleyin. | `account_handle`, `project_handle` |
| `get_bazel_invocation` | Derleme metrikleri, sınırlı bir yürütme zaman çizelgesi, kritik yol tanılama ve ilişkili uzak önbellek toplamları ile tamamlanmış tek bir Bazel çağrısını alın. | `account_handle`, `project_handle`, `invocation_id` |
| `list_bazel_build_steps` | Filtreler ve açık kapsam ile kaydedilmiş Bazel profil aralıklarını listeleyin. | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_build_step` | Kaydedilmiş bir Bazel adımını ve yayınlanan eylem sonucunu ve sanitize edilmiş günlüğünü inceleyin. | `account_handle`, `project_handle`, `invocation_id`, `step_id` |
| `list_bazel_remote_actions` | Tuist uzaktan yürütmenin bir çağrı için çalıştırdığı eylemleri mnemonic, hedef, eylem özeti, çıkış kodu, yürütme yolu ve faz zamanlamaları ile listeleyin. İsteğe bağlı `sort_by` (`duration` veya `queued_at`), `failed` ve `mnemonic` filtreleri. | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_remote_action` | Tek bir uzaktan eylemin argv, ortam (gizli görünen değerler maskelenmiş), platform, çalışma dizini, çıktı yolları, işçi, çıkış kodu, stdout ve stderr'in ilk 16 KiB'si, stderr'de tanınan derleyici `errors`, faz zamanlamaları ve eylem özetini alın. | `account_handle`, `project_handle`, `invocation_id`, `action_id` |
| `get_bazel_remote_action_log` | Bayt ofsetine göre bir uzaktan eylemin stdout veya stderr'inden en fazla 64 KiB okuyun, varsayılan olarak akışın sonuna kadar. Uzun akışlar tamamen kopyalanır veya daha uzun olduklarında ilk 16 KiB ve son 16 MiB korunur; `recorded` mevcut aralıkları listeler. | `account_handle`, `project_handle`, `invocation_id`, `action_id`, `stream` |
| `list_bazel_invocation_logs` | Bir Bazel çağrısı için yakalanan sanitize edilmiş günlükleri yürütme sırasına göre listeleyin: Bazel'in ilerleme çıktısının sınırlı kuyruğu ve `test.log` yapıtları. İsteğe bağlı `stream` (`stdout` veya `stderr`), `source` (`progress` veya `test_log`), `target_label` ve `errors` filtreleri sonuçları daraltır. | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_invocation_log` | Bir Bazel çağrısı için yakalanan tek bir sanitize edilmiş günlük parçasını alın. | `account_handle`, `project_handle`, `invocation_id`, `invocation_log_id` |
| `list_bazel_cache_events` | İşlemi, uç noktası ve gözlem zamanı ile ham Bazel uzak önbellek gözlemlerini listeleyin; isteğe bağlı olarak bir çağrı, sonuç veya işlemle daraltılabilir. | `account_handle`, `project_handle` |
| `get_bazel_cache_event` | Tek bir ham Bazel uzak önbellek gözlemini alın. | `account_handle`, `project_handle`, `cache_event_id` |

#### Uzaktan yürütme

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `get_remote_execution_activity` | Projenin çalışan Bazel çağrılarını ve şu anda çalışan veya sıraya alınmış uzak eylemlerini, her bir eylemin çağrısı, mnemonic'i, hedefi, eylem özeti, makine boyutu ve bu duruma girdiği zaman ile birlikte listeleyin. Yürütme ağ geçidinin önceden hazırladığı bir VM üzerinde çalıştırdığı eylemler tamamlanana kadar listelenmez. | `account_handle`, `project_handle` |
| `get_remote_execution_usage` | Projenin uzaktan yürütmelerini ve `[from, to)` aralığında ölçülen yürütme süresini toplamda, makine boyutuna göre, dağıtım moduna göre ve saat, gün veya ay bazında alın. Dönem varsayılan olarak son 30 gündür ve en fazla 366 günü kapsar. | `account_handle`, `project_handle` |

`list_bazel_invocations` filtreleri tam eşleşmedir ve aynı saniyede tamamlanan çağrılar çağrı kimliğine göre sıralanır. Bir dalda en son başarısız olan çağrıyı bulmak için `status: "failure"`, `git_branch` ve `page_size: 1` ile çağırın. REST uç noktası `GET /api/projects/{account_handle}/{project_handle}/bazel/invocations` aynı filtreleri kabul eder.

Dizinlenmiş profillerden güvenli bir şekilde ilişkili sunucu faz zamanlamalarına sahip yalnızca eylemleri döndürmek için `list_bazel_build_steps` üzerinde `remote_execution: true` ayarlayın. Liste ve ayrıntı yanıtları isteğe bağlı null değer alabilen `remote_queue_ms`, `remote_input_fetch_ms`, `remote_execution_ms` ve `remote_output_upload_ms` alanlarını sunar. Değerler, eylem içindeki yeniden denemeler dahil olmak üzere kaydedilen fazların toplamıdır; eksik veya null değerler sıfır değil, kullanılamaz anlamına gelir. Bunlar profil gözlemleridir, faturalandırılabilir kullanım veya yeni yürütme kanıtı değildir, çünkü önbelleğe alınmış sunucu sonuçları yürütme meta verilerini taşıyabilir. İstemci yüklemeleri hariç tutulur. Daha eski veya belirsiz profiller, uzaktan iş gerçekleşmiş olsa bile eşleşen eylem döndürmeyebilir. Adım REST uç noktası aynı `remote_execution=true` filtresini kabul eder. Panonun Uzaktan yürütme sekmesi aynı sorguyu ve 90 günlük saklama süresini kullanır.

Test günlükleri, geldikleri test sonucunun `target_label` ve deneme `status` bilgilerini taşır, bu nedenle `target_label: "//foo:bar_test"` yalnızca o hedefin test günlüklerini döndürür. `errors: true`, başarısız denemelerin test günlüklerini ve Bazel raporcusunun `ERROR:`, `FAIL:` veya `TIMEOUT:` ile başlayan bir satır içeren stderr ilerleme parçalarını döndürür. İlerleme çıktısı hedeflere atanmaz ve atama kaydedilmeden önce yazılan günlüklerin alanları boştur. Başarısız eylemler ve kendi çıktıları `list_bazel_build_steps` üzerinden hedef başına, test senaryosu başına başarısızlıklar ise test çalıştırması araçlarından kullanılabilir.

#### Cargo derlemeleri

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_cargo_builds` | Bir proje için Cargo derlemelerini en yeniden eskiye doğru listeleyin. `git_branch`, `status`, `is_ci` veya `command` ile filtreleyin. Cargo test yürütme sonuçları bu derleme listesi üzerinden değil, test araçları üzerinden kullanılabilir. | `account_handle`, `project_handle` |
| `get_cargo_build` | Derleme meta verilerini, toplam önbellek sayaçlarını ve tanılama bilgileriyle birlikte en fazla 500 kaydedilmiş derleyici işini alın. `compilations_truncated` atlanan işleri gösterir; tanılama yalnızca döndürülen işleri kapsar. | `account_handle`, `project_handle`, `build_id` |

Doğrulanmış görev kararlarını ve CAS işlemlerini almak için `get_cargo_build` üzerinde `include_cache_inspection: true` ayarlayın; sınır 4 MB'tır. Varsayılan olarak ve kayıtlar eksik veya geçersiz olduğunda `cache_inspection` null olur. Kısmi yakalama `truncated` bayrağına saygı gösterin; aktarımlar her görev isabetinin yerel/uzak kökenini belirlemez. HTTP ayrıntı uç noktası aynı sorgu parametresini kabul eder.

#### Mix derlemeleri

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_mix_builds` | Bir proje için Mix (Elixir) derleme derlemelerini, özel meta veriler dahil olmak üzere en yeniden eskiye doğru listeleyin. `git_branch`, `status`, `is_ci` veya `mix_env` ile filtreleyin. | `account_handle`, `project_handle` |
| `get_mix_build` | Derleme meta verilerini, tanılama sayılarını ve bağımlılık önbelleği özetini alın. | `account_handle`, `project_handle`, `build_id` |

#### Derleme izleri

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `get_build_trace` | [Perfetto](https://ui.perfetto.dev) içinde açabileceğiniz bir iz dosyası olarak Xcode, Gradle, Bazel veya Mix derlemesinin zaman çizelgesi için bir indirme bağlantısı alın. | `account_handle`, `project_handle`, `build_id` |

`build_id`, derleme çalıştırma kimliği (Bazel için çağrı kimliği) veya derlemenin pano URL'sidir. Döndürülen `trace_url`, bir [Chrome Trace Event](https://docs.google.com/document/d/1CvAClvFfyA5R-PhYUmn5OOQtYMH4h6I0nSsKchNAySU) JSON dosyası sunar. Bağlantıya sahip olan herkes, diğer kimlik bilgileri olmadan `expires_at` tarihine kadar, yani çağrıdan bir saat sonrasına kadar o derlemenin izini indirebilir. Ajanlar bunu `curl` ile indirebilir, Perfetto'da açmanız için size verebilir veya Perfetto'nun `trace_processor` ile sorgulayabilir. İz, paralellik tarafından şeritlere paketlenmiş kaydedilmiş adımları, tüm derlemeyi kapsayan bir yolu ve derleme makine metriklerini kaydettiğinde CPU ve bellek sayaçlarını içerir. Günlükler olmadan yukarıdaki adım araçlarıyla aynı veriyi tutar. Pano, her derlemenin Zaman Çizelgesi sekmesinden aynı dosyayı sunar.

#### Struo çalıştırmaları

<a id="once-runs"></a>

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_once_runs` | Bir proje için Struo çalıştırmalarını en yeniden eskiye doğru listeleyin. `kind` (`build`, `test` veya `generic`), `status`, `is_ci` veya `git_branch` ile filtreleyin. Tamamlanmamış çalıştırmaların durumu `in_progress` olur. | `account_handle`, `project_handle` |
| `get_once_run` | Eylem toplamları, önbellek özeti ve test çalıştırmaları için test toplamları ile birlikte bir çalıştırmayı alın. | `account_handle`, `project_handle`, `run_id` |

Cargo derleme, Mix derleme ve Struo çalıştırma kimlikleri bir proje içinde benzersizdir. Aynı okumalar HTTP API üzerinden `GET /api/projects/{account_handle}/{project_handle}/cargo/builds`, `.../mix/builds` ve `.../once/runs` adreslerinde mevcuttur; her biri tek bir kimlik için bir ayrıntı uç noktasına sahiptir.

#### Görevler, eylemler, modüller ve dosyalar

Bu proje kapsamındaki araçlar, çalıştırmalar boyunca kalıcı derleme kimliklerini inceler. `list_build_entities` ile başlayın, ardından döndürülen sabit `id` ile aynı `kind` değerini `get_build_entity` veya `list_build_entity_history` öğesine, `account_handle` ve `project_handle` ile birlikte iletin. Derleme veya çağrı tanımlayıcısı gerekmez.

| Araç | Açıklama | Gerekli parametreler |
| --- | --- | --- |
| `list_build_entities` | Bir projenin derlemeleri arasında görülen tek bir türdeki görevleri, modülleri, eylemleri veya dosyaları listeleyin. | `account_handle`, `project_handle`, `kind` |
| `get_build_entity` | Seçilen dönem için yerel kimliği ve analitikleriyle tek bir derleme varlığını alın. | `account_handle`, `project_handle`, `kind`, `id` |
| `list_build_entity_history` | Bir derleme varlığının kaydedilmiş yürütmelerini, derlemelerini veya önbellek olaylarını en yeniden eskiye doğru listeleyin. | `account_handle`, `project_handle`, `kind`, `id` |

| `kind` | Araç zinciri | Geçmiş listeleri |
| --- | --- | --- |
| `bazel_actions` | Bazel eylemleri | BEP tarafından bildirilen eylem yürütmeleri |
| `gradle_tasks` | Gradle görevleri | Görev yürütmeleri |
| `xcode_modules` | Xcode modülleri | Derlemeler ve modül önbelleği olayları |
| `once_actions` | Struo eylemleri | Yürütmeler |
| `mix_files` | Mix ile derlenen dosyalar | Derlemeler |
| `mix_modules` | Mix ile derlenen modüller | Derlemeler |
| `cargo_crates` | Cargo paketleri | Kaydedilmiş rustc çağrıları |

Bu araçlar kademeli olarak sunulmaktadır ve yalnızca etkinleştirildikleri projeler için veri döndürür; diğer projeler için boş bir sonuç yerine hata döndürürler. Bir tür, yalnızca ilgili derleme araç zincirini kullanan projeler için kullanılabilir. Araçlar sınırlı `start_at`/`end_at` filtrelerini, `environment` (`any`, `ci` veya `local`) ve tam eşleşen bir `branch` kabul eder. `list_build_entities`, `q` parametresini kabul eder; `list_build_entity_history` şeffaf olmayan `after`/`before` imleçlerini destekler. Bilinmeyen zamanlama veya önbellek gözlemleri sıfır veya isabetsizlik olarak değil, mevcut değil olarak kalır. Geçmiş, mevcut çalıştırma araçlarını kullanarak detaylı inceleme için kaydedilen üst öğeyi ve yerel yürütmeyi referans alır.

`get_build_entity` metrikleri, zamanlaması kaydedilmiş gözlem sayısını ifade eden `duration_samples` değerini içerir: Gerçek sıfır süreler sayılır, eksik zamanlama sayılmaz. Bu sayı, gözlem sayısından daha düşük olabilir; kullanılamayan süre istatistikleri null olarak kalır.

Xcode modül süreleri, derleme günlüklerindeki ölçülmüş hedef derlemelerinden gelir. Modül önbelleği çözümleri ve derleme işi içermeyen hedefler süre örneklerine katkıda bulunmaz. Derleme gözlemleri Xcode derlemesine atıfta bulunur; önbellek olayları ise oluşturma veya önbellek komutuna atıfta bulunur.

Bazel eylemleri, hedef etiketi, anımsatıcı ve yapılandırılmış birincil çıktı ile tanımlanır; girdiye bağlı önbellek özetlerine güvenmeden ayrı eylemleri ve yapılandırmaları birbirinden ayırır. Geçmiş, BEP tarafından bildirilen yürütmeleri kaydeder, önbellek aramalarını veya iz profili aşamalarını değil. Tam yürütme kapsamı için `--build_event_publish_all_actions` gerekir; yapıt teslimi en iyi çabayla yapılır, bu nedenle eksik gözlemler hiçbir işin çalışmadığına dair kanıt değildir. Kararlı kimliği veya yürütme başlangıcı olmayan eski Kura yükleri kabul edilmeye devam eder ancak dizine eklenmez. Eksik bitiş zamanı ölçümleri kullanılamaz durumda kalır ve gerçek sıfır süreler sayılır.

Mix modül süreleri, bağımsız olarak ölçülen modül çalışmasını değil, kapsayan dosyanın derlenmesini ölçer. Struo eylemleri, istemci hedef eşlemelerini bildirdiğinde bildirilen hedef/yetenek/dizin yuvalarını kullanır; yalnızca tanılama etiketleri kararlı kimlikler değildir. Mevcut istemciler ve çalıştırma düzeyindeki araçlar değişmeden desteklenmeye devam eder.

Cargo kasaları, tam olarak kaydedilen kasa kökü, adı ve türüne göre gruplandırılır. Checkout yolu değişiklikleri geçmişleri bölebilir ve derleme profilleri, özellikler ve hedef üçlüleri ayırt edilmez. Geçmiş, dosya başına çalışmayı veya önbellek isabetlerini değil, rustc çağrılarını ölçer; eksik işler kaldırmaları veya eksiksiz bir çalışma alanı envanterini doğrulamaz.

Analitik okumalarının bellek ve yürütme süresi sınırları vardır. Bir sorgu bu sınırları aşarsa, araç boş bir sonuç uydurmak yerine bir hata döndürür.

Yeni gözlemler dağıtımdan sonra dizine eklenir; bu özellik mevcut çalıştırma telemetrisini geriye doğru doldurmaz. Kimlik meta verileri, <.localized_link href="/guides/server/data-retention">veri saklama politikası</.localized_link> kapsamında bireysel gözlemlerden daha uzun süre saklanır.

#### Testler

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_test_runs` | Bir proje için test çalıştırmalarını, her biri kendi `selective_testing_strategy` ile birlikte listeleyin. `selective_testing` ile filtreleyin (`coverage`, kapsama tabanlı seçimin geri dönüşlerini içerir, veya `module_hash`). `query` alanları `git_branch`, `scheme`, `status` ve `selective_testing` şeklindedir: `field:"value"` tam eşleşir, `field~"value"` büyük/küçük harfe duyarlı olmayan bir alt dizeyle eşleşir (`selective_testing` üzerinde değil) ve baştaki `-` herhangi bir operatörü olumsuzlar. Örneğin, `-git_branch~"gh-readonly-queue"` birleştirme kuyruğu dallarını dışlar. Boşlukla ayrılmış sorgu filtreleri ve açık argümanlar AND mantığıyla birleştirilir. | `account_handle`, `project_handle` |
| `get_test_run` | Bir test çalıştırması için kendi kod kapsamı (`coverage`: herhangi bir ölçüm yapılıp yapılmadığı, satırları ve figürü, kısmi olup olmadığı veya kirli bir checkout'tan çalışıp çalışmadığı), seçici test özeti (`selective_testing`: strateji, temel commit ve istenen, seçilen, atlanan ve tahmini test sayıları, test seçimi etkinliğinin hesaplandığı değerler) ve onu çalıştıran komutun sonuç paketi (`.xcresult`) ve oturum arşivi (CLI günlükleri) için geçici indirme URL'leri dahil olmak üzere ayrıntılı metrikleri alın veya çalıştırmaya bağlı bir komut yoksa `null` döndürülür. Parçalı bir çalıştırmanın `result_bundle_url`, ilk raporlayan parçanın paketidir; `shard_result_bundles`, CI yeniden denemeleri de dahil olmak üzere her parça raporu için bir paketi, parça indeksini ve durumunu listeler, böylece başarısız bir test olmadan başarısız olan bir parça incelenebilir. | `test_run_id` |
| `list_test_module_runs` | Belirli bir test çalıştırması için test modülü çalıştırmalarını listeleyin. | `test_run_id` |
| `list_test_suite_runs` | Belirli bir test çalıştırması için test suite çalıştırmalarını, isteğe bağlı olarak modüle göre filtrelenmiş şekilde listeleyin. | `test_run_id` |
| `list_test_cases` | Bir proje için test senaryolarını listeleyin (`flaky` gibi filtreleri destekler). | `account_handle`, `project_handle` |
| `get_test_case` | Güvenilirlik oranı, kararsızlık oranı ve çalıştırma sayıları dahil olmak üzere bir test senaryosu için ayrıntılı metrikleri alın. | `test_case_id` veya `identifier` + `account_handle` + `project_handle` |
| `list_test_case_runs` | Test senaryosu çalıştırmalarını, isteğe bağlı olarak test senaryosuna veya test çalıştırmasına göre filtrelenmiş şekilde listeleyin. | `account_handle`, `project_handle` |
| `get_test_case_run` | Belirli bir test senaryosu çalıştırması için hata ayrıntılarını ve tekrarları alın ve çalıştırmanın kapsama tabanlı seçimi testi koruduğunda nedenini belirtin (`selective_testing`: karar, neden, eşleşen değiştirilmiş dosya ve parça). | `test_case_run_id` |
| `list_test_case_run_attachments` | Bir test senaryosu çalıştırması için ekleri listeleyin. Her ek, geçici bir indirme URL'si içerir. | `test_case_run_id` |
| `list_test_case_events` | Bir test senaryosu için susturma veya atlama gibi durum değişikliklerini listeleyin. | `test_case_id` |
| `update_test_case` | Bir test senaryosunun durumunu veya kararsız sınıflandırmasını güncelleyin. Bir değişiklik, harici hizmetler de dahil olmak üzere yapılandırılmış webhook uç noktalarına bir olay gönderebilir. | `test_case_id` veya `identifier` + `account_handle` + `project_handle` |
| `list_xcode_test_targets` | Bir test çalıştırması için seçici test hedef sonuçlarını listeleyin. | `test_run_id` |
| `list_selective_testing_tests` | Bir test çalıştırmasının kapsama tabanlı seçiminin karar verdiği, seçtiği ve atladığı testleri, her kararın nedeni, onu seçen değiştirilmiş dosya, parçası ve çalıştırmadaki sonucu ile birlikte listeleyin. `decision`, `reason` veya `search` ile filtreleyin. | `test_run_id` |
| `list_selective_testing_changed_files` | Bir test çalıştırmasının kapsama tabanlı seçim temelinden bu yana değişen dosyaları, her birinin kaç testi seçtiğini ve değişikliği seçimin geri düşmesine neden olan izlenen bir dosya olup olmadığını göstererek listeleyin. | `test_run_id` |
| `get_coverage` | Bir projenin kod kapsamını hedefleriyle birlikte, bir commit'te veya bir dalın en son tamamlanmış commit'inde alın. `git_commit_sha` veya `branch` olmadan, varsayılan dalı okur. | `account_handle`, `project_handle` |
| `list_coverage_files` | Bir commit'in kod kapsamının ölçtüğü dosyaları, satır kapsamlarıyla birlikte, bir commit'te veya bir dalın en son tamamlanmış commit'inde listeleyin. `search`, sıralama ve sayfalama desteklenir. | `account_handle`, `project_handle` |
| `get_coverage_file` | Bir dosyanın kod kapsamını ve fonksiyonlarını, bir commit'te veya bir dalın en son tamamlanmış commit'inde alın. Her satırın yürütme sayısını almak için `include_lines` ayarlayın. | `account_handle`, `project_handle`, `path` |
| `list_coverage_branches` | Kod kapsamına sahip dalları, varsayılan dal ilk sırada olacak şekilde listeleyin. | `account_handle`, `project_handle` |
| `list_coverage_commits` | Bir dalın commit'lerini, kapsama durumları (`complete`, `incomplete`, `in_progress`, `not_measured`), figürü ve önceki tamamlanmış committen değişimi ile birlikte, en yeniden eskiye doğru listeleyin. İmleçlerle sayfalanır. | `account_handle`, `project_handle` |
| `list_coverage_runs` | Bir commit'in veya dalın arkasındaki kod kapsamına sahip test çalıştırmalarını, her biri `full`, `partial` veya `discarded` (kirli checkout) olarak işaretlenmiş şekilde listeleyin. İmleçlerle sayfalanır. | `account_handle`, `project_handle` |
| `list_coverage_targets` | Bir commit'in hedef başına kapsamını, ardından çalıştırmalarının kapsam sayaçları olmadan ikili önbellekten aldığı hedefleri (`measured: false`) listeleyin. `search`, sıralama ve sayfalama desteklenir. | `account_handle`, `project_handle` |

Kod kapsamı araçları, kod kapsamı etkinleştirilmiş hesaplara sunulur.

#### Paketler

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_bundles` | Bir proje için paketleri (uygulama ikililerini) listeleyin. İsteğe bağlı olarak `git_branch` ve `tags` ile filtreleyin (tüm etiketler tam eşleşmelidir). | `account_handle`, `project_handle` |
| `get_bundle` | Özel etiketler de dahil olmak üzere belirli bir paket hakkında ayrıntılı bilgi alın. | `bundle_id` |
| `get_bundle_artifact_tree` | Bir paket için tamartifact ağacını, yola göre sıralanmış düz bir liste olarak alın. | `bundle_id` |

`list_bundles`, derleme çeşitlerini veya ortamları ayırt etmek için `tags: ["paid", "production"]` kabul eder. Etiketler, büyük/küçük harfe duyarlı, harf, rakam, tire veya alt çizgi içeren etiketlerdir; etiket başına en fazla 10 etiket ve 50 karakter bulunur. Liste ve ayrıntı sonuçları `custom_metadata.tags` içerir. Sayfalama sayıları ve dal filtreleri etiketli sonuçlara uygulanır; `tags` atlandığında filtrelensiz davranış korunur. Geçersiz etiket filtreleri sorguyu genişletmek yerine bir hata döndürür.

#### Nesiller

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_generations` | Bir proje için nesil çalıştırmalarını listeleyin. | `account_handle`, `project_handle` |
| `get_generation` | Belirli bir nesil çalıştırması hakkında ayrıntılı bilgi alın. | `generation_id` |

#### Önbellek çalıştırmaları

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_cache_runs` | Bir proje için önbellek çalıştırmalarını listeleyin. | `account_handle`, `project_handle` |
| `get_cache_run` | Oturum arşivi (CLI günlükleri) için geçici bir indirme URL'si de dahil olmak üzere belirli bir önbellek çalıştırması hakkında ayrıntılı bilgi alın. | `cache_run_id` |
| `list_xcode_module_cache_targets` | Bir nesil veya önbellek çalıştırması için modül önbelleği hedeflerini, hedef başına önbellek isabeti/ıska durumu ve ek hashleme girdileri de dahil olmak üzere tanılama bileşeni hash'lerini göstererek listeleyin. | `run_id` |

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
| `list_project_notification_alerts` | Proje bildirim uyarı kurallarını listeleyin. Kontrol paneli ayarları sayfasıyla aynı yönetici iznini gerektirir. Webhook adresleri gizlenmiştir. | `account_handle`, `project_handle` |

### Olaylar

Durumsuz `2026-07-28` Model Context Protocol yaşam döngüsünü kullanan istemciler, olayları ve yük şemalarını keşfetmek için `events/list` çağrısı yapabilir:

| Olay | Gönderildiği zaman | Abonelik filtresi |
|-------|-----------------|---------------------|
| `test_case.marked_flaky` | Bir test senaryosu kararsız olmayan durumdan kararsız duruma geçer. | `account_handle`, `project_handle` |
| `build.failed` | Yerel veya sürekli entegrasyon Xcode, Gradle ya da Bazel derlemesi bir başarısızlıkla sonlanır. | `account_handle`, `project_handle` |
| `test_run.failed` | Yerel veya sürekli entegrasyon test çalıştırması bir başarısızlıkla sonlanır; birleştirilmiş parçalı çalıştırma veya terk edilmiş bir çalıştırma dahildir. | `account_handle`, `project_handle` |
| `ci_job.failed` | Bir Tuist runner işi bir başarısızlıkla tamamlanır. | `account_handle` |
| `pulse_symptom.opened` | Pulse, pano veya sayfa düzeyinde bir semptomu açar veya yeniden açar. Yalnızca denetim düzeyinde günlüğe kaydedilen semptomlar ve açık bir semptomdaki sonraki değişiklikler gönderilmez. | `account_handle` |

Abone olmak için istemci, olay adı, yukarıda `arguments` listelenen tutamaçlar ve bir `https://` geri çağırma URL’si ile bir `whsec_` imzalama sırrı içeren bir `webhook` teslimatıyla `events/subscribe` çağrısı yapar. Proje olayları hesap üyeliği ve ilgili test veya derleme verilerine okuma erişimi gerektirir; runner işi olayları hesap üyeliği ve runner okuma erişimi gerektirir; Pulse semptom olayları kuruluş üyeliği ve hesap için Pulse erişimi gerektirir ve bir hesap jetonu o hesaba ait olmalıdır. Talep edilen [`auth.md`](https://workos.com/auth-md) erişim jetonları, talep edilen hesap jetonları ve tarayıcı yetkilendirme izinleri abonelikler oluşturabilir; ilişkili kimlik bilgisi artık etkin olmadığında teslimat durur. Her kullanıcı en fazla 25 etkin abonelik tutabilir. Tuist, aboneliği kaydetmeden önce geri çağırmaya bir doğrulama sorgusu gönderir. Geri çağırma, aynı `challenge` değerini içeren bir nesne döndürmelidir. Abonelik varsayılan olarak yedi gün sürer, tekrar abone olunarak yenilenebilir ve kullanıcının erişimi veya kimlik bilgisi kaldırıldığında teslimat durur. İsteğe bağlı `ttlMs` bir saat ile 30 gün arasında sınırlıdır. Tuist, zaman aşımına uğrayan bir geri çağırmayı yeniden dener ve beş dakikayı kapsayan en az üç ardışık zaman aşımından sonra aboneliği iptal eder; geri çağırmayı restore ettikten sonra tekrar abone olun.

Bir olay gerçekleştiğinde, Tuist kaynak tanımlayıcısını ve kontrol paneli URL’sini geri çağırmaya gönderir. Derleme ve test çalıştırması hataları ayrıca `is_ci` ve `git_branch` içerir, böylece istemciler yerel hataları yok sayabilir veya dala göre filtreleyebilir. Derleme olayları `build_system` içerir; runner işi olayları hem `workflow_job_id` hem de `workflow_run_id` içerir; Pulse semptom olayları `symptom_id`, `tier` (`board` veya `page`) ve `untrusted` altındaki etkilenen varlığı `{"type": "untrusted_json", "value": {"service", "kind", "key"}}` olarak içerir; her değer en fazla 200 karakterdir: varlık üretim telemetrisinden gelir, bu nedenle onu veri olarak ele alın, asla talimat olarak görmeyin. URL’leri semptomun sayfasını açar. İstek, istemcinin kaynağını doğrulayabilmesi için bir abonelik tanımlayıcısı ve [Standard Webhooks](https://www.standardwebhooks.com/) imza başlıkları içerir. Tuist başarısız teslimatları yeniden dener, bu nedenle istemciler kopyaları atmak için kararlı `eventId` kullanmalıdır. Yük, test adlarını, günlükleri ve hata mesajlarını dışarıda bırakır; istemci bu ayrıntıları yukarıdaki araçlarla alabilir ve bir ekibi bilgilendirmeye veya hata ayıklamaya başlamaya karar verebilir. İstemciler teslimatı `events/unsubscribe` ile durdurabilir.

### İstemler

| İstem | Açıklama |
|--------|-------------|
| `fix_flaky_test` | Başarısızlık kalıplarını analiz ederek, kök nedeni belirleyerek ve hedefe yönelik bir düzeltme uygulayarak kararsız bir testi düzeltmenize rehberlik eder. |
| `compare_builds` | Performans gerilemelerini, önbellek değişikliklerini ve derleme sorunlarını belirlemek için derlemeleri karşılaştırmanıza rehberlik eder. Xcode, Gradle, Bazel ve Cargo projeleri için yerel araçları kullanır. Cargo karşılaştırmaları kısmi derleyici kapsamını korur ve tahmini derleyici işini geçen süreden tasarruftan ayırır. |
| `compare_test_runs` | Gerilemeleri, yeni hataları ve kararsız testleri belirlemek için iki test çalıştırmasını karşılaştırmanıza rehberlik eder. |
| `compare_bundles` | Artifact ağacı genelinde boyut değişikliklerini belirlemek için iki paketi karşılaştırmanıza rehberlik eder. |
| `compare_test_case` | Bir test senaryosunun davranışını iki dal veya zaman dilimi arasında karşılaştırmanıza rehberlik eder. |
| `compare_generations` | Performans gerilemelerini ve modül önbelleği değişikliklerini belirlemek için iki nesil çalıştırmasını karşılaştırmanıza rehberlik eder. |
| `compare_cache_runs` | Önbellek etkinliği değişikliklerini ve hedef düzeyindeki gerilemeleri belirlemek için iki önbellek çalıştırmasını karşılaştırmanıza rehberlik eder. |
| `integrate_gradle_project` | Tuist’i mevcut bir Gradle projesine entegre etmenize rehberlik eder. Ayrı araç ve Gradle kimlik doğrulaması, hesap keşfi, proje oluşturma, uzak önbellek politikası, derleme içgöruları ve geri okuma doğrulamasını içerir. |
| `integrate_bazel_project` | Bir Bazel projesi oluşturmanıza veya seçmenize, komut satırını kimlik doğrulamanıza, uzak önbelleği ve derleme içgörülerini yapılandırmanıza ve entegrasyonu Tuist derleme verileri aracılığıyla doğrulamanıza rehberlik eder. |
| `integrate_xcode_project` | Tuist’i mevcut bir Xcode projesine entegre etmenize rehberlik eder. Xcode önbelleği, derleme içgöruları, test içgöruları ve test parçalama desteği sunar. |
| `ask_tuist` | Bağlam için genel materyalleri ve mevcut davranış için gerçek kaynak olarak odaklanmış uygulama ve test kanıtlarını kullanarak bir Tuist sorusunu yanıtlar. Bir `question` gerektirir ve revizyon sabitli kanıtlara atıfta bulunur. |

Proje verisi istemleri, incelemeyi belirli bir projeyle sınırlamak için `account_handle` ve `project_handle` kabul eder. Karşılaştırma istemleri ayrıca karşılaştırılacak iki öğeyi (ID, kontrol paneli URL’si veya dal adı ile) belirtmek için `base` ve `head` bağımsız değişkenlerini kabul eder. `ask_tuist`, proje parametreleri yerine bir `question` kabul eder. `integrate_gradle_project` ayrıca uygulanacak Gradle entegrasyonlarının virgülle ayrılmış bir listesi olan `features` kabul eder: `remote_cache`, `build_insights`, `test_insights`, `flaky_tests` ve `test_sharding`. `integrate_bazel_project`, kendi kendine barındırılan veya yerel kurulumlar için isteğe bağlı bir `server_url` kabul eder. `integrate_xcode_project`, `xcode_cache`, `build_insights`, `test_insights` ve `test_sharding` ile `features` kabul eder.

#### Gradle entegrasyon istemi özellikleri

`integrate_gradle_project` istemi ve `get_gradle_integration_guide` aracı, eksiksiz kurulum iş akışını belgeler. Araç ayrıca sunucunun başlatma talimatları tarafından referans alınır; bu da istemleri numaralandırmayan ajanlar tarafından keşfedilmesini sağlar.

| Özellik | Ajanın yapılandırdığı şey |
|---------|---------------------------|
| `remote_cache` | Gradle’ın derleme önbelleğini etkinleştirir, Tuist uzak önbellek yükleme politikasını yapılandırır ve yalnızca sürekli entegrasyon çalıştırıcılarından yerel salt okunur kullanımla yüklemeleri önerir. |
| `build_insights` | Tuist Gradle eklentisini uygular ve gerektiğinde derleme analitiği yükleme davranışını yapılandırır. |
| `test_insights` | Gradle `Test` görevi sonuçlarının otomatik olarak yüklenmesi için Tuist Gradle eklentisini uygular. |
| `flaky_tests` | Kararsız test algılama kurulumuna, isteğe bağlı Gradle Test Yeniden Deneme eklentisi kullanımına ve test karantina yapılandırmasına rehberlik eder. |
| `test_sharding` | `tuistPrepareTestShards`, parça matrisi oluşturma ve `TUIST_SHARD_INDEX` tabanlı test yürütme için sürekli entegrasyon iş akışını ekler. |

`features` atlandığında, istem ajandan kullanıcının hangi entegrasyonları istediğini netleştirmesini veya Gradle projesini düzenlemeden önce istekten en küçük yararlı kümeyi çıkarmasını ister.

#### Xcode entegrasyon istemi özellikleri

`integrate_xcode_project` istemi, Tuist’in desteklediği her Xcode entegrasyonunu belgeler:

| Özellik | Ajanın yapılandırdığı şey |
|---------|---------------------------|
| `xcode_cache` | `tuist setup cache`, oluşturulan proje önbellek ayarlarını, manuel Xcode önbellek derleme ayarlarını ve yalnızca sürekli entegrasyon çalıştırıcılarıyla sınırlı bir yükleme politikasını yapılandırır. |
| `build_insights` | `tuist inspect build`, `tuist xcodebuild`, `-resultBundlePath` ve isteğe bağlı makine metriklerini `tuist setup insights` aracılığıyla yapılandırır. |
| `test_insights` | `tuist inspect test`, şema test sonrasındaki eylemleri ve sürekli entegrasyon test çalıştırmaları için sonuç paketi oluşturmayı yapılandırır. |
| `test_sharding` | `TUIST_SHARD_INDEX` ile Xcode veya oluşturulan proje parça planlaması ve parça yürütme iş akışını ekler. |

`features` atlandığında, istem ajandan kullanıcının hangi entegrasyonları istediğini netleştirmesini veya Xcode projesini düzenlemeden önce istekten en küçük yararlı kümeyi çıkarmasını ister.
