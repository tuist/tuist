---
{
  "title": "Model Context Protocol (MCP)",
  "titleTemplate": ":title · Ajan tabanlı kodlama · Özellikler · Kılavuzlar · Tuist",
  "description": "Yapay zeka ajanlarına Tuist'in MCP uç noktası üzerinden test içgörülerine ve daha fazlasına erişim sağlayın."
}
---
# Model Context Protocol

[Model Context Protocol (MCP)](https://modelcontextprotocol.io/docs/getting-started/intro), yapay zeka ajanlarının harici hizmetler ve veri kaynaklarıyla etkileşime girmesini sağlayan açık bir standarttır. [Claude](https://claude.ai/), [Claude Code](https://docs.anthropic.com/en/docs/claude-code), [Codex](https://developers.openai.com/codex/) gibi uygulamaların ve [Zed](https://zed.dev), [Cursor](https://www.cursor.com) veya [Visual Studio Code](https://code.visualstudio.com) gibi editörlerin Tuist ile birlikte çalışabilir olmasını sağlar.

Tuist, sunucu tarafında bir Model Context Protocol uç noktasını `https://tuist.dev/mcp` adresinde barındırır. İstemcinizi bu uç noktaya bağlayarak ajanların test içgörleri, kararsız test analizleri ve daha fazlası dahil olmak üzere Tuist proje verilerinize erişmesini sağlayabilirsiniz. Çoğu araç, kimliği doğrulanmış kullanıcının panoda zaten görebildiği Tuist verilerini okur. Her araç, salt okunur olup olmadığını, geri alınması zor bir değişikliğe neden olup olmadığını (`destructiveHint`) ve Tuist dışına erişip erişmediğini (`openWorldHint`) belirten ek açıklamalar sunar. Durumu değiştiren araçlar, her biri hesabın veya projedeki kullanıcının izinleriyle sınırlıdır:

- **Kuruluşlar ve üyeler**: `create_organization`, `add_organization_member` (mevcut bir kullanıcıyı ekler veya bir üyenin rolünü değiştirir), `invite_organization_member` (herhangi bir adrese davetiye e-postası gönderir) ve `cancel_organization_invitation`.
- **Projeler**: `create_project`, `start_project_logo_upload` ve `complete_project_logo_upload` (logoyu değiştirir), `connect_project_repository` ve `disconnect_project_repository` (GitHub depo bağlantıları).
- **Testler**: `update_test_case` (bir test senaryosunu sessize alır, atlar, yeniden etkinleştirir veya kararsız olarak işaretler; değişiklik hesabın webhook uç noktalarına ulaşabilir).
- **Bildirim kuralları**: `create_notification_rule`, `update_notification_rule` ve `delete_notification_rule`.
- **Sürekli entegrasyon çalıştırıcıları**: `create_runner_profile`, `update_runner_profile` (önbellek birimlerini kaydeden işleri daraltmak bekleyen kayıtları iptal eder), `delete_runner_profile` ve `delete_runner_volume` (birimin kaydedilen içeriğini siler).
- **Sandıklar**: `create_sandbox`, `pause_sandbox`, `resume_sandbox`, `extend_sandbox`, `archive_sandbox`, `delete_sandbox` (disklerini siler) ve bir sandığın cihazlarında (günümüzde bir macOS sandığının iOS simülatörleri) `boot_sandbox_device`, `launch_sandbox_app` ve `open_sandbox_url`.
- **Geri bildirim**: `report_feedback` (bir araç veya istem hakkında Tuist ekibine rapor gönderir; yalnızca tuist.dev üzerinde).
- **Kuruluş Yapay Zekası**: `save_organization_ai_model`, `remove_organization_ai_model`, `set_organization_ai_default_model`, `save_organization_ai_task_route`, `remove_organization_ai_task_route` ve `remove_organization_ai_provider` (sağlayıcının anahtarını ve modellerini siler ve Anthropic'te bağlı bir Claude kuruluşunun bağlantısını kaldırır).
- **Ajan entegrasyonları**: `connect_amp_workspace` (çalışma alanının orb'larına hesaba CI erişimi verir), `disconnect_amp_workspace` ve `connect_claude_environment` (bir Claude Managed Agents ortamının Tuist sandıklarında oturumlar çalıştırmasına olanak tanır).

`add_organization_member`, `cancel_organization_invitation`, `complete_project_logo_upload`, `disconnect_project_repository`, `update_test_case`, `update_notification_rule`, `delete_notification_rule`, `update_runner_profile`, `delete_runner_profile`, `delete_runner_volume`, `delete_sandbox`, `disconnect_amp_workspace`, `remove_organization_ai_provider`, `remove_organization_ai_model` ve `remove_organization_ai_task_route` mevcut durumu değiştirdiği veya kaldırdığı için `destructiveHint: true` bildirir. `invite_organization_member`, `update_test_case`, `connect_claude_environment`, `remove_organization_ai_provider` ve `report_feedback` e-posta gönderdiği, harici webhook uç noktalarını bilgilendirdiği, Anthropic'i çağırdığı veya Tuist ekibine rapor gönderdiği için `openWorldHint: true` bildirir.

Kişisel Claude ve ChatGPT abonelikleri yalnızca panonun Yapay Zeka ayarlarında bağlanır, bu nedenle abonelik jetonları ve oturum açma işlemleri asla bir Model Context Protocol istemcisinden geçmez. Hesap kurulum araçları kullanıcı kimlik doğrulaması gerektirir. Proje jetonları veya normal hesap jetonları tarafından kullanılamazlar. Bir kullanıcı tarayıcıda bir istemciyi yetkilendirdiğinde veya bir `auth.md` kaydını talep ettiğinde, Tuist bu kimlik bilgisini yalnızca Model Context Protocol uç noktasında kullanıcıyla ilişkilendirir, böylece kurulum araçları istenen iş akışını tamamlayabilir. Herkes bir istemci kaydedebileceğinden, tarayıcıda birini yetkilendirmek istemcinin adını ve erişiminin gönderildiği ana bilgisayar adını gösteren bir onay sayfası görüntüler ve Tuist kimlik bilgisini yalnızca siz orada onayladıktan sonra verir. Kapsam istemeyen bir istemci `mcp` kapsam grubunu alır. İstemciler `S256` ile PKCE kullanmalıdır ve yönlendirme URI'leri HTTPS, döngü adresinde HTTP veya uygulamanın kendi şemasını kullanmalıdır.

Tuist, [2026-07-28 protokolünü](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http) uygular. İstekler durumsuzdur: istemciler her istekle birlikte protokol meta verilerini gönderir ve araçları başlatma olmadan doğrudan çağırabilir. `server/discover` sunucunun kimliğini, yeteneklerini, desteklenen sürümleri ve talimatları döndürür. Oturum tanımlayıcıları veya bağımsız olay akışları yoktur. 2025-06-18 veya 2025-03-26 başlatma akışını kullanan istemciler desteklenmeye devam eder; bunlar da sunucu oturumları olmadan çalışır.

## Model Context Protocol ile beceriler arasındaki fark

Model Context Protocol araçları ve <.localized_link href="/guides/features/agentic-coding/skills">beceriler</.localized_link> yaptıkları işlerde örtüşebilir. İkisi arasındaki mevcut örtüşme göz önüne alındığında, her iş akışı için bir yaklaşım seçin ve aynı akışta ikisini karıştırmak yerine tutarlı bir şekilde kullanın.

Eklenti yüklemeyi destekleyen istemciler için, her ikisini birlikte yüklemek amacıyla <.localized_link href="/guides/features/agentic-coding/plugins">Tuist eklentilerini</.localized_link> kullanın.

## Yapılandırma

İstemcinize uzak bir Model Context Protocol sunucusu olarak `https://tuist.dev/mcp` ekleyin. Sunucunun başlatma talimatları ve genel sunucu kartı, aracıların harici kimlik doğrulama belgelerini getirmesini veya takip etmesini istemeden, dinamik istemci kaydı ve standart tarayıcı yetkilendirme akışı ile OAuth 2.0'ı satır içinde açıklar. Bu sunucu çapındaki talimatlar iş akışı rehberliğini genel tutar: araç kimlik doğrulaması yerel komut satırı araçlarını veya derleme sistemi entegrasyonlarını doğrulamaz ve ajanlar istenen değişiklikleri ilgili Tuist araçları aracılığıyla doğrulamalıdır. Derleme sistemine özel kurulum ve kimlik doğrulama kontrolleri entegrasyon kılavuzlarında ve istemlerinde belgelenmiştir. Tuist ayrıca hem [Open Authorization](https://oauth.net/2/) keşif meta verilerini hem de mevcut [auth.md protokolünü](https://workos.com/auth-md) `https://tuist.dev/auth.md` adresinde ayrı ayrı duyurmaya devam eder.

Kuruluşlarınızdan biri tek oturum açmayı (SSO) zorunlu kılıyorsa, tarayıcıda bir istemciyi yetkilendirmek o kuruluş üzerinden oturum açılmış bir oturum gerektirir ve Tuist gerektiğinde sizi önce sağlayıcıya yönlendirir. Bkz. <.localized_link href="/guides/integrations/authentication/sso#choose-an-enrollment-policy">tek oturum açma</.localized_link>.

Uç nokta, eski oturum tabanlı yaşam döngüsünün yanı sıra, `server/discover` dahil olmak üzere durumsuz `2026-07-28` Model Context Protocol istek yaşam döngüsünü kabul eder. Mevcut istemciler mevcut bağlantı yöntemlerini kullanmaya devam edebilir.

Model Context Protocol olaylarını destekleyen istemciler proje olaylarına abone olabilir. Mevcut olay ve teslimat gereksinimleri için bkz. [Olaylar](#events).

Uzaktan tarayıcı kimlik doğrulamasını zaten destekleyen istemciler, tarayıcıda kimlik doğrulamaya devam edebilir. `auth.md` destekleyen istemciler ve ajanlar anonim olarak kayıt olabilir, güvenilir bir sağlayıcı kimlik beyanı sunabilir veya hizmet tarafından kimliği doğrulanmış bir e-posta talebi başlatabilir. Kayıt, Tuist tarafından imzalanmış bir kimlik beyanı döndürür; ajan bu beyanı standart token uç noktasında bir saatlik erişim tokenı ile değiştirir. Tuist genel imzalama anahtarını yayımlar ve standart token iptalini ile sağlayıcı güvenlik olayı teslimatını destekler.

Kimliği doğrulanmamış bir ajan, Model Context Protocol uç noktasının döndürdüğü `WWW-Authenticate` üst bilgisini okumalı, korunan kaynak meta verilerini getirmeli, yetkilendirme sunucusu meta verilerini getirmeli ve `agent_auth.skill` URL’sini takip etmelidir. Tuist ayrıca yetkisiz yanıt gövdesinde aynı yerel `auth_md` URL’sini döndürür; böylece dil modeli tabanlı istemciler, yerel bir istemci entegrasyonuna güvenmeden akışı keşfedebilir. Dağıtım yerel belgesi; uç nokta adları, istek gövdeleri, talep yoklaması ve beyan değişimi için tek doğru kaynaktır.

Bir ajan e-posta talebini başlatmadan önce, kullanıcının Tuist hesabına ait e-posta adresini onaylamasını istemelidir. Bu adresi bir sağlayıcı profilinden, Git yapılandırmasından, ortam değişkeninden veya oturum meta verilerinden çıkarmamalıdır.

Uç nokta `mcp` kapsam grubunu kullanır. Anonim, talep öncesi bir kimlik bilgisi yetenekleri keşfedebilir ve genel entegrasyon rehberliğini okuyabilir ancak oturum açmış bir kullanıcı olarak değerlendirilmez. Tarayıcı yetkilendirmesinden veya talepten sonra kimlik bilgisi kullanıcı kapsamına alınır ve her araç, gösterge panelindekiyle aynı yetkilendirme kontrollerini uygular. Ayrıntılar için bkz. <.localized_link href="/guides/server/authentication#scope-groups">kapsam grupları belgeleri</.localized_link>.

Araçlar, kimliği doğrulanmış kullanıcının zaten okuma erişimine sahip olduğu projelere çözülür. Xcode ve Gradle derleme araçları bir derleme UUID’sini veya gösterge paneli URL’sini kabul eder. UUID tam olarak bir projeyi tanımlamalıdır; birden fazla projede görünüyorsa araç başka bir projenin raporunu seçmek yerine bulunamadı döndürür. Proje kapsamlı gösterge paneli ve API okumaları kullanılabilir durumda kalır. Bildirilen aktör tanımlayıcıları doğrulanmamış etiketlerdir; kimlik bilgileri veya ek erişim hakları değildir.

Derleme listesi ve ayrıntı araçları isteğe bağlı `tuist_version` meta verilerini sunar: Xcode ve Cargo için raporlayan Tuist CLI, Gradle için Tuist Gradle eklentisi ve Mix için `tuist_ex` kitaplığı. Xcode ayrıca bağlı proje oluşturma olayından `tuist_generation_version` değerini sunar; bu değer yükleyen CLI’dan farklı olabilir. Eksik gözlemler null’dur; sunucudan veya başka bir rapordan çıkarılmaz. Bazel mevcut `bazel_version` değerini kullanır; Struo çalıştırma ayrıntıları `once_version` değerini sunar. Bu alanlar bildirilen sürümleri açıklar; doğrulanmış kimlik veya ağ sözleşmesi sürümlerini değil. REST derleme uç noktaları aynı meta verileri sunar. Mevcut entegrasyon ve kararsız test becerileri sürüm alanlarına bağlı değildir ve iş akışı değişikliği gerektirmez.

Bir müşterinin hesabını inceleyen Tuist operatörleri bunu, her çağrıyı kaydeden Tuist’in dahili operasyon araçları aracılığıyla yapar; bu uç noktaya doğrudan bağlantı, kullanıcının kendi üyeliklerinin ötesinde hiçbir erişim sağlamaz.

### Pulse

Pulse, hesabın operasyonel metrikleri, günlükleri, izlemeleri ve hataları için salt okunur araçları sunar; tümü `account_handle` ile adreslenir. İlk üçü Pulse sayfalarını ve REST API’lerini yansıtır; diğer beşi bir ajanın telemetriyi doğrudan keşfetmesine olanak tanır ve REST eşdeğeri yoktur:

| Araç | Amaç | `/api/accounts/:account_handle/pulse` altındaki REST eşdeğeri |
| --- | --- | --- |
| `query_pulse` | Pulse sayfa tabloları | `GET /:signal` |
| `get_pulse_analytics` | Pulse sayfa widget’ları | `GET /:signal/analytics` |
| `get_pulse_error_issue` | Bir hata sorunu ve olayları | `GET /errors/issues/:fingerprint` |
| `query_pulse_metrics` | Anlık veya aralık PromQL | Yok |
| `list_pulse_labels` | Etiket adları veya bir etiketin değerleri | Yok |
| `search_pulse_logs` | Filtrelenmiş günlük girdileri | Yok |
| `search_pulse_traces` | Filtrelenmiş span’lar | Yok |
| `get_pulse_trace` | Bir izlemenin tüm span’ları | Yok |

Pulse, bir hesap veya proje herkese açık olsa bile sunucu tarafından yapılandırılan kuruluşun mevcut üyeleriyle sınırlıdır. Kullanıcı kimlik doğrulaması veya kullanıcıyla ilişkilendirilmiş `mcp` kimlik bilgisi ve hesap okuma yetkisi gerektirir. Proje tokenları, normal hesap tokenları, anonim kayıtlar ve kuruluş üyeliği olmayan operatör erişimi Pulse erişimi sağlamaz. Kimlik bilgileri başka bir arka uç veya telemetri kiracısı seçemez ve yalnızca sunucu tarafından yapılandırılan hesap Pulse telemetrisine sahiptir; bu nedenle hiçbir araç başka bir hesabın verilerini okuyamaz. Tarayıcı ajanları bu araçları yalnızca Pulse sayfalarında, o sayfanın hesap kapsamı içinde alır.

REST bir kullanıcı kimlik bilgisi gerektirir. OAuth ve `auth.md` kullanıcı ilişkileri yalnızca `/mcp` uç noktasında kullanılabilir; geçerli bir kullanıcıya sahip olmayan bir hesap kimlik bilgisi, ilişkili hesabın üyeliği veya görünürlüğünden bağımsız olarak reddedilir.

`query_pulse`, `signal` (`metrics`, `logs`, `traces` veya `errors`), isteğe bağlı `query` ve `range` (`15m`, `1h`, `6h` veya `24h`, varsayılan `1h`) parametrelerini alır. Metrikler PromQL ifadelerini kabul eder. Günlükler, izlemeler ve hatalar; günlük gövdeleri, span adları ve hata sorun başlıklarıyla eşleştirilen büyük/küçük harfe duyarlı olmayan düz metni kabul eder; varsayılan olan `*` her şeyi seçer. İzleme satırları bireysel span’lardır. Hata satırları sorunlardır: hizmete ve parmak izine göre gruplandırılmış olaylar; olay sayısı, etkilenen hesaplar, penceredeki ilk ve son oluşum ile en son olaylarının başlığı, sorumlusu, düzeyi ve platformu içerir. Tablolar `search`, `page` (varsayılan `1`), `page_size` (`1`–`100`, varsayılan `20`), `sort_by` ve `sort_order` (`asc` veya `desc`) parametrelerini kabul eder. Sıralama sütunları sinyale bağlıdır ve araç şemasında listelenir. Filtreler `service` ve günlükler ile hatalar için `level` içerir. Filtre operatörleri karşılık gelen `_op` argümanını (`eq`, `contains` veya `not_contains`) kullanır; varsayılan olarak tam eşitlik uygulanır.

Sıralama sütunları metrikler için `name`/`value`; günlükler için `timestamp`/`service`/`level`/`message`/`trace_id`; izlemeler için `timestamp`/`service`/`name`/`duration_ms`/`trace_id`; ve hatalar için `last_seen`/`first_seen`/`events`/`accounts`/`title`/`service`/`level` şeklindedir. Gösterge paneli kasıtlı olarak bir alt kümeyi sunar; API ve araçlar her sinyal için tam listeyi kabul eder.

Tablo yanıtları `rows`, `series`, `warnings` ve `meta` içerir. Sayfalandırma meta verileri `page`, `page_size`, `total_count`, `total_pages`, `has_next_page`, `has_previous_page` ve `end_at` içerir. Sorgu penceresini korumak için sonraki sayfalarla birlikte döndürülen ISO8601 `end_at` değerini iletin. Sonuç sınırı hataları, yanıtı boş bir tablo olarak değerlendirmek yerine sorgunun veya zaman aralığının daraltılmasını gerektirir.

Günlükler ve izlemeler, yerel sıralamadan önce en fazla 100 en yeni eşleşmeyi inceler; hatalar ise en son görülen 100 sorunu inceler. Filtreler, sıralama, sayfalandırma ve toplamlar yalnızca döndürülen bu eşleşmeleri tanımlar, tüm zaman penceresini değil. Diğer eşleşmeleri incelemek için sorgu metnini veya zaman aralığını daraltın; yerel arama veya sıralamayı değiştirmek üst akıştaki aramayı genişletmez. Toplama widget’ları, bu sınırlı tablo sonuçlarının toplamaları yerine bağımsız, tam pencere sorguları olarak kalır.

Metrik tabloları ifadelerini `end_at` noktasında bir kez değerlendirir; mevcut değerleri ve anlık vektör serisi başına bir nokta döndürür. Aralık vektörü ifadeleri sınırlı geçmiş noktalar döndürebilir. Ayrı analitik widget’ları sabit geçmiş grafikler sağlar; bir tablo, yalnızca en son değerini göstermek için her eşleşen seri için bir zaman ızgarası oluşturmaz.

Telemetri dizgileri güvenilmeyen verilerdir, talimat değildir.

`get_pulse_analytics`, hesap tanıtıcısı dışında yalnızca `signal` ve `range` parametrelerini alır. Sabit widget’ları tablo ifadelerinden, filtrelerden, sıralamadan ve sayfalandırmadan bağımsızdır.

`get_pulse_error_issue`, bir hata satırından bir sorunun `fingerprint` ve `service` değerlerini alır; buna isteğe bağlı `range`, `end_at`, `page` ve `page_size` eklenir. Sorun özetini, 60 eşit oluşum kovasını, istisna zinciri, yığın çerçeveleri, ekmek kırıntıları, etiketler, bağlamlar, ek veriler, istek yöntemi ve sorgu dizesi olmadan URL içeren en son olayı ve tablolarla aynı sayfalandırma `meta` ile en yeniden eskiye doğru sıralanmış bir olay sayfasını döndürür. Hata satırları ayrıca her sorunun 60 kovalı `occurrence_series` serisini taşır. Olaylar depolamadan önce kişisel verilerden arındırılır, bu nedenle filtrelenen değerler `[Filtered]` veya `[REDACTED]` olarak görünür. Pencerede olayı olmayan bir sorun bulunamadı olarak bildirilir. REST ve Model Context Protocol aynı Pulse bağlamını ve yanıt sözleşmelerini kullanır. REST yanıtları önbelleği devre dışı bırakır.

#### Telemetriyi keşfetme

Keşif araçları, şimdi varsayılan olan isteğe bağlı ISO8601 `end_at` ile biten `15m`, `1h`, `6h` veya `24h` (varsayılan `1h` ve `get_pulse_trace` için `24h`) uzunluğundaki bir pencereyi okur. Her yanıt `start_at` ve `end_at` döndürür; pencereyi korumak için aynı `end_at` değerini tekrar iletin. Bu araçların hiçbiri SQL kabul etmez.

- `query_pulse_metrics`, bir PromQL ifadesi olan `query` değerini `end_at` (`type: instant`, varsayılan) noktasında veya pencere boyunca her `step` saniyede bir (`type: range`) değerlendirir. Adım değeri varsayılan olarak pencerenin 360’a bölünmesine eşittir ve bundan küçük olamaz; bu nedenle bir seride en fazla 361 nokta olur. Sonuçlarda en fazla 5.000 seri bulunur. Noktalar `[unix_seconds, value]` şeklindedir; `NaN` ve sonsuz değerler dizgidir. Anlık sorgular `range` ve `step` parametrelerini reddeder.
- `list_pulse_labels`, bir `signal` parametresi alır. `label` olmadan etiket adlarını listeler; `label` ile o etiketin değerlerini listeler. Metrikler için `__name__` metrik adlarını listeler ve diğer herhangi bir etiketin değerleri `match` gibi bir seri seçici gerektirir; örneğin `up`. Günlük ve izleme etiketi değerleri `filters` kabul eder; izleme etiket adları izleme şemasından gelir ve bunu yapmaz. Günlük ve izleme değerleri, penceredeki giriş sayılarını içerir (en sık olanlar önce); bu nedenle hizmete göre hatalar gibi alt kırılımlar olarak da hizmet ederler. `search` yalnızca değişmez metin içeren adları veya değerleri tutar ve `limit` `1`–`1000` (varsayılan `100`) aralığını kabul eder.
- `search_pulse_logs`, gövdesi `text` içeren ve her filtreyi eşleştiren en fazla `limit` girişi (`1`–`100`, varsayılan `50`) döndürür; sıralama `newest` veya `oldest` öncelikli olabilir. Her giriş `severity_text`, `body`, `trace_id`, `span_id`, `scope_name` ve birleştirilmiş kaynak ile günlük `attributes` bilgilerini içerir. Yalnızca OTLP günlük göndericilerinin ayarladığı Kubernetes’ten toplanan günlükler için `span_id` ve `scope_name` değerleri `null` olur.
- `search_pulse_traces`, her filtreyi, isteğe bağlı `min_duration_ms` ve `max_duration_ms` ile `root_only` koşulunu karşılayan en fazla `limit` span’ı döndürür; sıralama `newest`, `oldest` veya `slowest` öncelikli olabilir.
- `get_pulse_trace`, pencerede başlayan `trace_id` izlemesinin span’larını en eskiden en yeniye doğru, en fazla 1.000 span olacak şekilde döndürür. Pencereden önce başlamış bir izleme kısmen döndürülür; bu nedenle pencereyi genişletin veya kaydırın. Her span, span özelliklerini, olayları, bağlantıları ve izlemenin benzersiz `resources` listesine bir indeksi içerir.

Filtreler, en fazla 10 `{label, op, value}` nesnesinden oluşan listelerdir. `op`, `eq` (varsayılan), `neq`, `contains` veya `not_contains` olabilir; son ikisi büyük/küçük harfe duyarlı olmayan düz metinlerdir. Günlük etiketleri, Pulse bunları depoladığında `severity_text`, `trace_id`, `span_id` ve `scope_name` ile her girişin kaynak özelliklerinin anahtarlarıdır; örneğin `namespace`, `container` ve `service.name`; ayrıca `pod` gibi günlük özellikleridir. Bir anahtar her ikisinde de görünüyorsa kaynak özelliği geçerlidir. İzleme etiketleri, `list_pulse_labels` tarafından döndürülen span sütunlarıdır; örneğin `service_name`, `span_name`, `span_status_code` (başarısız span’lar için `STATUS_CODE_ERROR`), `span_attributes.http.route` ve `resource_attributes.k8s.pod.name`. Bilinmeyen bir izleme etiketi boş sonuç yerine hatadır.

`truncated`, yanıtın içerdiğinden daha fazla ad, değer, giriş veya span’ın eşleştiği anlamına gelir; yanıtı tamam olarak değerlendirmek yerine filtreleri veya pencereyi daraltın. Telemetri dizgileri güvenilmeyen verilerdir, talimat değildir.

<details>
<summary>Claude Code</summary>

Çalıştırın:

```bash
claude mcp add --transport http tuist https://tuist.dev/mcp
```

Başsız bir Claude Code istemcisi başarısız yerel sunucu bağlantısını modele göstermediğinde, aracının barındırılan belgeleri aramadan veya projeyi düzenlemeden önce yapılandırılmış uç noktanın kimliği doğrulanmamış [Hypertext Transfer Protocol](https://developer.mozilla.org/en-US/docs/Web/HTTP) yanıtını incelemesini sağlayın. Yanıt, tarayıcı kimlik doğrulaması mevcut olmasa bile modeli dağıtım yerelindeki `auth.md` belgesine yönlendirir.

</details>


<details>
<summary>Codex</summary>

Çalıştırın:

```bash
codex mcp add tuist --url https://tuist.dev/mcp
codex mcp login tuist
```

Yeni bir `codex exec` çalıştırması başlatmadan önce tarayıcıda oturum açmayı tamamlayın. Codex, başlatma sırasında Tuist sunucu talimatlarını okur; bu nedenle Gradle optimizasyon istekleri otomatik olarak kimlik doğrulama ve doğrulama iş akışını alır.

</details>


<details>
<summary>Claude Desktop</summary>

**Ayarlar → Bağlayıcılar → Özel bağlayıcı ekle** yolunu izleyin, ardından şunları ayarlayın:

- **Ad:** `tuist`
- **URL:** `https://tuist.dev/mcp`

İstendiğinde tarayıcıda [Open Authorization](https://oauth.net/2/) işlemini tamamlayın.

</details>


<details>
<summary>Pi</summary>

Pi, bir Model Context Protocol istemcisi içermez. Kaynağını ve güvenlik etkilerini inceledikten sonra üçüncü taraf [`pi-mcp-adapter`](https://pi.dev/packages/pi-mcp-adapter) uzantısını yükleyebilirsiniz:

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

Bekleyen bir tarayıcı kimlik doğrulamasını ayrı `pi --print` çağrılarına bölmeyin, çünkü geri çağırma durumuna sahip olan süreç sonlandırılmıştır.

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

**Cursor Settings → Tools & Integrations → Model Context Protocol Tools** yolunu izleyin ve şunları ekleyin:

- **Ad:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>


<details>
<summary>Visual Studio Code</summary>

**Command Palette → MCP: Add Server** seçeneğini kullanın, ardından şu ayarlarla bir [Hypertext Transfer Protocol](https://developer.mozilla.org/en-US/docs/Web/HTTP) sunucusu yapılandırın:

- **Ad:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>


<details>
<summary>Zed</summary>

**Agent panel → Settings → Add Custom Server** yolunu izleyin, ardından şunları ayarlayın:

- **Ad:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>

Aracınız `auth.md` destekliyorsa, tarayıcı açmadan anonim olarak başlayabilir. Güvenilir bir sağlayıcı kimliği zaten bağlıysa, tarayıcı olmadan da işlem tamamlanabilir. Hizmetle kimliği doğrulanmış e-posta, anonim talep veya ilk sağlayıcı bağlantısı için aracı size bir Tuist doğrulama bağlantısı ve altı haneli bir kod gösterir. Bağlantıyı açın, oturum açın ve Tuist sayfasında aracının kodunu girin. Kodu asla aracıya geri göndermeyin. Tuist'in yetkilendirme sunucusu meta verileri, doğrudan dağıtımın kendi `/auth.md` adresine işaret eder; bu adres kesin istek ve yoklama yapılarını içerir.

## Amp orb'larında ve Claude Code bulut oturumlarında çalışan ajanlar

Bir Tuist hesabına bağlı alan kutularında (sandbox) çalışan kodlama ajanları, tarayıcı veya kaydedilmiş bir Tuist kimlik bilgisi gerekmeden kendi kimlik belirteçleriyle uç noktaya kimlik doğrulayabilir:

- Hesabın **Ayarlar → Entegrasyonlar → Amp** altında bağladığı bir Amp çalışma alanının veya projesinin **Amp orb'ları**, orb'un kimlik belirtecini gönderir. Amp'te sunucunun `Authorization` başlığını `Bearer ${amp:id-token}` olarak ayarlayın. Amp, sunucu URL'sinin kaynağı için belirteci basar, bu nedenle URL bu Tuist örneğinin kendi adresi olmalıdır ve süresi dolmadan önce yeniler. Başka bir kaynak için basılan belirteçler reddedilir.
- Bağlı bir Claude Code ortamının **Claude Code bulut oturumları**, Tuist'in onlara `TUIST_OIDC_TOKEN` olarak ilettiği oturum belirtecini gönderir. Başlığı `Bearer ${TUIST_OIDC_TOKEN}` olarak ayarlayın.

Tuist'in Linux alan kutuları sunucuyu sizin için eklemez: Aynı kimlikle oturum açan Tuist CLI'ını ve aracının sonuçlarını projenin geçmişine göre ne zaman kontrol etmesi gerektiğini bildiren bir beceriyi içerirler. Ajanlara MCP araçlarını da sağlamak için sunucuyu yukarıdaki başlıkla birlikte Amp veya Claude Code ayarlarınıza ya da projenin `.mcp.json` dosyasına ekleyin.

Bu belirteçler, bağlı hesabın her projesine salt okunur erişim sağlar: `mcp` grubunun okuma kapsamlarını taşırlar ve testleri sessize alma veya atlama gibi veri oluşturan, değiştiren veya silen hiçbir kapsamı taşımazlar. Çalışma alanının veya ortamın bağlantısını kesmek, bir sonraki istekte erişimi durdurur ve erişim asla belirtecin kendisinden daha uzun sürmez. Birden fazla Tuist hesabına bağlı bir Amp çalışma alanı reddedilir, çünkü belirteci tek bir hesabı adlandırmaz. Bir bağlantı eksik olduğunda, yetkisiz yanıtın `error_description` alanı bunu belirtir.

Bu salt okunur erişim yalnızca Model Context Protocol uç noktası için geçerlidir. Aynı alan kutusundaki komut satırı aracı ve derleme sistemi entegrasyonları, bağlantının CI erişimi için belirteci değiştirmeye devam eder.

## WebMCP

[WebMCP](https://webmachinelearning.github.io/webmcp) destekleyen tarayıcılarda, Tuist'in sayfaları araçları `document.modelContext` ile kaydeder, böylece tarayıcıya yerleşik ajanlar herhangi bir ek yapılandırma olmadan bunları çağırabilir. Çağrılar Tuist sunucusunda çalışır.

- **Web sitesi ve belge sayfaları**, belge ve kaynak araçlarını (`search_tuist`, `search_tuist_code`, `list_tuist_files` ve `read_tuist_file`) kaydeder. Oturum açmanıza gerek yoktur.
- Oturum açtığınızda, **bir hesabın pano sayfaları** o hesap için Tuist'in salt okunur araçlarını kaydeder. Her sayfa yalnızca gösterdiği içeriğe, projenin derleme sistemine uygun araçları kaydeder: Bir Gradle projesinin derlemeler sayfası Gradle derleme araçlarını, test sayfaları test ve kapsam araçlarını, çalıştırıcı sayfaları çalıştırıcı araçlarını ve alan kutusu sayfaları alan kutusu araçlarını alır. Her sayfa ayrıca `list_projects` ve `get_project` belge araçlarını da alır. Araçlar oturum açmış kullanıcı olarak çalıştığından, yalnızca panoda okuyabileceğiniz verilere ve yalnızca baktığınız hesaba erişirler. Başka bir sayfaya veya hesaba geçtiğinizde, araçlar o sayfanın araçlarıyla değiştirilir.

Veri oluşturan, değiştiren veya silen araçlar WebMCP üzerinden kullanılamaz, çünkü bir tarayıcı ajanı araçları sizin eklemeniz olmadan alır ve derlemeler ile testlerin ürettiği içeriği okur. Bu araçları kullanmak için bir MCP istemcisini `/mcp` uç noktasına bağlayın.

Kuruluş tek oturum açmayı (SSO) zorunlu kılıyorsa, araçlarını kullanmak için panoya sağlayıcısıyla oturum açın.

## Derleme sistemi entegrasyonları iki kimlik bilgisi kullanır

Model Context Protocol araçları için kullanılan kimlik bilgisi, Gradle eklentisini veya Bazel'in uzak hizmetlerini kimlik doğrulamaz. Bir aracı bir Gradle veya Bazel entegrasyonunu düzenlemeden veya doğrulamadan önce şunu çalıştırmalıdır:

```bash
tuist auth whoami --url https://tuist.dev
```

Bu komut kimlik doğrulanmamışsa, aracı durmalı ve kullanıcıdan şunu çalıştırmasını istemelidir:

```bash
tuist auth login --url https://tuist.dev
```

Yerel veya kendi barındırdığınız bir dağıtım için, her iki komuttaki ve `tuist.toml` içindeki URL'yi değiştirin. Ana bilgisayar adının yazımını her yerde aynı tutun. Örneğin, `localhost` ve `127.0.0.1` ayrı saklanan kimlik bilgilerini kullanır.


## Yetenekler

### Araçlar

Aşağıdaki araçlar Tuist Model Context Protocol sunucusu üzerinden kullanılabilir:

Her araç, açık giriş ve çıkış şemalarıyla birlikte insan tarafından okunabilir bir açıklama yayımlar. Başarılı çağrılar, ilan edilen çıkış şemasına uyan yapılandırılmış içerik döndürür; ayrıca henüz yapılandırılmış içeriği tüketmeyen istemciler için metin olarak serileştirilmiş aynı sonucu da içerir.

`build_run_id`, `test_run_id`, `test_case_id`, `bundle_id`, `run_id`, `generation_id` veya `cache_run_id` gibi tek bir kaydın tanımlayıcısını alan araçlar, o kaydın Tuist pano URL'sini de kabul eder. Tanımlayıcıyı ayıklamak yerine URL'yi doğrudan tarayıcıdan yapıştırın.

`get_xcode_build`, `get_test_run`, `get_gradle_build` ve `get_project` araçları `side_quests` içerebilir: projenin kullanmadığı ancak kaydın faydalı olacağını gösterdiği Tuist yetenekleri. Her birinin bir `id`, dayandığı kanıtı belirten bir `tip` ve bir `docs` bağlantısı vardır. Ajanlardan önce kullanıcının isteğini tamamlamaları, geçerli yan görevlerden bahsetmeleri ve yalnızca kullanıcı onayladığında bunlardan birini gerçekleştirmeleri istenir. Bunlar yalnızca projenin hesabının üyelerine döndürülür; kullanıcı oturumu, MCP jetonu veya ajan kimliğiyle bağlanmaları fark etmez:

| Kimlik | Araç | Önerildiğinde |
|----|------|----------------|
| `xcode_compilation_cache` | `get_xcode_build` | Xcode 26 veya sonraki bir sürümle işlenen temiz bir derleme, önbelleğe alınabilir derleme görevi çalıştırmadı. |
| `gradle_build_cache` | `get_gradle_build` | Bir derleme, Gradle'ın derleme önbelleği bunlardan herhangi biri için bir anahtar hesaplamadan önbelleğe alınabilir görevleri yürüttü; bu, derleme önbelleğinin kapalı olduğu anlamına gelir. |
| `flaky_test_quarantine` | `get_test_run` | Bir çalıştırma kararsız testler içeriyordu ve projede etkinleştirilmiş hiçbir otomasyon bunları sessize almıyor veya atlamıyor. Struo projeleri için önerilmez. |
| `test_sharding` | `get_test_run` | Tuist'in parçalara bölebileceği bir derleme sisteminde, parçalara bölünmemiş bir CI çalıştırması 10 dakika veya daha uzun sürdü. İpucu, seçici testin ne zaman kaç testi atladığını belirtir. |
| `tuist_runners` | `get_xcode_build`, `get_test_run` | Bir CI çalıştırması GitHub Actions, Bitrise, GitLab CI veya Buildkite makinelerini kullandı ve hesap hiçbir zaman Tuist Runners üzerinde bir iş çalıştırmadı. Yalnızca tuist.dev'de. |
| `pull_request_comments` | `get_xcode_build`, `get_test_run` | Bir GitHub Actions çalıştırması, GitHub deposuna bağlı olmayan bir projeye aittir. |
| `other_build_systems` | `get_project` | Hesap, Tuist'i desteklenen her derleme sistemiyle kullanmıyor. İpucu, diğerlerini tanımlayan dosyaları listeler, böylece aracı depoyu kontrol edebilir. |

#### Belgelendirme ve topluluk araması

Bu salt okunur araç, Tuist'in belgelerini, [uygulama programlama arayüzü](https://en.wikipedia.org/wiki/API) referansını, GitHub sürümlerini, topluluk forumunu ve GitHub sorunlarını, dokümantasyon web sitesini güçlendiren aynı arama motoru üzerinden arar. Sürüm sonuçları ürünü, sürümü, yayın tarihini ve ön sürüm durumunu içerir. Varsayılan olarak kararlı sürümler aranır ve ön sürümler `include_prereleases` ile dahil edilebilir. Araç yalnızca `https://tuist.dev/mcp` adresindeki Tuist tarafından barındırılan sunucuda kullanılabilir.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `search_tuist` | Genel Tuist belgelerini, uygulama programlama arayüzü referansını, GitHub sürümlerini, topluluk tartışmalarını ve GitHub sorunlarını arayın. İsteğe bağlı olarak tek bir `source` kaynağıyla sınırlayın (`docs`, `api_reference`, `releases`, `forum`, `issues`). | `query` |

#### Geri bildirim

Ajanlar, bir Tuist aracının veya isteminin bekledikleri gibi çalışmadığında (örneğin kafa karıştırıcı bir sonuç, hata, eksik veri veya eksik bir yetenek) Tuist ekibine bildirebilir. Ajanlardan bir rapor önermeleri ve bunu yalnızca siz onayladığınızda göndermeleri istenir. Her rapor, Tuist desteği ile bir konuşma başlatır; destek ekibi size e-posta ile yanıt verebilir. Bir rapor, ajanın ne beklediğini, ne olduğunu, isteğe bağlı bir öneriyi, Tuist kullanıcı kimliğinizi, kullanıcı adınızı ve e-postanızı ile ait olduğunuz kuruluşları içerir. Ajanlar ayrıca sorunun yaşandığı hesabı ve projeyi de belirtebilir, böylece ekip hangi kuruluşla iletişime geçeceğini bilir; yalnızca ait olduğunuz hesaplar kabul edilir. Raporları yalnızca Tuist kullanıcısı olarak oturum açmış ajanlar gönderebilir ve her kullanıcı saatte en fazla 10 rapor açabilir. Araç yalnızca `https://tuist.dev/mcp` adresindeki Tuist tarafından barındırılan sunucuda kullanılabilir.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `report_feedback` | Bir Tuist aracı veya istemiyle ilgili bir sorunu bildirin. İsteğe bağlı olarak `tool_name`, gerçekleştiği `account_handle` ve `project_handle` öğelerini belirtin ve bir `suggestion` ekleyin. | `category`, `expected`, `actual` |

#### Kaynak destekli yanıtlar

Bu salt okunur araçlar, ajanların mevcut davranışa bağlı yanıtlar için doğruluk kaynağı olarak barındırılan sunucuyla birlikte dağıtılan tam genel Tuist kaynak revizyonunu kullanmasına olanak tanır. Yalnızca `https://tuist.dev/mcp` adresinde kullanılabilirler.

Uyumlu istemciler, başlatma sırasında satır içi OAuth kimlik doğrulama bilgilerinin yanı sıra araçların kaynak revizyonu, bağlantıları ve sonuç sınırları hakkında olgusal açıklamalar alır. Bu açıklamalar yanıt stilini veya bir doğrulama iş akışını dikte etmez. Kullanıcılar, önce `ask_tuist` istemini çağırmadan doğrudan bir soru sorabilir; istem, açık kaynak destekli bir iş akışı için kullanılmaya devam eder.

Her işlem için eşzamanlılık, süre, gezinme, okunan bayt ve yanıt boyutu sabit sınırlara sahiptir. Arama ve listeleme sonuçları `truncated` ve `truncation_reason` alanlarını içerir. Bir sonuç kısaltıldığında, sonucu kapsamlı olarak değerlendirmek yerine yolu, dosya kalıbını veya arama terimini daraltın.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `search_tuist_code` | Kaynak dosyaları arayarak mevcut davranış, varsayılanlar, yapılandırma, özellik kapıları, hata işleme veya belgelenmemiş ayrıntılar hakkındaki soruları yanıtlayın. Sonuçlar çevreleyen satırları, revizyon sabitli kaynak bağlantılarını ve tarama istatistiklerini içerir. | `pattern` |
| `list_tuist_files` | İlgili yol bilinmediğinde bir kaynak alt sistemini veya yakındaki testleri keşfedin. Listelemelerin derinliği ve sonuç sayıları sınırlıdır. | Yok |
| `read_tuist_file` | İlgili yolu bulduktan sonra bir uygulama dosyasındaki, çağrı noktasındaki veya testteki odaklanmış satır aralığını inceleyin. Kısaltılmış yanıtlar, devam etmek için `next_start_line` sağlar. | `path` |

#### Projeler

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_accounts` | Kimliği doğrulanmış kullanıcı için kullanılabilen kişisel ve kuruluş hesap kullanıcı adlarını, her hesabın proje oluşturup oluşturamayacağı dahil olmak üzere listeleyin. | Yok |
| `get_organization` | Bir kuruluşun üye dizinini alın. Bekleyen davetler, gösterge paneliyle aynı yönetici iznini gerektirir; davet kabul belirteçleri asla döndürülmez. | `account_handle` |
| `create_organization` | Kimliği doğrulanmış kullanıcı için bir Tuist kuruluşu oluşturun. | `handle` |
| `create_project` | Kimliği doğrulanmış kullanıcının erişebileceği bir hesap altında bir Tuist projesi oluşturun. | `account_handle`, `project_handle` |
| `add_organization_member` | Mevcut bir Tuist kullanıcısını bir kuruluşa ekleyin veya mevcut bir üyenin rolünü güncelleyin. `user` (varsayılan), `admin` veya `viewer` kabul eder; burada görüntüleyici panoları ve çalıştırmaları okuyabilir ancak hiçbir şeyi değiştiremez. | `organization_handle`, `email` |
| `invite_organization_member` | Bir e-posta adresini, mevcut bir Tuist kullanıcısına ait olup olmadığından bağımsız olarak bir kuruluşa davet edin. Tuist, 14 gün sonra sona eren bir kabul bağlantısı e-postası gönderir; sunucu e-posta gönderemediğinde `email_sent` değeri `false` olur ve bağlantının gösterge panelinden kopyalanması gerekir. `user` (varsayılan), `admin` veya `viewer` kabul eder. Kuruluş yöneticisi izni gerektirir. | `organization_handle`, `email` |
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

Bu araçlar, kimliği doğrulanmış kullanıcının kendi bildirim kurallarını yönetir: Kuralın projelerinde (veya hiçbiri listelenmediğinde bildirim alabileceğiniz herhangi bir projede) yeni bir önizleme gibi bir olay gerçekleştiğinde ve koşulları karşıladığında, Tuist uygulama cihazlarınıza anlık bildirim gönderme gibi eylemlerini yürütür. Kurallar olmadan bildirim almazsınız. Kullanıcı kimlik doğrulaması gerektirirler, yalnızca kendi kurallarınız üzerinde işlem yaparlar ve yalnızca ait olduğunuz hesaplara ait projeleri kabul ederler. Kurallar tüm hesaplarınızı kapsadığından gösterge paneli sayfalarında sunulmazlar.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_notification_events` | Kuralların abone olabileceği olay türlerini, her biri için koşullarına ilişkin bir JSON Şeması ile birlikte listeleyin. | Yok |
| `list_notification_condition_options` | Bir projedeki bir olay için koşul değerleri önerin; örneğin, son önizlemelerinin izleri ve dalları. | `event`, `account_handle`, `project_handle` |
| `list_notification_rules` | Kurallarınızı listeleyin. | Yok |
| `create_notification_rule` | Bir olaydan, isteğe bağlı projelerden ve koşullardan ve en az bir eylemden oluşan bir kural oluşturun. | `event`, `actions` |
| `update_notification_rule` | Bir kuralın etkin durumunu, projelerini, koşullarını veya eylemlerini değiştirin. | `rule_id` |
| `delete_notification_rule` | Bir kuralı silin. | `rule_id` |

#### Sürekli entegrasyon çalıştırıcıları

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_runner_jobs` | Bir hesap için sürekli entegrasyon çalıştırıcı işlerini listeleyin. | `account_handle` |
| `get_runner_job` | Bir sürekli entegrasyon çalıştırıcı işini alın; makinesinin belleğinin tükenip tükenmediği, neyi durdurduğu ve neyin değiştirilmesi gerektiği dahil. | `account_handle`, `workflow_job_id` |
| `list_runner_job_steps` | Bir sürekli entegrasyon çalıştırıcı işi için kaydedilen adımları listeleyin. | `account_handle`, `workflow_job_id` |
| `list_runner_job_metrics` | Bir sürekli entegrasyon çalıştırıcı işi için kaydedilen makine metriklerini listeleyin. | `account_handle`, `workflow_job_id` |
| `list_runner_job_logs` | Bir sürekli entegrasyon çalıştırıcı işi için yakalanan en fazla 500 günlük satırını listeleyin. | `account_handle`, `workflow_job_id` |
| `list_runner_workflows` | Bir hesap için sürekli entegrasyon iş akışı özetlerini listeleyin. | `account_handle` |
| `list_runner_profiles` | Bir hesap için sürekli entegrasyon çalıştırıcı profillerini, her birinin `runs-on` etiketiyle birlikte listeleyin. | `account_handle` |
| `get_runner_catalog` | Bir çalıştırıcı profilinin kullanabileceği makine şekillerini ve Xcode sürümlerini listeleyin. | `account_handle` |
| `create_runner_profile` | Bir platform, bir makine şekli ve macOS'ta bir Xcode sürümü ile bir çalıştırıcı profili oluşturun. İsteğe bağlı olarak hangi dalların önbellek birimlerini kaydedeceğini ayarlayın. Hesap yöneticiliği veya `account:runners:write` kapsamı gerektirir. | `account_handle`, `name`, `platform`, `vcpus`, `memory_gb` |
| `update_runner_profile` | Bir çalıştırıcı profilinin makine şeklini, Xcode sürümünü veya özel önbellek birimi değişikliklerini hangi dalların kaydedeceğini değiştirin. Atlanmış alanlar değerlerini korur. Hesap yöneticiliği veya `account:runners:write` kapsamı gerektirir. | `account_handle`, `profile_name` |
| `delete_runner_profile` | Kullanıcı onayından sonra bir çalıştırıcı profilini silin. Varsayılan profiller silinemez. Hesap yöneticiliği veya `account:runners:write` kapsamı gerektirir. | `account_handle`, `profile_name` |

Çalıştırıcı birim araçları, Birimler gösterge paneliyle aynı verileri sunar. Okuma araçları çalıştırıcı erişimi gerektirir; temizleme işlemi hesap yöneticiliği veya `account:runners:write` kapsamı ve kullanıcı onayı gerektirir.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_runner_volumes` | Birimleri ada ve depoya göre filtreleyin, sıralayın ve sayfalara bölün. | `account_handle` |
| `get_runner_volume` | Depo, platform, kapasite, kullanılan alan ve son kullanım. | `account_handle`, `volume_id` |
| `list_runner_volume_jobs` | Sayfalanmış iş ve iş akışı referansları, önbellek durumu, isabet sonucu ve bağlama süresi. | `account_handle`, `volume_id` |
| `list_runner_job_volumes` | Bir iş tarafından bağlanan birimler. | `account_handle`, `workflow_job_id` |
| `get_runner_volume_analytics` | Depolama serileri, iş çalıştırmaları, isabet oranı ve eğilimler. İsteğe bağlı `volume_id`, `start` ve `end` (ISO 8601); varsayılan yedi gün, en fazla 90. | `account_handle` |
| `delete_runner_volume` | Bir birimi ve kaydedilen içeriğini silin. Çalışan işler kendi kopyalarını tutar ancak bunları kaydedemez; aynı anahtara sahip sonraki işler boş başlar. | `account_handle`, `volume_id` |

Listeler `page` ve `page_size` (en fazla 100) kabul eder. Birim envanteri ayrıca `name` ve `repository` (tam eşleşmeler, AND ile birleştirilmiş), `sort_by` (`volume`, `repository`, `used_space`, `capacity`, `last_used`) ve `sort_order` (`asc`, `desc`) kabul eder. Bilinmeyen ölçümler ve isabet sonuçları `null` olarak kalır. Önbellek durumu, iş başarısını değil, birim değişikliklerinin kaydedilip kaydedilmediğini açıklar.

#### Kum havuzları

Kum havuzu araçları, Kum Havuzları gösterge paneliyle aynı verilere ve eylemlere, [API](https://tuist.dev/api/docs) ile aynı erişime sahiptir: hesap üyeleri hesaptaki her kum havuzunda her aracı kullanabilir. Salt okunur görüntüleyiciler bunları kullanamaz. Hesabın kum havuzlarının etkinleştirilmiş olması gerekir. Gösterge panelinin kum havuzu sayfaları salt okunur araçları kaydeder.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_sandboxes` | Kum havuzlarını durumları, şekilleri ve zaman damgalarıyla sayfalandırın. İsteğe bağlı `search` (kum havuzundaki metin, Amp Orb veya Anthropic oturum kimliği), `status`, `vcpus`, `sort_by` (`created`, `last_active`, `identifier`) ve `sort_order`. | `account_handle` |
| `get_sandbox` | Bir kum havuzunun durumu, şekli, düğümü, arşivi ve zaman damgaları. | `account_handle`, `sandbox_id` |
| `get_sandbox_analytics` | vCPU-saatleri, oluşturulan kum havuzları, oturum, kurulum ve başlama süreleri ile hesabın limitlerine karşı tepe vCPU'lar, bellek ve disk, eğilimlerle birlikte. İsteğe bağlı `start` ve `end` (ISO 8601); varsayılan 30 gün, en fazla 90. | `account_handle` |
| `create_sandbox` | Boş bir kum havuzunu başlatın ve çalıştığında döndürün. İsteğe bağlı `platform` (`linux` veya `darwin`), `xcode_version` (bir macOS kum havuzunun tam Xcode sürümü, aracın açıklamasında listelenenlerden; `darwin` anlamına gelir), `repository` (bir macOS kum havuzunun github.com `owner/name`, hesabın projelerinden birine bağlı: Linux Claude Code ortamında bir macOS kurulum betiği olduğunda Mac <.localized_link href="/guides/features/sandboxes/claude#remote-mac-snapshots">hazır anlık görüntüsünden</.localized_link> önyüklenir ve arka planda görüntünün en yeni Pro iPhone simülatörünü önyüklemeye başlar), `template`, `memory_mb` ile `vcpus` (Linux: 2x4096, 4x8192 veya 8x16384, varsayılan 2x4096; macOS: 8x8192, 8x16384 veya 8x24576, varsayılan 8x8192) `workspace_gb` ve `lifetime_seconds` (çalışan komutları iptal edilmeden ve duraklatılıp arşivlenmeden önce ne kadar çalışabileceği, dosyalarını koruyarak: varsayılan iki saat, en fazla bir gün). Açıklaması, aracıya deponun derlediği Xcode'u (`.xcode-version`, mise, CI yapılandırması veya belgeler) bulmasını ve iletmesini söyler; çünkü başka bir Xcode deponun önbelleklerini ve anlık görüntüsünü kaçırır, Mac'in `/opt/tuist/agent-guide.md` konumunda taşıdığı kılavuzu okumasını ve aşağıdaki simülatör araçlarıyla iOS Simülatörü'nde çalışan uygulamayı göstermesini sağlar. Mac'teki Tuist, depo bir sürüm sabitlediğinde o sürümü kullanır ve <.localized_link href="/guides/features/sandboxes#tuist-in-sandbox">hesabın önbelleğini</.localized_link> kendi başına kullanır. | `account_handle` |
| `pause_sandbox` | Çalışan bir kum havuzunun anlık görüntüsünü düğümünün diskine alın. | `account_handle`, `sandbox_id` |
| `resume_sandbox` | Duraklatılmış veya arşivlenmiş bir kum havuzunu devam ettirin. | `account_handle`, `sandbox_id` |
| `extend_sandbox` | Bir kum havuzunun yaşam süresini şimdi yeniden başlatın, isteğe bağlı `lifetime_seconds` ile (en fazla bir gün). Bir entegrasyonun sahibi olduğu kum havuzlarının süresi yoktur. | `account_handle`, `sandbox_id` |
| `archive_sandbox` | Duraklatılmış bir kum havuzunun disklerini nesne depolamaya taşımak için sıraya alın. | `account_handle`, `sandbox_id` |
| `delete_sandbox` | Kullanıcı onayından sonra bir kum havuzunu ve disklerini silin. | `account_handle`, `sandbox_id` |
| `list_sandbox_devices` | Bir kum havuzunun cihazları; `id`, `name`, `platform`, `runtime` ve `state` (`Booted`, `Shutdown`) bilgileriyle. Günümüzde bunlar bir macOS kum havuzunun simülatörleridir, örneğin iOS; Android emülatörleri henüz desteklenmemektedir. | `account_handle`, `sandbox_id` |
| `boot_sandbox_device` | Bir cihazı ada veya kimlikle başlatın ve onun için en fazla 40 saniye bekleyin; bir simülatör Simülatör uygulamasında görünür. Zaten başlatılmış bir cihazı başlatmak başarılı olur. | `account_handle`, `sandbox_id`, `device` |
| `launch_sandbox_app` | Başlatılmış cihazda bir uygulama başlatın, çalışırken yeniden başlatın. İlk olarak yüklemek için kum havuzunda derlenmiş bir .app olan `app_path` öğesini iletin veya yüklü bir uygulama için `app_id` (iOS'ta paket kimliği) kullanın. Birden fazla cihaz başlatıldığında isteğe bağlı `device`. | `account_handle`, `sandbox_id` |
| `open_sandbox_url` | Tarayıcıda (iOS'ta Safari) bir web sayfasını veya başlatılmış cihazda bir uygulamanın derin bağlantısını açın. İsteğe bağlı `device`. | `account_handle`, `sandbox_id`, `url` |
| `get_sandbox_screenshot` | Başlatılmış cihazı veya `target: screen` ile kum havuzunun tüm ekranını bir görüntü olarak döndürün: ajanın bağlamına sığması için uzun kenarında en fazla 1600 piksel olan bir JPEG. İsteğe bağlı `device`. Diskteki tam boyutlu PNG için `tuist sandbox screenshot` kullanın. | `account_handle`, `sandbox_id` |

Cihaz araçları kum havuzunda sabit komutları çalıştırır; sizin ilettiğiniz komutları çalıştırmaz, bunu yalnızca CLI'nin `tuist sandbox exec` yapar. Linux kum havuzunda `devices_unsupported`, bir cihaz başlatılana kadar `device_not_booted`, kum havuzunun sahip olmadığı bir ad veya kimlik için `device_not_found` ve eksik `app_path` veya yüklü olmayan bir uygulama için `app_not_found` yanıtını verirler.

Bir kum havuzu aracının hatası, kendi satırında `code: fleet_busy` gibi kararlı bir kodla başlar, ardından ne yapılacağı gelir; bekleme içeren kodlar bir `retry_after_seconds:` satırı ekler. API, hata gövdesinde aynı `code` kodunu gönderir. Her ana bilgisayar meşgul olduğunda, `create_sandbox` `fleet_busy` yanıtını vermeden önce biri için en fazla 25 saniye bekler.

#### Amp çalışma alanları

Bu araçlar, orb'ların jeton olmadan Tuist'te oturum açmasını sağlayan <.localized_link href="/guides/server/authentication#amp-orbs">Amp çalışma alanı bağlantılarını</.localized_link> yönetir. Kontrol panelinin Entegrasyonlar sayfasıyla aynı yalnızca yönetici iznini kullanırlar. Bir orb içindeki bir ajan, kendi kimliklerini `$AMP_WORKSPACE_ID` ve `$AMP_PROJECT_ID` üzerinden okuyabilir. Bir bağlantının kabul ettiği her orb, hesaptaki tüm projelere CI erişimi kazanır; bu nedenle ajanların bağlanmadan önce kullanıcıyla onaylaması gerekir.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_amp_workspace_connections` | Hesabın bağlı Amp çalışma alanlarını ve her birinin sınırlı olduğu projeyi (varsa) listeleyin. | `account_handle` |
| `connect_amp_workspace` | Bir Amp çalışma alanını bağlayın. İsteğe bağlı `project_id`, oturum açmayı tek bir Amp projesinin orb'larıyla sınırlar. | `account_handle`, `workspace_id` |
| `disconnect_amp_workspace` | Bir çalışma alanının bağlantısını kesin. Orb'larının zaten sahip olduğu oturumlar süresi dolana kadar geçerli kalır. | `account_handle`, `connection_id` |

#### Claude ortamları

Bu araçlar, Claude Yönetilen Ajanların kendi kendine barındırılan ortamlarını bağlar, böylece oturumları Ayarlar → Entegrasyonlar → Claude'da olduğu gibi Tuist kum havuzlarında çalışır. Hesap yönetimi ve kum havuzlarının etkinleştirilmesini gerektirirler. Bir ajan, Anthropic'in API'sini kullanarak ortamı oluşturabilir, ancak ortam anahtarını yalnızca Claude Konsolu oluşturur; bu nedenle ajan kullanıcıdan bunu ister. Tuist, oturumları bir Anthropic API anahtarı veya iş yükü kimliği federasyonu ile başlatır ve kaydetmeden önce ortamı bu kimlik bilgisiyle getirir. Anthropic tarafındaki kurulum, kullanıcının kendi Anthropic kimlik bilgilerini kullanır; Tuist bunları asla almaz. Anahtarlar istemci ve model üzerinden geçtiği için bunları yalnızca açıkça sağlayın.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_claude_environments` | Bağlı ortamları ve her birinin kullandığı kimlik bilgisini, ayrıca bir federasyon kuralının güvenmesi gereken yayıncı URL'sini ve konu önekini listeleyin. | `account_handle` |
| `connect_claude_environment` | Bir ortamı `api_key` ile veya `organization_id`, `workspace_id`, `service_account_id` ve `federation_rule_id` ile bağlayın. İsteğe bağlı `platform`, `vcpus` ve `memory_mb` kum havuzu şeklini belirler. | `account_handle`, `environment_id`, `environment_key` |

#### Kuruluş Yapay Zekası

Bu araçlar, bir kuruluşun sunucu tarafı yapay zeka görevlerinin kullandığı modelleri Ayarlar → Yapay Zeka'da olduğu gibi yönetir ve kurallarını paylaşır: yalnızca kuruluş yöneticileri için ve yalnızca yapay zeka ayarlarına sahip kuruluşlar için. Her görev, örneğin `pulse_grouping` veya `pulse_explanation`, varsa görev rotasını, yoksa varsayılan modeli kullanır; ikisi de yoksa istek göndermez. Her araç, her görevin mevcut modelini ve bunun rotasından, varsayılandan mı yoksa hiçbir yerden mi geldiğini içeren tüm yapılandırmayı döndürür. Bir sağlayıcı eklemek veya düzenlemek bir API anahtarı gerektirdiğinden, bu işlem kontrol panelinde veya REST API'sinde (`/api/accounts/{handle}/ai`) gerçekleşir, bu araçlar aracılığıyla değil.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `get_organization_ai_configuration` | Sağlayıcıları (anahtarlar olmadan), modelleri, varsayılan modeli, görev rotalarını ve her görevin mevcut modelini okuyun. | `account_handle` |
| `save_organization_ai_model` | Bir model ekleyin (`name`, `provider_id`, `upstream_model_id`) veya `id` ile birini güncelleyin. | `account_handle` |
| `remove_organization_ai_model` | Bir modeli ve onun görev rotalarını kaldırın. | `account_handle`, `model_id` |
| `set_organization_ai_default_model` | Varsayılan modeli seçin veya null ile temizleyin. | `account_handle`, `model_id` |
| `save_organization_ai_task_route` | Bir `task` öğesini yapılandırılmış bir `model_id` öğesine yönlendirin veya `id` ile bir rotayı güncelleyin. Bir görevin en fazla bir rotası olabilir. | `account_handle` |
| `remove_organization_ai_task_route` | Bir rotayı kaldırın, böylece görev tekrar varsayılan modeli kullanır. | `account_handle`, `route_id` |
| `remove_organization_ai_provider` | Bir sağlayıcıyı anahtarı, modelleri ve onların rotalarıyla birlikte kaldırın; bağlı bir Claude kuruluşunun bağlantısını keser. | `account_handle`, `provider_id` |

#### Web Kancaları

Web kanca araçları, kontrol paneliyle aynı yalnızca yönetici iznini kullanır. Teslimat denemeleri, uç nokta için kaydedilen istek ve yanıt verilerini içerir, ancak uç nokta imzalama gizli anahtarını asla içermez.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_webhook_endpoints` | Bir hesap için web kanca uç noktalarını listeleyin. | `account_handle` |
| `get_webhook_endpoint` | Bir web kanca uç noktasını alın. | `account_handle`, `webhook_endpoint_id` |
| `list_webhook_delivery_attempts` | Bir uç nokta için teslimat denemelerini listeleyin. | `account_handle`, `webhook_endpoint_id` |
| `get_webhook_delivery_attempt` | Bir teslimat denemesini alın. | `account_handle`, `webhook_endpoint_id`, `delivery_attempt_id` |

#### Xcode derlemeleri

Xcode, Gradle, Bazel, Mix ve Cargo için derleme ayrıntısı araçları, bildirildiğinde altyapı gözlemleri dahil olmak üzere mevcut `custom_metadata: {tags, values}` yapısını ortaya çıkarır. Değerler dize olarak kalır ve bilinmeyen anahtarlar korunur. Örneğin, `tuist.cpu.available_processors` çalışma zamanında kullanılabilen mantıksal işlemcileri tanımlarken, `tuist.gradle.max_workers` bir Gradle çalışan sınırıdır ve `tuist.jvm.max_heap_bytes` bir JVM yığın sınırıdır, ana makine belleği değildir. Bunlar güvenilir olmayan istemci gözlemleridir, doğrulanmış çalıştırıcı kimlikleri değildir. Eksik gözlemler eksik kalır; içe aktarılan günlükler ve daha eski istemcilerde altyapı meta verileri olmayabilir. Struo meta verileri koordineli bir istemci/protokol güncellemesini bekliyor.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_xcode_builds` | Bir proje için Xcode derleme çalıştırmalarını listeleyin. | `account_handle`, `project_handle` |
| `get_xcode_build` | Belirli bir Xcode derleme çalıştırması hakkında, ham `.xcactivitylog` içeren arşiv için geçici bir indirme URL'si dahil olmak üzere ayrıntılı bilgi alın. | `build_run_id` |
| `list_xcode_build_targets` | Belirli bir Xcode derleme çalıştırması için derleme hedeflerini listeleyin. | `build_run_id` |
| `list_xcode_build_files` | Belirli bir Xcode derleme çalıştırması için derlenmiş dosyaları listeleyin. | `build_run_id` |
| `list_xcode_build_steps` | Günlük metni olmadan, zamanlamalar ve sonuçlarla kaydedilmiş derleme adımlarını listeleyin. | `build_run_id` |
| `get_xcode_build_step` | Günlüğü ve kesme bayrağı dahil olmak üzere tek bir kaydedilmiş derleme adımını alın. | `build_run_id`, `step_id` |
| `list_xcode_build_issues` | Belirli bir derleme çalıştırması için derleme sorunlarını (uyarılar ve hatalar) listeleyin. | `build_run_id` |
| `list_xcode_build_cache_tasks` | Belirli bir Xcode derleme çalıştırması için önbelleklenebilir görevleri (önbellek isabetleri/ıskaatları) listeleyin. | `build_run_id` |
| `list_xcode_build_cas_outputs` | Belirli bir Xcode derleme çalıştırması için [içerik adreslenebilir depolama](https://en.wikipedia.org/wiki/Content-addressable_storage) çıktılarını listeleyin. | `build_run_id` |

`list_xcode_build_steps`, varsayılan olarak 20 adımdan oluşan sayfalar döndürür (maksimum 100, `page_size` aracılığıyla), gezinme için `page` ve `pagination_metadata` ile. Başlıkları, projeleri veya hedefleri eşleştirmek için `search` kullanın veya tam `project`, `target`, `category` (örneğin, `swiftCompilation`) ve `status` (`success` veya `failure`) filtreleyin. En yavaş olanı önce getirmek için `duration_ms` ile veya kronolojik sıra için `start_ms` ile sıralayın. Adım kimlikleri beraberlikleri bozar ve 64 bitlik hassasiyetlerinin tamamını korumak için ondalık dizeler olarak döndürülür. Kimlikler bir derlemeye özeldir ve derlemeler arasında eşleştirilmemelidir.

İsteğe bağlı `start_ms` ve `end_ms`, derleme başlangıcından itibaren milisaniye cinsinden bir zaman aralığıyla örtüşen adımları seçer; bitiş hariçtir. Her iki araç da `build_run_id` olarak bir derleme UUID'sini veya kontrol paneli URL'sini kabul eder. Döndürülen adım `id` değerini, günlüğünü almak için `step_id` olarak değiştirilmeden iletin. Günlükler adım başına en fazla 64 KiB tutar, `log_truncated` atlanan çıktıyı belirtir.

Adımlar, Xcode derlemeleri işlendiğinde varsayılan olarak toplanır. Kaydedilmiş adım verileri 90 gün boyunca saklanır. Liste yanıtı `availability` içerir: filtreler hiçbirini eşleştirmese bile kaydedilmiş adımlar varsa `available`; derleme hala işleniyorsa ve henüz adım yoksa `processing`; veya adımlar kaydedilmediyse ya da süresi dolduysa `unavailable`.

Aynı işlemler, aynı filtreler ve sayfalama ile `GET /api/projects/{account_handle}/{project_handle}/xcode/builds/{build_id}/steps` ve `GET /api/projects/{account_handle}/{project_handle}/xcode/builds/{build_id}/steps/{step_id}` adreslerinde HTTP API üzerinden kullanılabilir. Her ikisi de derlemenin projesine okuma erişimi gerektirir.

#### Gradle derlemeleri

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `get_gradle_integration_guide` | Tam kimlik doğrulama, proje kurulumu, Gradle eklentisi, önbellek politikası ve iki derlemeli doğrulama iş akışını döndürün. Aracılar, mevcut bir Android veya Gradle projesini düzenlemeden önce bunu çağırmalıdır. | Yok |
| `list_gradle_builds` | Özel meta veriler dahil olmak üzere bir proje için Gradle derleme çalıştırmalarını listeleyin. İsteğe bağlı `tag` parametresiyle özel bir etikete göre filtreleyin. | `account_handle`, `project_handle` |
| `get_gradle_build` | Derleme meta verilerini, görev/önbellek sayılarını ve `failures` öğesini alın: başarısız olan her görevin ve yapılandırma adımının hata mesajı. | `build_run_id` |
| `list_gradle_build_tasks` | Görev sonuçlarını, bileşik derleme kimliğini, önbelleklenebilirliği, artımlı durumu ve hata mesajlarını listeleyin. | `build_run_id` |
| `list_gradle_build_steps` | Arama, meta veri ve örtüşen zaman filtreleriyle zamanlanmış görevleri, yapılandırmayı ve dönüşümleri listeleyin. | `build_run_id` |
| `get_gradle_build_step` | Opak kimliğe göre kaydedilmiş adım meta verilerini inceleyin; başarısız bir görevin veya yapılandırma adımının `log`, onun hata mesajıdır. | `build_run_id`, `step_id` |

Gradle ve Bazel adım listeleri varsayılan olarak 20 sonuç döndürür (maksimum 100), `search`, tam `project`, `target`, `category` ve `status`, örtüşen `start_ms` / `end_ms` filtrelerini (bitiş hariç) ve `duration_ms` veya `start_ms` sıralamasını destekler. Döndürülen kimlikleri değiştirilmeden iletin; bunlar kendi derlemelerine özeldir. Listeler `time_origin` ve `coverage` gösterir. Daha eski Gradle raporları, derleme başlangıcı yüklenmediği için `first_recorded_timestamp` kullanır. Bazel profilleri, tüm kaydedilmiş aralıkları `trace_profile` kapsamıyla ve zaman kökeni olarak `profile_start` ile ortaya çıkarır. Daha eski derlemeler, saklanan BEP özetlerine geri döner. Kaynak kayıtları 90 gün sonra sona erer. Bazel ayrıntıları, yayınlandığında temizlenmiş eylem günlüklerini içerir. Başarısız bir görevin veya yapılandırma adımının Gradle ayrıntıları, Tuist Gradle eklentisinin `log` olarak bildirdiği hata mesajını içerir: Gradle'ın konsolunun yazdırdığı şekilde istisna mesajı ve neden zinciri, yığın izleri veya görev çıktısı olmadan, proje içindeki yollar göreceli hale getirilmiş ve kimlik bilgileri ile diğer yerel yollar sansürlenmiş, adım başına en fazla 16 KiB ve derleme başına 32 başarısız adım. Diğer Gradle adımları, daha eski eklenti sürümleri tarafından bildirilen derlemeler ve kimlik bilgisi içermeyen raporlar null `log` değerine sahiptir. Yapılandırma adımları, başarısız olduklarında `failure` ve aksi takdirde `unknown` bildirir. `compare_builds` istemi, tam Bazel izlerini saklanan özetlerden ayırt etmek için bu kapsamı kullanır ve daha geniş çağrı çıktısını kontrol etmeden önce eylem sonuçları ve günlükler için adımları aracıların dikkatine sunar.

Tek adımlı araçlar `get_gradle_build_step` ve `get_bazel_build_step` bir adımı kimliğe göre alır ve zaman filtrelerini kabul etmez; adımları zaman aralığına göre filtrelemek için ilgili liste araçlarını kullanın.

Saklanan özetlerden döndürülen Bazel adım kimlikleri, bir adım listelenip alındıktan sonra tam bir profil gelirse okunabilir kalır. Adım verilerinin süresi dolmuş indekslenmiş bir profil, kullanılamıyor olarak bildirilir. Gradle adım listeleri, sıfır süreli önbelleklenmiş ve atlanan işlemleri içerir.

#### Bazel çağrıları

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `get_bazel_integration_guide` | Kimlik doğrulama, proje kurulumu, Bazel yapılandırması ve doğrulama iş akışını döndürün. | Yok |
| `list_bazel_invocations` | Tamamlanan [Bazel Derleme Olay Protokolü](https://bazel.build/remote/bep) çağrılarını en yeniden eskiye doğru, derleme metrikleri, sınırlı bir yürütme zaman çizelgesi, kritik yol tanılama ve bir proje için ilişkili uzak önbellek toplamlarıyla listeleyin. `status`, `git_branch`, `git_commit_sha`, `is_ci` ve `command` ile filtreleyin. | `account_handle`, `project_handle` |
| `get_bazel_invocation` | Derleme metrikleri, sınırlı bir yürütme zaman çizelgesi, kritik yol tanılama ve ilişkili uzak önbellek toplamları ile tek bir tamamlanmış Bazel çağrısını alın. | `account_handle`, `project_handle`, `invocation_id` |
| `list_bazel_build_steps` | Filtreler ve açık kapsam ile kaydedilmiş Bazel profil aralıklarını listeleyin. | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_build_step` | Kaydedilmiş bir Bazel adımını ve yayınlanan eylem sonucunu ve temizlenmiş günlüğünü inceleyin. | `account_handle`, `project_handle`, `invocation_id`, `step_id` |
| `list_bazel_remote_actions` | Tuist uzaktan yürütmenin bir çağrı için çalıştırdığı eylemleri, anımsatıcı, hedef, eylem özeti, çıkış kodu, yürütme yolu ve faz zamanlamalarıyla listeleyin. İsteğe bağlı `sort_by` (`duration` veya `queued_at`), `failed` ve `mnemonic` filtreleri. | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_remote_action` | Tek bir uzak eylemin argv değerini, ortamını (gizli gibi görünen değerler maskelenmiş), platformunu, çalışma dizinini, çıktı yollarını, çalışanını, çıkış kodunu, stdout ve stderr'in ilk 16 KiB'ini, stderr'de tanınan derleyici `errors` hatalarını, faz zamanlamalarını ve eylem özetini alın. | `account_handle`, `project_handle`, `invocation_id`, `action_id` |
| `get_bazel_remote_action_log` | Uzak bir eylemin stdout veya stderr'inin bayt ofsetine göre en fazla 64 KiB'ini okuyun, varsayılan olarak akışın sonu. Uzun akışlar tamamen kopyalanır veya daha uzun olduklarında ilk 16 KiB'lerini ve son 16 MiB'lerini korur; `recorded` mevcut aralıkları listeler. | `account_handle`, `project_handle`, `invocation_id`, `action_id`, `stream` |
| `list_bazel_invocation_logs` | Bir Bazel çağrısı için yakalanan temizlenmiş günlükleri yürütme sırasına göre listeleyin: Bazel'in ilerleme çıktısının sınırlı kuyruk kısmı ve `test.log` yapıtları. İsteğe bağlı `stream` (`stdout` veya `stderr`), `source` (`progress` veya `test_log`), `target_label` ve `errors` filtreleri sonuçları daraltır. | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_invocation_log` | Bir Bazel çağrısı için yakalanan tek bir temizlenmiş günlük parçasını alın. | `account_handle`, `project_handle`, `invocation_id`, `invocation_log_id` |
| `list_bazel_cache_events` | İşlem, uç nokta ve gözlem zamanıyla birlikte ham Bazel uzak önbellek gözlemlerini listeleyin; isteğe bağlı olarak bir çağrı, sonuç veya işlemle daraltılabilir. | `account_handle`, `project_handle` |
| `get_bazel_cache_event` | Tek bir ham Bazel uzak önbellek gözlemini alın. | `account_handle`, `project_handle`, `cache_event_id` |

#### Uzaktan yürütme

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `get_remote_execution_activity` | Projenin çalışan Bazel çağrılarını ve şu anda çalışan ile kuyruktaki uzak eylemlerini, her eylemin çağrısı, anımsatıcısı, hedefi, eylem özeti, makine boyutu ve bu duruma ne zaman girdiği bilgileriyle listeleyin. Yürütme ağ geçidinin önceden hazırladığı bir sanal makinede çalıştırdığı eylemler tamamlanana kadar listelenmez. | `account_handle`, `project_handle` |
| `get_remote_execution_usage` | Projenin uzaktan yürütmelerini ve `[from, to)` aralığında ölçülen yürütme süresini toplamda, makine boyutuna göre, dağıtım moduna göre ve saat, gün veya ay bazında alın. Dönem varsayılan olarak son 30 gündür ve en fazla 366 günü kapsar. | `account_handle`, `project_handle` |

`list_bazel_invocations` filtreleri tam eşleşmedir ve aynı saniyede biten çağrılar çağrı kimliğine göre sıralanır. Bir dalda en son başarısız olan çağrıyı bulmak için `status: "failure"`, `git_branch` ve `page_size: 1` ile çağırın. REST uç noktası `GET /api/projects/{account_handle}/{project_handle}/bazel/invocations` aynı filtreleri kabul eder.

Yalnızca indekslenmiş profillerden güvenli bir şekilde ilişkili sunucu faz zamanlamalarına sahip eylemleri döndürmek için `list_bazel_build_steps` üzerinde `remote_execution: true` ayarlayın. Liste ve detay yanıtları, isteğe bağlı olarak null olabilen `remote_queue_ms`, `remote_input_fetch_ms`, `remote_execution_ms` ve `remote_output_upload_ms` değerlerini sunar. Değerler, eylem içindeki yeniden denemeler dahil olmak üzere kaydedilen fazların toplamını verir; eksik veya null değerler sıfır değil, kullanılamaz anlamına gelir. Bunlar profil gözlemleridir, faturalandırılabilir kullanım veya yeni yürütme kanıtı değildir, çünkü önbelleklenmiş sunucu sonuçları yürütme meta verileri taşıyabilir. İstemci yüklemeleri hariç tutulur. Eski veya belirsiz profiller, uzak iş gerçekleşmiş olsa bile eşleşen eylem döndürmeyebilir. Adım REST uç noktası aynı `remote_execution=true` filtresini kabul eder. Kontrol panelinin Uzaktan yürütme sekmesi aynı sorguyu ve 90 günlük saklama süresini kullanır.

Test günlükleri, geldikleri test sonucunun `target_label` ve deneme `status` bilgisini taşır, bu nedenle `target_label: "//foo:bar_test"` yalnızca o hedefin test günlüklerini döndürür. `errors: true`, başarısız denemelerin test günlüklerini ve Bazel raporlayıcısının `ERROR:`, `FAIL:` veya `TIMEOUT:` ile başladığı bir satır içeren stderr ilerleme parçalarını döndürür. İlerleme çıktısı hedeflere atanmaz ve atama kaydedilmeden önce yazılan günlüklerin alanları boştur. Başarısız eylemler ve kendi çıktıları `list_bazel_build_steps` üzerinden hedef başına, test durumu başına başarısızlıklar ise test çalıştırma araçlarından erişilebilir.

#### Cargo derlemeleri

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_cargo_builds` | Bir proje için Cargo derlemelerini en yeniden eskiye doğru listeleyin. `git_branch`, `status`, `is_ci` veya `command` ile filtreleyin. Cargo test yürütme sonuçları bu derleme listesi üzerinden değil, test araçları üzerinden erişilebilir. | `account_handle`, `project_handle` |
| `get_cargo_build` | Derleme meta verilerini, toplam önbellek sayaçlarını ve tanılama bilgileriyle birlikte en fazla 500 kaydedilmiş derleyici işini alın. `compilations_truncated` atlanan işleri gösterir; tanılama yalnızca döndürülen işleri kapsar. | `account_handle`, `project_handle`, `build_id` |

Doğrulanmış görev kararlarını ve CAS işlemlerini almak, 4 MB ile sınırlı olmak üzere, `get_cargo_build` üzerinde `include_cache_inspection: true` ayarlayın. Varsayılan olarak ve kayıtlar eksik veya geçersiz olduğunda `cache_inspection` null olur. Kısmi yakalama `truncated` bayrağına saygı gösterin; aktarımlar her görev isabetinin yerel/uzak kökenini belirlemez. HTTP detay uç noktası aynı sorgu parametresini kabul eder.

#### Mix derlemeleri

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_mix_builds` | Bir proje için Mix (Elixir) derleme derlemelerini, özel meta veriler dahil, en yeniden eskiye doğru listeleyin. `git_branch`, `status`, `is_ci` veya `mix_env` ile filtreleyin. | `account_handle`, `project_handle` |
| `get_mix_build` | Derleme meta verilerini, tanılama sayılarını ve bağımlılık önbellek özetini alın. | `account_handle`, `project_handle`, `build_id` |

#### Derleme izleri

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `get_build_trace` | Bir Xcode, Gradle, Bazel veya Mix derlemesinin zaman çizelgesini [Perfetto](https://ui.perfetto.dev) içinde açabileceğiniz bir iz dosyası olarak indirmek için bir bağlantı alın. | `account_handle`, `project_handle`, `build_id` |

`build_id`, derleme çalıştırma kimliğidir (Bazel için çağrı kimliği) veya derlemenin kontrol paneli URL'sidir. Döndürülen `trace_url`, bir [Chrome Trace Event](https://docs.google.com/document/d/1CvAClvFfyA5R-PhYUmn5OOQtYMH4h6I0nSsKchNAySU) JSON dosyası sunar. Bağlantıya sahip olan herkes, aramadan bir saat sonra gelen `expires_at` tarihine kadar başka kimlik bilgileri olmadan o derlemenin izini indirebilir. Ajanlar bunu `curl` ile indirebilir, Perfetto'da açmanız için size verebilir veya Perfetto'nun `trace_processor` ile sorgulayabilir. İz, paralellikle şeritlere paketlenmiş kaydedilmiş adımları, tüm derlemeyi kapsayan bir izi ve derleme makine metriklerini kaydettiğinde CPU ve bellek sayaçlarını içerir. Günlükler hariç, yukarıdaki adım araçlarıyla aynı veriyi tutar. Kontrol paneli, her derlemenin Zaman Çizelgesi sekmesinden aynı dosyayı sunar.

#### Struo çalıştırmaları

<a id="once-runs"></a>

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_once_runs` | Bir proje için Struo çalıştırmalarını en yeniden eskiye doğru listeleyin. `kind` (`build`, `test` veya `generic`), `status`, `is_ci` veya `git_branch` ile filtreleyin. Tamamlanmamış çalıştırmaların durumu `in_progress` olur. | `account_handle`, `project_handle` |
| `get_once_run` | Bir çalıştırmayı, eylem toplamları, önbellek özeti ve test çalıştırmaları için test toplamlarıyla birlikte alın. | `account_handle`, `project_handle`, `run_id` |

Cargo derleme, Mix derleme ve Struo çalıştırma kimlikleri bir proje içinde benzersizdir. Aynı okumalar HTTP API üzerinden `GET /api/projects/{account_handle}/{project_handle}/cargo/builds`, `.../mix/builds` ve `.../once/runs` adreslerinde mevcuttur; her biri tek bir kimlik için bir detay uç noktasına sahiptir.

#### Görevler, eylemler, modüller ve dosyalar

Bu proje kapsamlı araçlar, çalıştırmalar arasındaki kalıcı derleme kimliklerini inceler. `list_build_entities` ile başlayın, ardından döndürülen kararlı bir `id` değerini aynı `kind` ile birlikte `get_build_entity` veya `list_build_entity_history` uç noktalarına, `account_handle` ve `project_handle` parametreleriyle iletin. Derleme veya çağrı kimliği gerekmez.

| Araç | Açıklama | Gerekli parametreler |
| --- | --- | --- |
| `list_build_entities` | Bir projenin derlemeleri arasında görülen tek bir türdeki görevleri, modülleri, eylemleri veya dosyaları listeleyin. | `account_handle`, `project_handle`, `kind` |
| `get_build_entity` | Seçilen dönem için yerel kimliği ve analitik verileriyle birlikte tek bir derleme varlığını alın. | `account_handle`, `project_handle`, `kind`, `id` |
| `list_build_entity_history` | Tek bir derleme varlığının kaydedilmiş yürütmelerini, derlemelerini veya önbellek olaylarını en yeniden eskiye doğru listeleyin. | `account_handle`, `project_handle`, `kind`, `id` |

| `kind` | Araç zinciri | Geçmiş listeleri |
| --- | --- | --- |
| `bazel_actions` | Bazel eylemleri | BEP tarafından bildirilen eylem yürütmeleri |
| `gradle_tasks` | Gradle görevleri | Görev yürütmeleri |
| `xcode_modules` | Xcode modülleri | Derlemeler ve modül önbelleği olayları |
| `once_actions` | Struo eylemleri | Yürütmeler |
| `mix_files` | Mix derlenmiş dosyalar | Derlemeler |
| `mix_modules` | Mix derlenmiş modüller | Derlemeler |
| `cargo_crates` | Cargo paketleri | Kaydedilmiş rustc çağrıları |

Bu araçlar kademeli olarak sunulmaktadır ve yalnızca etkinleştirildiği projeler için veri döndürür; diğer projeler için boş sonuç yerine hata döndürür. Bir tür, yalnızca ilgili derleme araç zincirini kullanan projeler için kullanılabilir. Araçlar sınırlı `start_at`/`end_at` filtrelerini, `environment` (`any`, `ci` veya `local`) ve tam eşleşen bir `branch` kabul eder. `list_build_entities`, `q` parametresini kabul eder; `list_build_entity_history` ise şeffaf olmayan `after`/`before` imleçlerini destekler. Bilinmeyen zamanlama veya önbellek gözlemleri sıfır veya isabetsizlik olarak değil, mevcut değil olarak kalır. Geçmiş, mevcut çalıştırma araçlarını kullanarak detaylı inceleme yapmak üzere kaydedilen üst öğeyi ve yerel yürütmeyi referans alır.

`get_build_entity` metrikleri, kaydedilmiş zamanlamaya sahip gözlem sayısını içeren `duration_samples` değerini içerir: Gerçek sıfır süreler sayılır, eksik zamanlama sayılmaz. Bu sayı, gözlem sayısından daha düşük olabilir; mevcut olmayan süre istatistikleri null olarak kalır.

Xcode modül süreleri, derleme günlüklerindeki ölçülen hedef derlemelerden gelir. Modül önbelleği çözümleri ve derleme işi olmayan hedefler süre örneklerine katkıda bulunmaz. Derleme gözlemleri Xcode derlemesini; önbellek olayları ise oluşturma veya önbellek komutunu referans alır.

Bazel eylemleri, hedef etiketi, anımsatıcı ve yapılandırılmış birincil çıktı ile tanımlanır; girişe bağlı önbellek özetlerine güvenmeden ayrı eylemleri ve yapılandırmaları distinct tutar. Geçmiş, BEP tarafından bildirilen yürütmeleri kaydeder, önbellek aramalarını veya iz profili aşamalarını değil. Tam yürütme kapsamı `--build_event_publish_all_actions` gerektirir; yapıt teslimi en iyi çaba ile yapılır, bu nedenle eksik gözlemler hiçbir işin çalışmadığına dair kanıt değildir. Kararlı kimliği veya yürütme başlangıcı olmayan eski Kura yükleri kabul edilir ancak indekslenmez. Eksik bitiş zamanı ölçümleri mevcut değil olarak kalır ve gerçek sıfır süreler sayılır.

Mix modül süreleri, bağımsız olarak ölçülen modül işini değil, içeren dosyanın derlenmesini ölçer. Struo eylemleri, istemci hedef eşlemelerini bildirdiğinde bildirilen hedef/yetenek/dizin yuvalarını kullanır; tanılama etiketleri tek başına kararlı kimlikler değildir. Mevcut istemciler ve çalıştırma düzeyi araçları değişmeden desteklenmeye devam eder.

Cargo paketleri, tam olarak kaydedilen paket kökü, adı ve türüne göre gruplandırılır. Checkout yolu değişiklikleri geçmişleri bölebilir ve derleme profilleri, özellikler ve hedef üçlüleri ayırt edilmez. Geçmiş, rustc çağrılarını ölçer, dosya başına işi veya önbellek isabetlerini değil; eksik işler kaldırılmaları veya tam bir çalışma alanı envanterini kanıtlamaz.

Analitik okumalarının sınırlı bellek ve yürütme süresi vardır. Bir sorgu bu sınırları aşarsa, araç boş bir sonuç uydurmak yerine hata döndürür.

Yeni gözlemler dağıtımdan sonra indekslenir; bu özellik mevcut çalıştırma telemetrisini geriye dönük doldurmaz. Kimlik meta verileri, <.localized_link href="/guides/server/data-retention">veri saklama politikası</.localized_link> kapsamında bireysel gözlemlerden daha uzun süre saklanır.

#### Testler

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_test_runs` | Bir proje için test çalıştırmalarını, her biri kendi `selective_testing_strategy` ile birlikte listeleyin. `selective_testing` ile filtreleyin (`coverage`, kapsama tabanlı seçimin geri dönüşlerini içerir, veya `module_hash`). `query` alanları `git_branch`, `scheme`, `status` ve `selective_testing` şeklindedir: `field:"value"` tam eşleşir, `field~"value"` büyük/küçük harf duyarsız bir alt dizeyle eşleşir (`selective_testing` üzerinde değil) ve baştaki `-` operatörün tersini alır. Örneğin, `-git_branch~"gh-readonly-queue"` birleştirme kuyruğu dallarını hariç tutar. Boşlukla ayrılmış sorgu filtreleri ve açık argümanlar AND mantığıyla birleşir. | `account_handle`, `project_handle` |
| `get_test_run` | Bir test çalıştırması için, kendi kod kapsamı (`coverage`: herhangi bir ölçüm yapılıp yapılmadığı, satırları ve figürü, kısmi olup olmadığı veya kirli bir checkout'tan çalışıp çalışmadığı), seçici test özeti (`selective_testing`: strateji, temel commit ve istenen, seçilen, atlanan ve tahmini test sayıları; test seçimi etkinliğinin hesaplandığı değerler) ve sonuç paketi (`.xcresult`) ile onu çalıştıran komutun oturum arşivi (CLI günlükleri) için geçici indirme URL'lerini veya çalıştırmaya bağlı komut yoksa `null` değerini içeren ayrıntılı metrikleri alın. Parçalı bir çalıştırmanın `result_bundle_url`, ilk raporlayan parçanın paketidir; `shard_result_bundles`, CI yeniden denemeleri dahil olmak üzere her parça raporu için bir paketi, parça dizini ve durumuyla birlikte listeler, böylece başarısız testi olmayan ancak başarısız olan bir parça incelenebilir. | `test_run_id` |
| `list_test_module_runs` | Belirli bir test çalıştırması için test modülü çalıştırmalarını listeleyin. | `test_run_id` |
| `list_test_suite_runs` | Belirli bir test çalıştırması için test suite çalıştırmalarını, isteğe bağlı olarak modüle göre filtrelenmiş şekilde listeleyin. | `test_run_id` |
| `list_test_cases` | Bir proje için test senaryolarını listeleyin (`flaky` gibi filtreleri destekler). | `account_handle`, `project_handle` |
| `get_test_case` | Güvenilirlik oranı, kararsızlık oranı ve çalıştırma sayıları dahil olmak üzere bir test senaryosu için ayrıntılı metrikleri alın. | `test_case_id` veya `identifier` + `account_handle` + `project_handle` |
| `list_test_case_runs` | Test senaryosu çalıştırmalarını, isteğe bağlı olarak test senaryosuna veya test çalıştırmasına göre filtrelenmiş şekilde listeleyin. | `account_handle`, `project_handle` |
| `get_test_case_run` | Belirli bir test senaryosu çalıştırması için hata ayrıntılarını ve tekrarları alın; ayrıca, çalıştırmanın kapsama tabanlı seçimi testi koruduysa nedenini (`selective_testing`: karar, neden, eşleşen değişen dosya ve parça) öğrenin. | `test_case_run_id` |
| `list_test_case_run_attachments` | Bir test senaryosu çalıştırması için ekleri listeleyin. Her ek, geçici bir indirme URL'si içerir. | `test_case_run_id` |
| `list_test_case_events` | Bir test senaryosundaki durum değişikliklerini, örneğin sessize alma veya atlama işlemlerini listeleyin. | `test_case_id` |
| `update_test_case` | Bir test senaryosunun durumunu veya kararsız sınıflandırmasını güncelleyin. Bir değişiklik, harici hizmetler dahil olmak üzere yapılandırılmış webhook uç noktalarına bir olay gönderebilir. | `test_case_id` veya `identifier` + `account_handle` + `project_handle` |
| `list_xcode_test_targets` | Bir test çalıştırması için seçici test hedef sonuçlarını listeleyin. | `test_run_id` |
| `list_selective_testing_tests` | Bir test çalıştırmasının kapsama tabanlı seçiminin karar verdiği, seçtiği ve atladığı testleri; her kararın nedenini, onu seçen değişen dosyayı, parçasını ve çalıştırmadaki sonucunu içerecek şekilde listeleyin. `decision`, `reason` veya `search` ile filtreleyin. | `test_run_id` |
| `list_selective_testing_changed_files` | Bir test çalıştırmasının kapsama tabanlı seçim temelinden bu yana değişen dosyaları; her birinin kaç testi seçtiğini ve değişimi seçimin geri dönüşüne neden olan izlenen bir dosya olup olmadığını içerecek şekilde listeleyin. | `test_run_id` |
| `get_coverage` | Bir projenin kod kapsamını hedefleriyle birlikte, bir commit'te veya bir dalın en son tamamlanan commit'inde alın. `git_commit_sha` veya `branch` olmadan varsayılan dalı okur. | `account_handle`, `project_handle` |
| `list_coverage_files` | Bir commit'in kod kapsamının ölçtüğü dosyaları, satır kapsamlarıyla birlikte, bir commit'te veya bir dalın en son tamamlanan commit'inde listeleyin. `search`, sıralama ve sayfalama desteklenir. | `account_handle`, `project_handle` |
| `get_coverage_file` | Bir dosyanın kod kapsamını ve fonksiyonlarını, bir commit'te veya bir dalın en son tamamlanan commit'inde alın. Her satırın yürütme sayısını almak için `include_lines` ayarlayın. | `account_handle`, `project_handle`, `path` |
| `list_coverage_branches` | Kod kapsamı olan dalları, varsayılan dal ilk sırada olacak şekilde listeleyin. | `account_handle`, `project_handle` |
| `list_coverage_commits` | Bir dalın commit'lerini; kapsama durumları (`complete`, `incomplete`, `in_progress`, `not_measured`), figürü ve önceki tamamlanan commit'e göre değişikliğiyle birlikte, en yeniden eskiye doğru listeleyin. İmleçlerle sayfalanır. | `account_handle`, `project_handle` |
| `list_coverage_runs` | Bir commit'in veya dalın arkasındaki kod kapsamına sahip test çalıştırmalarını; her biri `full`, `partial` veya `discarded` (kirli checkout) olarak işaretlenmiş şekilde listeleyin. İmleçlerle sayfalanır. | `account_handle`, `project_handle` |
| `list_coverage_targets` | Bir commit'in hedef başına kapsamını, ardından çalıştırmalarının kapsam sayaçları olmadan ikili önbellekten aldığı hedefleri (`measured: false`) listeleyin. `search`, sıralama ve sayfalama desteklenir. | `account_handle`, `project_handle` |

Kod kapsamı araçları, kod kapsamı etkinleştirilmiş hesaplara sunulur.

#### Paketler

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_bundles` | Bir proje için paketleri (uygulama ikililerini) listeleyin. İsteğe bağlı olarak `git_branch` ve `tags` ile filtreleyin (tüm etiketler tam eşleşmelidir). | `account_handle`, `project_handle` |
| `get_bundle` | Özel etiketler dahil olmak üzere belirli bir paket hakkında ayrıntılı bilgi alın. | `bundle_id` |
| `get_bundle_artifact_tree` | Bir paket için tüm yapay ağaç düzlem listesini yoluna göre sıralanmış olarak alın. | `bundle_id` |

`list_bundles`, derleme varyantlarını veya ortamları ayırt etmek için `tags: ["paid", "production"]` kabul eder. Etiketler, büyük/küçük harfe duyarlı, harf, rakam, tire veya alt çizgi içeren etiketlerdir; en fazla 10 etiket ve etiket başına 50 karakter olabilir. Liste ve ayrıntı sonuçları `custom_metadata.tags` içerir. Sayfalama sayıları ve dal filtreleri etiketli sonuçlara uygulanır; `tags` atlanması filtrelensiz davranışı korur. Geçersiz etiket filtreleri sorguyu genişletmek yerine bir hata döndürür.

#### Nesiller

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_generations` | Bir proje için nesil çalıştırmalarını listeleyin. | `account_handle`, `project_handle` |
| `get_generation` | Belirli bir nesil çalıştırması hakkında ayrıntılı bilgi alın. | `generation_id` |

#### Önbellek çalıştırmaları

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_cache_runs` | Bir proje için önbellek çalıştırmalarını listeleyin. | `account_handle`, `project_handle` |
| `get_cache_run` | Belirli bir önbellek çalıştırması hakkında, oturum arşivi (CLI günlükleri) için geçici bir indirme URL'si dahil olmak üzere ayrıntılı bilgi alın. | `cache_run_id` |
| `list_xcode_module_cache_targets` | Bir nesil veya önbellek çalıştırması için modül önbelleği hedeflerini; hedef başına önbellek isabeti/ıska durumu ve tanılama bileşeni karmalarını, ek karma girdileri dahil ederek listeleyin. | `run_id` |

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
| `get_automation_alert` | Bir otomasyon uyarısını alın. | `alert_id` |
| `list_automation_alert_revisions` | Bir otomasyon uyarısının revizyon geçmişini listeleyin. Eylem kimlik bilgileri gizlenir. | `alert_id` |
| `list_project_notification_alerts` | Proje bildirim uyarı kurallarını listeleyin. Gösterge paneli ayarları sayfasıyla aynı yönetici iznini gerektirir. Webhook adresleri gizlenir. | `account_handle`, `project_handle` |

### Olaylar

Durumsuz `2026-07-28` Model Context Protocol yaşam döngüsünü kullanan istemciler, olayları ve yük şemalarını keşfetmek için `events/list` çağrısı yapabilir:

| Olay | Ne zaman gönderilir | Abonelik filtresi |
|-------|-----------------|---------------------|
| `test_case.marked_flaky` | Bir test senaryosu kararsız olmayan durumdan kararsız duruma geçer. | `account_handle`, `project_handle` |
| `build.failed` | Yerel veya sürekli entegrasyon Xcode, Gradle ya da Bazel derlemesi başarısızlıkla sonuçlanır. | `account_handle`, `project_handle` |
| `test_run.failed` | Yerel veya sürekli entegrasyon test çalıştırması başarısızlıkla sonuçlanır; birleştirilmiş parçalı çalıştırma veya terk edilmiş çalıştırma dahil. | `account_handle`, `project_handle` |
| `ci_job.failed` | Bir Tuist runner işi başarısızlıkla tamamlanır. | `account_handle` |
| `pulse_symptom.opened` | Pulse, board veya page düzeyinde bir semptomu açar veya yeniden açar. Yalnızca audit düzeyinde günlüğe kaydedilen semptomlar ve açık bir semptomdaki sonraki değişiklikler gönderilmez. | `account_handle` |

Abone olmak için istemci, olay adını, yukarıda `arguments` içinde listelenen tutamaçları ve bir `https://` geri çağırma URL'si ile bir `whsec_` imzalama sırrı içeren bir `webhook` teslimatıyla `events/subscribe` çağrısı yapar. Proje olayları hesap üyeliği ve ilgili test veya derleme verilerine okuma erişimi gerektirir; runner işi olayları hesap üyeliği ve runner okuma erişimi gerektirir; Pulse semptom olayları kuruluş üyeliği ve hesap için Pulse erişimi gerektirir ve bir hesap jetonu o hesaba ait olmalıdır. Talep edilen [`auth.md`](https://workos.com/auth-md) erişim jetonları, talep edilen hesap jetonları ve tarayıcı yetkilendirme izinleri abonelikler oluşturabilir; ilişkili kimlik bilgisi artık etkin olmadığında teslimat durur. Her kullanıcı en fazla 25 aktif abonelik tutabilir. Tuist, aboneliği kaydetmeden önce geri çağırmaya bir doğrulama zorluğu gönderir. Geri çağırma, aynı `challenge` değerini içeren bir nesne döndürmelidir. Abonelik varsayılan olarak yedi gün sürer, tekrar abone olunarak yenilenebilir ve kullanıcının erişimi veya kimlik bilgisi kaldırıldığında teslimat durur. İsteğe bağlı `ttlMs`, bir saat ile 30 gün arasında sınırlıdır. Tuist, zaman aşımına uğrayan bir geri çağırmayı yeniden dener ve beş dakikayı kapsayan en az üç ardışık zaman aşımından sonra aboneliği iptal eder; geri çağırmayı restore ettikten sonra tekrar abone olun.

Bir olay gerçekleştiğinde Tuist, kaynak tanımlayıcısını ve gösterge paneli URL'sini geri çağırmaya gönderir. Derleme ve test çalıştırması hataları ayrıca `is_ci` ve `git_branch` içerir, böylece istemciler yerel hataları yok sayabilir veya dala göre filtreleyebilir. Derleme olayları `build_system` içerir; runner işi olayları hem `workflow_job_id` hem de `workflow_run_id` içerir; Pulse semptom olayları `symptom_id`, `tier` (`board` veya `page`) ve etkilenen varlığı `untrusted` altında, her değeri en fazla 200 karakter olacak şekilde `{"type": "untrusted_json", "value": {"service", "kind", "key"}}` olarak içerir: varlık üretim telemetrisinden gelir, bu nedenle onu veri olarak ele alın, asla talimat olarak kullanmayın. URL'leri semptomun sayfasını açar. İstek, istemcinin kaynağını doğrulayabilmesi için bir abonelik tanımlayıcısı ve [Standard Webhooks](https://www.standardwebhooks.com/) imza başlıkları içerir. Tuist başarısız teslimatları yeniden dener, bu nedenle istemciler yinelenenleri atmak için kararlı `eventId` kullanmalıdır. Yük, test adlarını, günlükleri ve hata mesajlarını dışarıda bırakır; istemci bu ayrıntıları yukarıdaki araçlarla alabilir ve bir ekibi bilgilendirmeye veya hata ayıklamaya başlamaya karar verebilir. İstemciler teslimatı `events/unsubscribe` ile durdurabilir.

### İstemler

| İstem | Açıklama |
|--------|-------------|
| `fix_flaky_test` | Başarısızlık kalıplarını analiz ederek, kök nedeni belirleyerek ve hedefe yönelik bir düzeltme uygulayarak kararsız bir testi düzeltmenize rehberlik eder. |
| `compare_builds` | Performans gerilemelerini, önbellek değişikliklerini ve derleme sorunlarını belirlemek için derlemeleri karşılaştırmanıza rehberlik eder. Xcode, Gradle, Bazel ve Cargo projeleri için yerel araçları kullanır. Cargo karşılaştırmaları kısmi derleyici kapsamını korur ve tahmini derleyici işini geçen süreden tasarruftan ayırır. |
| `compare_test_runs` | Gerilemeleri, yeni hataları ve kararsız testleri belirlemek için iki test çalıştırmasını karşılaştırmanıza rehberlik eder. |
| `compare_bundles` | Yapay ağaçtaki boyut değişikliklerini belirlemek için iki paketi karşılaştırmanıza rehberlik eder. |
| `compare_test_case` | Bir test senaryosunun davranışını iki dal veya zaman dilimi arasında karşılaştırmanıza rehberlik eder. |
| `compare_generations` | Performans gerilemelerini ve modül önbelleği değişikliklerini belirlemek için iki nesil çalıştırmasını karşılaştırmanıza rehberlik eder. |
| `compare_cache_runs` | Önbellek etkinliği değişikliklerini ve hedef düzeyindeki gerilemeleri belirlemek için iki önbellek çalıştırmasını karşılaştırmanıza rehberlik eder. |
| `integrate_gradle_project` | Tuist'i mevcut bir Gradle projesine entegre etmenize rehberlik eder. Ayrı araç ve Gradle kimlik doğrulaması, hesap keşfi, proje oluşturma, uzak önbellek politikası, derleme içgörülerini ve geri okuma doğrulamasını içerir. |
| `integrate_bazel_project` | Bir Bazel projesi oluşturmanıza veya seçmenize, komut satırını kimlik doğrulamanıza, uzak önbelleği ve derleme içgörülerini yapılandırmanıza ve entegrasyonu Tuist derleme verileri aracılığıyla doğrulamanıza rehberlik eder. |
| `integrate_xcode_project` | Tuist'i mevcut bir Xcode projesine entegre etmenize rehberlik eder. Xcode önbelleği, derleme içgörülerini, test içgörülerini ve test parçalamayı destekler. |
| `ask_tuist` | Bağlam için genel materyalleri ve mevcut davranışın doğruluğu olarak odaklanmış uygulama ve test kanıtlarını kullanarak bir Tuist sorusunu yanıtlar. Bir `question` gerektirir ve revizyon sabitli kanıtlara atıfta bulunur. |

Proje verisi istemleri, araştırmayı belirli bir projeye odaklamak için `account_handle` ve `project_handle` kabul eder. Karşılaştırma istemleri ayrıca karşılaştırılacak iki öğeyi (ID, kontrol paneli URL'si veya dal adı ile) belirtmek için `base` ve `head` bağımsız değişkenlerini kabul eder. `ask_tuist`, proje parametreleri yerine bir `question` kabul eder. `integrate_gradle_project` ayrıca uygulanacak Gradle entegrasyonlarının virgülle ayrılmış bir listesi olan `features` kabul eder: `remote_cache`, `build_insights`, `test_insights`, `flaky_tests` ve `test_sharding`. `integrate_bazel_project`, kendi kendine barındırılan veya yerel kurulumlar için isteğe bağlı bir `server_url` kabul eder. `integrate_xcode_project`, `xcode_cache`, `build_insights`, `test_insights` ve `test_sharding` içeren `features` kabul eder.

#### Gradle entegrasyonu istemi özellikleri

`integrate_gradle_project` istemi ve `get_gradle_integration_guide` aracı, tam kurulum iş akışını belgeler. Araç ayrıca sunucunun başlatma talimatları tarafından referans alınır; bu da istemleri numaralandırmayan ajanlar tarafından keşfedilmesini sağlar.

| Özellik | Ajanın yapılandırdığı şey |
|---------|---------------------------|
| `remote_cache` | Gradle'ın derleme önbelleğini etkinleştirir, Tuist uzak önbellek yükleme politikasını yapılandırır ve yalnızca yerel salt okunur kullanımla sürekli entegrasyon çalıştırıcılarından yüklemeleri önerir. |
| `build_insights` | Tuist Gradle eklentisini uygular ve gerektiğinde derleme analitiği yükleme davranışını yapılandırır. |
| `test_insights` | Gradle `Test` görev sonuçlarının otomatik olarak yüklenmesi için Tuist Gradle eklentisini uygular. |
| `flaky_tests` | Kararsız test tespiti, isteğe bağlı Gradle Test Retry eklentisi kullanımı ve test karantina yapılandırması için kurulumu yönlendirir. |
| `test_sharding` | `tuistPrepareTestShards` için sürekli entegrasyon iş akışını, parça matrisi oluşturmayı ve `TUIST_SHARD_INDEX` tabanlı test yürütmeyi ekler. |

`features` atlandığında, istem ajandan kullanıcının hangi entegrasyonları istediğini netleştirmesini veya Gradle projesini düzenlemeden önce istekten en küçük yararlı kümeyi çıkarmasını ister.

#### Xcode entegrasyonu istemi özellikleri

`integrate_xcode_project` istemi, Tuist'in desteklediği her Xcode entegrasyonunu belgeler:

| Özellik | Ajanın yapılandırdığı şey |
|---------|---------------------------|
| `xcode_cache` | `tuist setup cache`, oluşturulan proje önbellek ayarlarını, manuel Xcode önbellek derleme ayarlarını ve yalnızca sürekli entegrasyon çalıştırıcılarıyla sınırlı bir yükleme politikasını yapılandırır. |
| `build_insights` | `tuist inspect build`, `tuist xcodebuild`, `-resultBundlePath` ve `tuist setup insights` aracılığıyla isteğe bağlı makine metriklerini yapılandırır. |
| `test_insights` | `tuist inspect test`, şema test sonras eylemlerini ve sürekli entegrasyon test çalıştırmaları için sonuç paketi oluşturmayı yapılandırır. |
| `test_sharding` | `TUIST_SHARD_INDEX` ile Xcode veya oluşturulan proje parça planlamasını ve parça yürütme iş akışını ekler. |

`features` atlandığında, istem ajandan kullanıcının hangi entegrasyonları istediğini netleştirmesini veya Xcode projesini düzenlemeden önce istekten en küçük yararlı kümeyi çıkarmasını ister.
