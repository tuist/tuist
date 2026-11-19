---
{
  "title": "Model Context Protocol (MCP)",
  "titleTemplate": ":title · Ajan tabanlı kodlama · Özellikler · Kılavuzlar · Tuist",
  "description": "AI ajanlarına Tuist'in MCP uç noktası üzerinden test içgörülerine ve daha fazlasına erişim sağlayın."
}
---
# Model Context Protocol

[Model Context Protocol (MCP)](https://modelcontextprotocol.io/docs/getting-started/intro), yapay zeka ajanlarının harici hizmetler ve veri kaynaklarıyla etkileşime girmesini sağlayan açık bir standarttır. [Claude](https://claude.ai/), [Claude Code](https://docs.anthropic.com/en/docs/claude-code), [Codex](https://developers.openai.com/codex/) gibi uygulamaların ve [Zed](https://zed.dev), [Cursor](https://www.cursor.com) veya [Visual Studio Code](https://code.visualstudio.com) gibi editörlerin Tuist ile birlikte çalışabilir olmasını sağlar.

Tuist, sunucu tarafında bir Model Context Protocol uç noktasını `https://tuist.dev/mcp` adresinde barındırır. İstemcinizi bu uç noktaya bağlayarak ajanlar, test içgörileri, kararsız test analizi ve daha fazlası dahil olmak üzere Tuist proje verilerinize erişebilir. Çoğu araç, kimliği doğrulanmış kullanıcının panoda zaten görebildiği Tuist verilerini okur. Her araç, salt okunur olup olmadığını, zor geri alınabilen bir değişikliğe neden olup olmadığını (`destructiveHint`) ve Tuist dışına erişip erişmediğini (`openWorldHint`) belirten açıklamalar sunar. Durumu değiştiren araçlar, her biri hesabın veya projedeki kullanıcı izinleriyle sınırlıdır:

- **Organizasyonlar ve üyeler**: `create_organization`, `add_organization_member` (mevcut bir kullanıcı ekler veya bir übenin rolünü değiştirir), `invite_organization_member` (herhangi bir adrese davetiye e-postası gönderir) ve `cancel_organization_invitation`.
- **Projeler**: `create_project`, `start_project_logo_upload` ve `complete_project_logo_upload` (logoyu değiştirir), `connect_project_repository` ve `disconnect_project_repository` (GitHub depo bağlantıları).
- **Testler**: `update_test_case` (bir test senaryosunu sessize alır, atlar, yeniden etkinleştirir veya kararsız olarak işaretler; değişiklik hesabın webhook uç noktalarına ulaşabilir).
- **Bildirim kuralları**: `create_notification_rule`, `update_notification_rule` ve `delete_notification_rule`.
- **Sürekli entegrasyon çalıştırıcıları**: `create_runner_profile`, `update_runner_profile` (hangi işlerin önbellek birimlerini kaydettiğini daraltmak bekleyen kayıtları siler), `delete_runner_profile` ve `delete_runner_volume` (birimin kaydedilen içeriğini siler).
- **Sandbox’lar**: `create_sandbox`, `pause_sandbox`, `resume_sandbox`, `archive_sandbox` ve `delete_sandbox` (disklerini siler).
- **Geri bildirim**: `report_feedback` (bir araç veya istem hakkında Tuist ekibine rapor gönderir; yalnızca tuist.dev üzerinde).
- **Organizasyon Yapay Zekası**: `save_organization_ai_model`, `remove_organization_ai_model`, `set_organization_ai_default_model`, `save_organization_ai_task_route`, `remove_organization_ai_task_route` ve `remove_organization_ai_provider` (sağlayıcının anahtarını ve modellerini siler ve Anthropic'te bağlı bir Claude organizasyonunun bağlantısını kaldırır).
- **Ajan entegrasyonları**: `connect_amp_workspace` (çalışma alanının orb'larına hesaba CI erişimi verir), `disconnect_amp_workspace` ve `connect_claude_environment` (Claude Managed Agents ortamının Tuist sandbox’larında oturumlar çalıştırmasına olanak tanır).

`add_organization_member`, `cancel_organization_invitation`, `complete_project_logo_upload`, `disconnect_project_repository`, `update_test_case`, `update_notification_rule`, `delete_notification_rule`, `update_runner_profile`, `delete_runner_profile`, `delete_runner_volume`, `delete_sandbox`, `disconnect_amp_workspace`, `remove_organization_ai_provider`, `remove_organization_ai_model` ve `remove_organization_ai_task_route` mevcut durumu değiştirdiği veya kaldırdığı için `destructiveHint: true` bildirir. `invite_organization_member`, `update_test_case`, `connect_claude_environment`, `remove_organization_ai_provider` ve `report_feedback` e-posta gönderdiği, harici webhook uç noktalarını bildirdiği, Anthropic'i çağırdığı veya Tuist ekibine rapor gönderdiği için `openWorldHint: true` bildirir.

Kişisel Claude ve ChatGPT abonelikleri yalnızca panonun Yapay Zeka ayarlarında bağlanır, bu nedenle abonelik jetonları ve oturum açma işlemleri asla bir Model Context Protocol istemcisinden geçmez. Hesap kurulum araçları kullanıcı kimlik doğrulaması gerektirir. Proje jetonları veya normal hesap jetonları için kullanılamazlar. Bir kullanıcı tarayıcıda bir istemciyi yetkilendirdiğinde veya bir `auth.md` kaydını talep ettiğinde, Tuist bu kimlik bilgilerini yalnızca Model Context Protocol uç noktasında kullanıcıyla ilişkilendirir, böylece kurulum araçları istenen iş akışını tamamlayabilir.

Tuist, [2026-07-28 protokolünü](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http) uygular. İstekler durumsuzdur: istemciler her istekle birlikte protokol meta verilerini gönderir ve başlatma olmadan araçları doğrudan çağırabilir. `server/discover` sunucunun kimliğini, yeteneklerini, desteklenen sürümleri ve talimatları döndürür. Oturum tanımlayıcıları veya bağımsız olay akışları yoktur. 2025-06-18 veya 2025-03-26 başlatma akışını kullanan istemciler desteklenmeye devam eder; bunlar da sunucu oturumları olmadan çalışır.

## Model Context Protocol ile beceriler

Model Context Protocol araçları ve <.localized_link href="/guides/features/agentic-coding/skills">beceriler</.localized_link> yaptıkları işlerde örtüşebilir. İkisi arasındaki mevcut örtüşme göz önüne alındığında, her iş akışı için bir yaklaşım seçin ve aynı akışta ikisini karıştırmak yerine tutarlı bir şekilde kullanın.

Eklenti yüklemeyi destekleyen istemciler için, her ikisini birlikte yüklemek amacıyla <.localized_link href="/guides/features/agentic-coding/plugins">Tuist eklentilerini</.localized_link> kullanın.

## Yapılandırma

İstemcinize uzak bir Model Context Protocol sunucusu olarak `https://tuist.dev/mcp` ekleyin. Sunucunun başlatma talimatları ve genel sunucu kartı, aracıların harici kimlik doğrulama belgelerini getirmesini veya takip etmesini istemeden, dinamik istemci kaydı ile OAuth 2.0 ve standart tarayıcı yetkilendirme akışını satır içinde açıklar. Bu sunucu çapındaki talimatlar iş akışı rehberliğini genel tutar: araç kimlik doğrulaması yerel komut satırı araçlarını veya derleme sistemi entegrasyonlarını kimlik doğrulamaz ve ajanlar istenen değişiklikleri ilgili Tuist araçları aracılığıyla doğrulamalıdır. Derleme sistemine özel kurulum ve kimlik doğrulama kontrolleri entegrasyon kılavuzlarında ve istemlerde belgelenmiştir. Tuist hem [Open Authorization](https://oauth.net/2/) keşif meta verilerini hem de mevcut [auth.md protokolünü](https://workos.com/auth-md) ayrıca `https://tuist.dev/auth.md` adresinde duyurmaya devam eder.

Organizasyonlarınızdan biri tek oturum açmayı (SSO) zorunlu kılıyorsa, tarayıcıda bir istemciyi yetkilendirmek o organizasyon üzerinden oturum açmış bir oturum gerektirir ve Tuist gerektiğinde sizi önce sağlayıcıya yönlendirir. Bkz. <.localized_link href="/guides/integrations/authentication/sso#choose-an-enrollment-policy">tek oturum açma</.localized_link>.

Uç nokta, daha eski oturum tabanlı yaşam döngüsünün yanı sıra, `server/discover` dahil olmak üzere durumsuz `2026-07-28` Model Context Protocol istek yaşam döngüsünü kabul eder. Mevcut istemciler mevcut bağlantı yöntemlerini kullanmaya devam edebilir.

Model Context Protocol olaylarını destekleyen istemciler proje olaylarına abone olabilir. Mevcut olay ve teslimat gereksinimleri için bkz. [Olaylar](#events).

Zaten uzak tarayıcı kimlik doğrulamasını destekleyen istemciler tarayıcıda kimlik doğrulamaya devam edebilir. `auth.md` destekleyen istemciler ve ajanlar anonim olarak kayıt olabilir, güvenilir bir sağlayıcı kimlik iddiası sunabilir veya hizmet tarafından kimliği doğrulanmış bir e-posta talebi başlatabilir. Kayıt, Tuist tarafından imzalanmış bir kimlik iddiası döndürür; ajan bunu standart jeton uç noktasında bir saatlik erişim jetonu ile takas eder. Tuist genel imzalama anahtarını yayımlar ve standart jeton iptalini ve sağlayıcı güvenlik olayı teslimatını destekler.

Kimliği doğrulanmamış bir ajan, Model Context Protocol uç noktası tarafından döndürülen `WWW-Authenticate` başlığını okumalı, korunan kaynak meta verilerini almalı, yetkilendirme sunucusu meta verilerini almalı ve `agent_auth.skill` URL’sini izlemelidir. Tuist ayrıca yetkisiz yanıt gövdesinde aynı yerel `auth_md` URL’sini döndürür; böylece dil modeli tabanlı istemciler, yerel bir istemci entegrasyonuna güvenmeden akışı keşfedebilir. Dağıtım düzeyindeki belge, uç nokta adları, istek gövdeleri, talep yoklaması ve iddia takası için tek doğruluk kaynağıdır.

Bir ajan e-posta talebini başlatmadan önce, kullanıcının Tuist hesabına ait e-posta adresini onaylamasını istemelidir. Bu adresi bir sağlayıcı profilinden, Git yapılandırmasından, ortam değişkeninden veya oturum meta verilerinden çıkarmamalıdır.

Uç nokta `mcp` kapsam grubunu kullanır. Anonim, talep öncesi kimlik bilgileri yetenekleri keşfedebilir ve genel entegrasyon rehberlerini okuyabilir ancak oturum açmış bir kullanıcı olarak değerlendirilmez. Tarayıcı yetkilendirmesi veya talepten sonra kimlik bilgisi kullanıcı kapsamlı hale gelir ve her araç, gösterge panelindekiyle aynı yetkilendirme kontrollerini uygular. Ayrıntılar için bkz. <.localized_link href="/guides/server/authentication#scope-groups">kapsam grupları belgeleri</.localized_link>.

Araçlar, kimliği doğrulanmış kullanıcının zaten okuma erişimine sahip olduğu projelere çözülür. Xcode ve Gradle derleme araçları bir derleme UUID’sini veya gösterge paneli URL’sini kabul eder. UUID tam olarak bir projeyi tanımlamalıdır; birden fazla projede görünüyorsa araç başka bir projenin raporunu seçmek yerine bulunamadı yanıtını döndürür. Proje kapsamlı gösterge paneli ve API okumaları kullanılabilir durumda kalır. Bildirilen aktör tanımlayıcıları doğrulanmamış etiketlerdir; kimlik bilgisi veya ek erişim hakları değildir.

Derleme listesi ve ayrıntı araçları isteğe bağlı `tuist_version` meta verilerini sunar: Xcode ve Cargo için raporlayan Tuist CLI, Gradle için Tuist Gradle eklentisi ve Mix için `tuist_ex` kitaplığı. Xcode ayrıca bağlı proje oluşturma olayından `tuist_generation_version` değerini sunar; bu değer yükleyen CLI’dan farklı olabilir. Eksik gözlemler null olarak bildirilir; sunucudan veya başka bir rapordan çıkarılmaz. Bazel mevcut `bazel_version` değerini kullanır; Once çalıştırma ayrıntıları `once_version` değerini sunar. Bu alanlar bildirilen sürümleri açıklar; doğrulanmış kimlik veya iletişim sözleşmesi sürümlerini değil. REST derleme uç noktaları aynı meta verileri sunar. Mevcut entegrasyon ve kararsız test becerileri sürüm alanlarına bağlı değildir ve iş akışı değişikliği gerektirmez.

Bir müşterinin hesabını inceleyen Tuist operatörleri bunu Tuist’in dahili operasyon araçları üzerinden yapar; bu araçlar her çağrıyı kaydeder. Bu uç noktaya doğrudan bağlantı, kullanıcının kendi üyelikleri dışında hiçbir erişim sağlamaz.

### Pulse

Pulse, hesabın operasyonel metrikleri, günlükleri, izleri ve hataları için salt okunur araçlar sunar; tümüne `account_handle` ile hitap edilir. İlk üçü Pulse sayfalarını ve bunların REST API’sini yansıtır; diğer beşi bir ajanın telemetriyi doğrudan keşfetmesine olanak tanır ve REST eşdeğeri yoktur:

| Araç | Amaç | `/api/accounts/:account_handle/pulse` altındaki REST eşdeğeri |
| --- | --- | --- |
| `query_pulse` | Pulse sayfası tabloları | `GET /:signal` |
| `get_pulse_analytics` | Pulse sayfası widget’ları | `GET /:signal/analytics` |
| `get_pulse_error_issue` | Bir hata sorunu ve olayları | `GET /errors/issues/:fingerprint` |
| `query_pulse_metrics` | Anlık veya aralıklı PromQL | Yok |
| `list_pulse_labels` | Etiket adları veya bir etiketin değerleri | Yok |
| `search_pulse_logs` | Filtrelenmiş günlük girdileri | Yok |
| `search_pulse_traces` | Filtrelenmiş yayılma alanları | Yok |
| `get_pulse_trace` | Bir izdeki tüm yayılma alanları | Yok |

Pulse, bir hesap veya proje herkese açık olsa bile sunucu tarafından yapılandırılmış organizasyonun mevcut üyeleriyle sınırlıdır. Kullanıcı kimlik doğrulaması veya kullanıcıyla ilişkili `mcp` kimlik bilgisi ve hesap okuma yetkisi gerektirir. Proje jetonları, sıradan hesap jetonları, anonim kayıtlar ve organizasyon üyeliği olmayan operatör erişimi Pulse erişimi sağlamaz. Kimlik bilgileri başka bir arka uç veya telemetri kiracısı seçemez ve yalnızca sunucu tarafından yapılandırılan hesap Pulse telemetrisine sahiptir; bu nedenle hiçbir araç başka bir hesabın verilerini okuyamaz. Tarayıcı ajanları bu araçları yalnızca Pulse sayfalarında, o sayfanın hesap kapsamı içinde alır.

REST bir kullanıcı kimlik bilgisi gerektirir. OAuth ve `auth.md` kullanıcı ilişkileri yalnızca `/mcp` uç noktasında mevcuttur; geçerli bir kullanıcıya sahip olmayan bir hesap kimlik bilgisi, ilişkili hesabın üyeliği veya görünürlüğünden bağımsız olarak reddedilir.

`query_pulse`, `signal` (`metrics`, `logs`, `traces` veya `errors`), isteğe bağlı `query` ve `range` (`15m`, `1h`, `6h` veya `24h`, varsayılan `1h`) parametrelerini alır. Metrikler PromQL ifadelerini kabul eder. Günlükler, izler ve hatalar günlük gövdelerine, yayılma alanı adlarına ve hata sorun başlıklarına karşı eşlenen büyük/küçük harf duyarsız düz metni kabul eder; varsayılan olan `*` her şeyi seçer. İz satırları bireysel yayılma alanlarıdır. Hata satırları sorunlardır: hizmete ve parmak izine göre gruplandırılmış olaylar; olay sayısı, etkilenen hesaplar, penceredeki ilk ve son oluşum ile en son olaylarının başlığı, sorumlusu, düzeyi ve platformu. Tablolar `search`, `page` (varsayılan `1`), `page_size` (`1`–`100`, varsayılan `20`), `sort_by` ve `sort_order` (`asc` veya `desc`) parametrelerini kabul eder. Sıralama sütunları sinyale bağlıdır ve araç şemasında listelenir. Filtreler arasında günlükler ve hatalar için `service` ve `level` bulunur. Filtre işleçleri karşılık gelen `_op` bağımsız değişkenini (`eq`, `contains` veya `not_contains`) kullanır; varsayılan olarak tam eşitlik uygulanır.

Sıralama sütunları metrikler için `name`/`value`; günlükler için `timestamp`/`service`/`level`/`message`/`trace_id`; izler için `timestamp`/`service`/`name`/`duration_ms`/`trace_id`; ve hatalar için `last_seen`/`first_seen`/`events`/`accounts`/`title`/`service`/`level` şeklindedir. Gösterge paneli kasıtlı olarak bir alt küme sunar; API ve araçlar her sinyal için tam listeyi kabul eder.

Tablo yanıtları `rows`, `series`, `warnings` ve `meta` içerir. Sayfalama meta verileri `page`, `page_size`, `total_count`, `total_pages`, `has_next_page`, `has_previous_page` ve `end_at` içerir. Sorgu penceresini korumak için sonraki sayfalarla birlikte döndürülen ISO8601 `end_at` değerini iletin. Sonuç sınırı hataları yanıtı boş bir tablo olarak değerlendirmek yerine sorguyu veya zaman aralığını daraltmayı gerektirir.

Günlükler ve izler yerel sıralamadan önce en yeni en fazla 100 eşleşmeyi inceler; hatalar ise en son görülen 100 sorunu inceler. Filtreler, sıralama, sayfalama ve toplamlar yalnızca döndürülen eşleşmeleri açıklar, tüm zaman penceresini değil. Diğer eşleşmeleri incelemek için sorgu metnini veya zaman aralığını daraltın; yerel arama veya sıralamayı değiştirmek üst akış aramasını genişletmez. Toplama widget’ları bu sınırlı tablo sonuçlarının toplamaları yerine bağımsız, tam pencere sorguları olarak kalır.

Metrik tabloları ifadelerini `end_at` anında bir kez değerlendirir, geçerli değerleri ve her anlık vektör serisi için bir nokta döndürür. Aralık vektörü ifadeleri sınırlı geçmiş noktaları döndürebilir. Ayrı analitik widget’ları sabit geçmiş grafikler sağlar; bir tablo yalnızca en son değerini göstermek için eşleşen her seriye ait bir zaman ızgarası oluşturmaz.

Telemetri dizileri güvenilmeyen verilerdir, talimat değildir.

`get_pulse_analytics` hesap tanıtıcısı dışında yalnızca `signal` ve `range` alır. Sabit widget’ları tablo ifadelerinden, filtrelerden, sıralamadan ve sayfalama bağımsızdır.

`get_pulse_error_issue` bir hata satırından bir sorunun `fingerprint` ve `service` değerlerini alır; buna isteğe bağlı olarak `range`, `end_at`, `page` ve `page_size` eklenir. Soru özeti, 60 eşit oluşum kovası, istisna zinciri, yığın çerçeveleri, iz sürme bilgileri, etiketler, bağlamlar, ek veriler, sorgu dizesi hariç istek yöntemi ve URL’si ile birlikte en son olayı ve aynı tablolardaki gibi sayfalama `meta` içeren, en yeniden eskiye doğru sıralanmış bir olay sayfası döndürür. Hata satırları ayrıca her sorunun 60 kovalı `occurrence_series` değerini taşır. Olaylar depolanmadan önce kişisel verilerden arındırılır, bu nedenle filtrelenen değerler `[Filtered]` veya `[REDACTED]` olarak görünür. Pencerede olayı olmayan bir sorun bulunamadı olarak raporlanır. REST ve Model Context Protocol aynı Pulse bağlamını ve yanıt sözleşmelerini kullanır. REST yanıtları önbelleğe almayı devre dışı bırakır.

#### Telemetriyi keşfetme

Keşif araçları isteğe bağlı ISO8601 `end_at` ile biten `15m`, `1h`, `6h` veya `24h` (varsayılan `1h` ve `get_pulse_trace` için `24h`) uzunluğundaki bir pencereyi okur; varsayılan olarak şu andır. Her yanıt `start_at` ve `end_at` döndürür; pencereyi korumak için aynı `end_at` değerini tekrar iletin. Bu araçların hiçbiri SQL kabul etmez.

- `query_pulse_metrics`, bir PromQL ifadesi olan `query` değerini `end_at` (`type: instant`, varsayılan) anında veya pencere boyunca her `step` saniyede bir (`type: range`) değerlendirir. Adım varsayılan olarak pencerenin 360’a bölünmesine eşittir ve bundan küçük olamaz, bu nedenle bir seride en fazla 361 nokta olur. Sonuçlarda en fazla 5.000 seri bulunur. Noktalar `[unix_seconds, value]` şeklindedir ve `NaN` ile sonsuz değerler dizge olarak temsil edilir. Anlık sorgular `range` ve `step` parametrelerini reddeder.
- `list_pulse_labels` bir `signal` alır. `label` olmadan etiket adlarını listeler; `label` ile o etiketin değerlerini listeler. Metrikler için `__name__` metrik adlarını listeler ve diğer herhangi bir etiketin değerleri `match`, örneğin `up` gibi bir seri seçici gerektirir. Günlük ve iz etiket değerleri `filters` kabul eder; iz etiket adları iz şemasından gelir ve bunu yapmaz. Günlük ve iz değerleri, penceredeki giriş sayılarını içerir ve en sık görülenler önce gelir, bu nedenle hizmete göre hatalar gibi alt kırılımlar olarak da işlev görürler. `search` yalnızca değişmez metin içeren adları veya değerleri tutar ve `limit` `1`–`1000` (varsayılan `100`) kabul eder. Günlük etiket adı keşfi, her türden en fazla 1.000 farklı öznitelik kümesini inceler ve yalnızca filtrelerin kabul ettiği anahtarları listeler.
- `search_pulse_logs` gövdesi `text` içeren ve her filtreyi eşleştiren, `newest` veya `oldest` sırasına göre en fazla `limit` girişi (`1`–`100`, varsayılan `50`) döndürür. Her giriş `severity_text`, `body`, `trace_id`, `span_id`, `scope_name` ve birleştirilmiş kaynak ile günlük `attributes` özniteliklerini içerir. `span_id` ve `scope_name`, yalnızca OTLP günlük göndericilerinin ayarladığı Kubernetes’ten toplanan günlükler için `null` değerindedir.
- `search_pulse_traces` her filtreyi, isteğe bağlı `min_duration_ms` ve `max_duration_ms` ile `root_only` koşullarını karşılayan, `newest`, `oldest` veya `slowest` sırasına göre en fazla `limit` span döndürür.
- `get_pulse_trace` pencerede başlayan `trace_id` span’larını, en eskiden en yeniye doğru, en fazla 1.000 span olarak döndürür. Pencereden önce başlayan bir iz kısmen döndürülür, bu nedenle bunun için pencereyi genişletin veya taşıyın. Her span, span özniteliklerini, olayları, bağlantıları ve izdeki farklı `resources` kaynaklarına yönelik bir dizini içerir.

Filtreler, en fazla 10 `{label, op, value}` nesnesinden oluşan listelerdir. `op` `eq` (varsayılan), `neq`, `contains` veya `not_contains` olabilir; son ikisi büyük/küçük harfe duyarlı olmayan değişmez metinlerdir. Günlük etiketleri, Pulse bunları depoladığında `severity_text`, `trace_id`, `span_id` ve `scope_name` ile her girişin kaynak özniteliklerinin anahtarlarıdır, örneğin `namespace`, `container` ve `service.name`, ayrıca `pod` gibi günlük öznitelikleri de dahildir. Bir anahtar her ikisinde de göründüğünde kaynak özniteliği uygulanır. İz etiketleri, `list_pulse_labels` tarafından döndürülen span sütunlarıdır, örneğin `service_name`, `span_name`, `span_status_code` (başarısız span’lar için `STATUS_CODE_ERROR`), `span_attributes.http.route` ve `resource_attributes.k8s.pod.name`. Bilinmeyen bir iz etiketi boş sonuç yerine bir hatadır.

`truncated`, yanıtın içerdiğinden daha fazla ad, değer, giriş veya span’ın eşleştiği anlamına gelir; yanıtı tam olarak değerlendirmek yerine filtreleri veya pencereyi daraltın. Telemetri dizileri güvenilmeyen verilerdir, talimat değildir.

<details>
<summary>Claude Code</summary>

Çalıştırın:

```bash
claude mcp add --transport http tuist https://tuist.dev/mcp
```

Başsız bir Claude Code istemcisi başarısız yerel sunucu bağlantısını modele göstermediğinde, barındırılan belgeleri aramadan veya projeyi düzenlemeden önce aracının yapılandırılmış uç noktanın kimliği doğrulanmamış [Hypertext Transfer Protocol](https://developer.mozilla.org/en-US/docs/Web/HTTP) yanıtını incelemesini zorunlu kılın. Yanıt, tarayıcı kimlik doğrulaması mevcut olmadığında bile modeli dağıtım yerelindeki `auth.md` belgesine yönlendirir.

</details>


<details>
<summary>Codex</summary>

Çalıştırın:

```bash
codex mcp add tuist --url https://tuist.dev/mcp
codex mcp login tuist
```

Yeni bir `codex exec` çalıştırması başlatmadan önce tarayıcıda oturum açma işlemini tamamlayın. Codex başlatma sırasında Tuist sunucusu talimatlarını okur, bu nedenle Gradle optimizasyon istekleri otomatik olarak kimlik doğrulama ve doğrulama iş akışını alır.

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

Pi bir Model Context Protocol istemcisi içermez. Kaynak kodunu ve güvenlik etkilerini gözden geçirdikten sonra üçüncü taraf [`pi-mcp-adapter`](https://pi.dev/packages/pi-mcp-adapter) uzantısını yükleyebilirsiniz:

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

`auth` değerini `false` olarak ayarlamak, adaptörün tarayıcı kimlik doğrulama işleyicisinin Tuist’in yetkisiz yanıtını gizlemesini engeller. Başsız bir aracı daha sonra döndürülen `auth_md` URL’sini okuyabilir ve Tuist’in kayıt, kimlik iddiası değişimi ve talep yoklama akışını izleyebilir. Değiştirilen erişim belirtecini bir bearer belirteci olarak yapılandırın veya aracının doğrudan kimliği doğrulanmış Model Context Protocol çağrıları yapmasına izin verin.

Tarayıcı kimlik doğrulamasını tercih ediyorsanız `auth` değerini `"oauth"` olarak ayarlayın. Bu akış için, kimlik doğrulama tamamlanırken Pi’nin [remote procedure call mode](https://pi.dev/docs/latest/rpc) ile tek bir işlemi canlı tutun:

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

**Komut Paleti → MCP: Sunucu Ekle** seçeneğini kullanın, ardından şu ayarlarla bir [Hypertext Transfer Protocol](https://developer.mozilla.org/en-US/docs/Web/HTTP) sunucusu yapılandırın:

- **Ad:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>


<details>
<summary>Zed</summary>

**Temsilci paneli → Ayarlar → Özel Sunucu Ekle** seçeneğini açın, ardından şunları ayarlayın:

- **Ad:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>

Aracınız `auth.md` destekliyorsa, tarayıcı açmadan anonim olarak başlayabilir. Güvenilen bir sağlayıcı kimliği zaten bağlıysa, tarayıcı olmadan da işlem tamamlanabilir. Hizmetle kimliği doğrulanmış e-posta, anonim talep veya ilk sağlayıcı bağlantısı için aracı size bir Tuist doğrulama bağlantısı ve altı haneli bir kod gösterir. Bağlantıyı açın, oturum açın ve Tuist sayfasında aracının kodunu girin. Kodu asla aracıya geri göndermeyin. Tuist’in yetkilendirme sunucusu meta verileri doğrudan dağıtımın kendi `/auth.md` dosyasına işaret eder; bu dosya tam istek ve yoklama yapılarını içerir.

## Amp orb’larında ve Claude Code bulut oturumlarında çalışan ajanlar

Bir Tuist hesabına bağlı alan kutularında (sandbox) çalışan kodlama ajanları, tarayıcı veya kaydedilmiş bir Tuist kimlik bilgisi gerekmeden kendi kimlik belirteçleriyle uç noktaya kimlik doğrulaması yapabilir:

- Hesabın **Ayarlar → Entegrasyonlar → Amp** altında bağladığı bir Amp çalışma alanının veya projesinin **Amp orb’ları**, orb’un kimlik belirtecini gönderir. Amp’de sunucunun `Authorization` başlığını `Bearer ${amp:id-token}` olarak ayarlayın. Amp, sunucu URL’sinin kaynağı için belirteci basar, bu nedenle URL bu Tuist örneğinin kendi adresi olmalıdır ve süresi dolmadan önce yeniler. Başka bir kaynak için basılan belirteçler reddedilir.
- Bağlı bir Claude Code ortamının **Claude Code bulut oturumları**, Tuist’in kendilerine `TUIST_OIDC_TOKEN` olarak ilettiği oturum belirtecini gönderir. Başlığı `Bearer ${TUIST_OIDC_TOKEN}` olarak ayarlayın.

Tuist’in Linux alan kutuları sunucuyu sizin için eklemez: aynı kimlikle oturum açan Tuist CLI’ını ve aracıya sonuçlarını projenin geçmişine göre ne zaman kontrol etmesi gerektiğini söyleyen bir beceriyi birlikte sunar. Ajanlara MCP araçlarını da sağlamak için sunucuyu yukarıdaki başlıkla birlikte Amp veya Claude Code ayarlarınıza ya da projenin `.mcp.json` dosyasına ekleyin.

Bu belirteçler, bağlı hesabın her projesine salt okunur erişim sağlar: `mcp` grubunun okuma kapsamlarını taşırlar ve testleri sessize alma veya atlama gibi veri oluşturan, değiştiren veya silen hiçbir kapsamı taşımazlar. Çalışma alanının veya ortamın bağlantısını kesmek, sonraki istekte erişimi durdurur ve erişim asla belirtecin kendisinden daha uzun sürmez. Birden fazla Tuist hesabına bağlı bir Amp çalışma alanı reddedilir çünkü belirteci tek bir hesabı adlandırmaz. Bir bağlantı eksik olduğunda, yetkisiz yanıtın `error_description` alanı bunu belirtir.

Bu salt okunur erişim yalnızca Model Context Protocol uç noktası için geçerlidir. Aynı alan kutusundaki komut satırı aracı ve derleme sistemi entegrasyonları, bağlantının CI erişimi için belirteci yine de değiştirir.

## WebMCP

[WebMCP](https://webmachinelearning.github.io/webmcp) destekleyen tarayıcılarda, Tuist sayfaları araçları `document.modelContext` ile kaydeder, böylece tarayıcıya yerleşik ajanlar ekstra yapılandırma olmadan bunları çağırabilir. Çağrılar Tuist sunucusunda çalışır.

- **Web sitesi ve belge sayfaları**, belge ve kaynak araçlarını (`search_tuist`, `search_tuist_code`, `list_tuist_files` ve `read_tuist_file`) kaydeder. Oturum açmanıza gerek yoktur.
- Oturum açtığınızda, **bir hesabın pano sayfaları** o hesap için Tuist’in salt okunur araçlarını kaydeder. Her sayfa yalnızca gösterdiği içeriğe, projenin derleme sistemine uygun araçları kaydeder: bir Gradle projesinin derlemeler sayfası Gradle derleme araçlarını, test sayfaları test ve kapsam araçlarını, çalıştırıcı sayfaları çalıştırıcı araçlarını ve alan kutusu sayfaları alan kutusu araçlarını alır. Her sayfa ayrıca belge araçlarını, `list_projects` ve `get_project` araçlarını da alır. Araçlar oturum açmış kullanıcı olarak çalışır, bu nedenle yalnızca panoda okuyabileceğiniz verilere ve yalnızca baktığınız hesaba erişebilirler. Başka bir sayfaya veya hesaba geçtiğinizde, araçlar o sayfanın araçlarıyla değiştirilir.

Veri oluşturan, değiştiren veya silen araçlar WebMCP üzerinden kullanılamaz çünkü bir tarayıcı ajanı araçları siz eklemeden alır ve derlemeler ile testlerin ürettiği içeriği okur. Bu araçları kullanmak için bir MCP istemcisini `/mcp` uç noktasına bağlayın.

Kuruluş tek oturum açmayı (SSO) zorunlu kılıyorsa, araçlarını kullanmak için sağlayıcısıyla panoda oturum açın.

## Derleme sistemi entegrasyonları iki kimlik bilgisi kullanır

Model Context Protocol araçları için kullanılan kimlik bilgisi, Gradle eklentisini veya Bazel’in uzak hizmetlerini kimlik doğrulamaz. Bir aracı bir Gradle veya Bazel entegrasyonunu düzenlemeden veya doğrulamadan önce şunu çalıştırmalıdır:

```bash
tuist auth whoami --url https://tuist.dev
```

Bu komut kimlik doğrulaması yapmamışsa, aracı durmalı ve kullanıcıdan şunu çalıştırmasını istemelidir:

```bash
tuist auth login --url https://tuist.dev
```

Yerel veya kendi barındırdığınız bir dağıtım için, her iki komuttaki ve `tuist.toml` içindeki URL’yi değiştirin. Ana bilgisayar adının yazımını her yerde aynı tutun. Örneğin, `localhost` ve `127.0.0.1` ayrı saklanan kimlik bilgilerini kullanır.


## Yetenekler

### Araçlar

Aşağıdaki araçlar Tuist Model Context Protocol sunucusu üzerinden kullanılabilir:

Her araç, açık giriş ve çıkış şemalarıyla birlikte insan tarafından okunabilir bir açıklama yayımlar. Başarılı çağrılar, ilan edilen çıkış şemasına uyan yapılandırılmış içerik döndürür ve ayrıca henüz yapılandırılmış içeriği tüketmeyen istemciler için metin olarak serileştirilmiş aynı sonucu verir.

Tek bir kaydın tanımlayıcısını alan araçlar, örneğin `build_run_id`, `test_run_id`, `test_case_id`, `bundle_id`, `run_id`, `generation_id` veya `cache_run_id`, ayrıca o kaydın Tuist pano URL’sini kabul eder. Tanımlayıcıyı çıkarmak yerine URL’yi doğrudan tarayıcıdan yapıştırın.

`get_xcode_build`, `get_test_run`, `get_gradle_build` ve `get_project` `side_quests` içerebilir: projenin kullanmadığı ancak kaydın yardımcı olacağını gösterdiği Tuist yetenekleri. Her birinin bir `id`’si, dayandığı kanıtı belirten bir `tip`’si ve bir `docs` bağlantısı vardır. Ajanlardan önce kullanıcının isteğini tamamlamaları, geçerli yan görevlerden bahsetmeleri ve yalnızca kullanıcı onay verdiğinde birini uygulamaları istenir. Bunlar yalnızca projenin hesabının üyelerine, kullanıcı oturumu, MCP belirteci veya aracı kimliğiyle bağlansalar bile döndürülür:

| Kimlik | Araç | Önerildiğinde |
|----|------|----------------|
| `xcode_compilation_cache` | `get_xcode_build` | Xcode 26 veya üzeriyle işlenen temiz bir derleme, önbelleğe alınabilir herhangi bir derleme görevi çalıştırmadı. |
| `gradle_build_cache` | `get_gradle_build` | Bir derleme, Gradle’in derleme önbelleği bunlardan hiçbiri için bir anahtar hesaplamadan önbelleğe alınabilir görevleri yürüttü; bu, derleme önbelleğinin kapalı olduğu anlamına gelir. |
| `flaky_test_quarantine` | `get_test_run` | Bir çalıştırma kararsız testler içeriyordu ve projede bunları sessize alan veya atlayan etkin bir otomasyon yoktu. Once projeleri için önerilmez. |
| `test_sharding` | `get_test_run` | Tuist’in parçalayabildiği bir derleme sisteminde, parçalanmamış bir CI çalıştırması 10 dakika veya daha fazla sürdü. İpucu, seçici testin ne zaman kaç testi zaten atladığını belirtir. |
| `tuist_runners` | `get_xcode_build`, `get_test_run` | Bir CI çalıştırması GitHub Actions, Bitrise, GitLab CI veya Buildkite makinelerini kullandı ve hesap hiçbir zaman Tuist Runners üzerinde bir iş çalıştırmadı. Yalnızca tuist.dev’de. |
| `pull_request_comments` | `get_xcode_build`, `get_test_run` | Bir GitHub Actions çalıştırması, GitHub deposuna bağlı olmayan bir projeye aittir. |
| `other_build_systems` | `get_project` | Hesap, desteklenen her derleme sistemiyle Tuist’i kullanmıyor. İpucu, diğerlerini tanımlayan dosyaları listeler, böylece aracı depoyu kontrol edebilir. |

#### Dokümantasyon ve topluluk araması

Bu salt okunur araç, Tuist’in dokümantasyonunu, [uygulama programlama arayüzü](https://en.wikipedia.org/wiki/API) referansını, GitHub sürümlerini, topluluk forumunu ve GitHub sorunlarını dokümantasyon web sitesini çalıştıran aynı arama motoru aracılığıyla arar. Sürüm sonuçları ürünü, sürümü, yayın tarihini ve ön sürüm durumunu içerir. Varsayılan olarak kararlı sürümler aranır ve ön sürümler `include_prereleases` ile dahil edilebilir. Araç yalnızca `https://tuist.dev/mcp` adresindeki Tuist tarafından barındırılan sunucuda kullanılabilir.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `search_tuist` | Genel Tuist dokümantasyonunu, uygulama programlama arayüzü referansını, GitHub sürümlerini, topluluk tartışmalarını ve GitHub sorunlarını arayın. İsteğe bağlı olarak tek bir `source` ile sınırlayın (`docs`, `api_reference`, `releases`, `forum`, `issues`). | `query` |

#### Geri bildirim

Ajanlar, bir Tuist aracının veya isteminin bekledikleri gibi çalışmadığında (örneğin kafa karıştırıcı bir sonuç, hata, eksik veri veya eksik bir yetenek) Tuist ekibine bildirebilir. Ajanlardan bir rapor önermeleri ve yalnızca siz onay verdikten sonra göndermeleri istenir. Her rapor, Tuist desteğiyle bir konuşma başlatır; destek ekibi size e-posta ile yanıt verebilir. Bir rapor, ajanın ne beklediğini, ne olduğunu, isteğe bağlı bir öneriyi, Tuist kullanıcı kimliğinizi, kullanıcı adınızı ve e-postanızı ile ait olduğunuz kuruluşları içerir. Ajanlar ayrıca sorunun gerçekleştiği hesabı ve projeyi belirtebilir, böylece ekip hangi kuruluşla iletişime geçeceğini bilir; yalnızca ait olduğunuz hesaplar kabul edilir. Raporları yalnızca Tuist kullanıcısı olarak oturum açmış ajanlar gönderebilir ve her kullanıcı saatte en fazla 10 rapor açabilir. Araç yalnızca `https://tuist.dev/mcp` adresindeki Tuist tarafından barındırılan sunucuda kullanılabilir.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `report_feedback` | Bir Tuist aracı veya istemiyle ilgili bir sorunu bildirin. İsteğe bağlı olarak `tool_name`, gerçekleştiği `account_handle` ve `project_handle` değerlerini belirtin ve bir `suggestion` ekleyin. | `category`, `expected`, `actual` |

#### Kaynak destekli yanıtlar

Bu salt okunur araçlar, ajanların mevcut davranışa bağlı yanıtlar için gerçek kaynak olarak barındırılan sunucuyla birlikte dağıtılan tam genel Tuist kaynak revizyonunu kullanmasına olanak tanır. Yalnızca `https://tuist.dev/mcp` adresinde kullanılabilirler.

Uyumlu istemciler, başlatma sırasında araçların kaynak revizyonuna ilişkin olgusal açıklamaları, bağlantıları ve sonuç sınırlamalarını satır içi OAuth kimlik doğrulama bilgilerinin yanında alır. Bu açıklamalar yanıt stilini veya bir doğrulama iş akışını dayatmaz. Kullanıcılar, önce `ask_tuist` istemini çağırmadan doğrudan bir soru sorabilir; istem, açık kaynak destekli bir iş akışı için kullanılmaya devam eder.

Her işlem için eşzamanlılık, süre, gezinme, okunan bayt ve yanıt boyutu açısından sabit sınırlar vardır. Arama ve listeleme sonuçları `truncated` ve `truncation_reason` alanlarını içerir. Bir sonuç kısaltıldığında, sonucu kapsamlı olarak değerlendirmek yerine yolu, dosya desenini veya arama terimini daraltın.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `search_tuist_code` | Kaynak dosyaları arayarak mevcut davranış, varsayılanlar, yapılandırma, özellik kapıları, hata yönetimi veya belgelenmemiş ayrıntılar hakkındaki soruları yanıtlayın. Sonuçlar çevreleyen satırları, revizyon sabitli kaynak bağlantılarını ve tarama istatistiklerini içerir. | `pattern` |
| `list_tuist_files` | İlgili yol bilinmediğinde bir kaynak alt sistemini veya yakındaki testleri keşfedin. Listelemelerin derinliği ve sonuç sayıları sınırlıdır. | Yok |
| `read_tuist_file` | İlgili yolu bulduktan sonra bir uygulama dosyasında, çağrı noktasında veya testte odaklanmış bir satır aralığını inceleyin. Kısaltılmış yanıtlar, devam için `next_start_line` sağlar. | `path` |

#### Projeler

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_accounts` | Kimliği doğrulanmış kullanıcı için kullanılabilen kişisel ve kuruluş hesap kullanıcı adlarını, her hesabın proje oluşturup oluşturamayacağı dahil olmak üzere listeleyin. | Yok |
| `get_organization` | Bir kuruluşun üye dizinini alın. Bekleyen davetler, pano ile aynı yönetici iznini gerektirir; davet kabul belirteçleri asla döndürülmez. | `account_handle` |
| `create_organization` | Kimliği doğrulanmış kullanıcı için bir Tuist kuruluşu oluşturun. | `handle` |
| `create_project` | Kimliği doğrulanmış kullanıcının erişebildiği bir hesap altında bir Tuist projesi oluşturun. | `account_handle`, `project_handle` |
| `add_organization_member` | Mevcut bir Tuist kullanıcısını bir kuruluşa ekleyin veya mevcut bir üyenin rolünü güncelleyin. `user` (varsayılan), `admin` veya `viewer` kabul edilir; burada görüntüleyici panoları ve çalıştırmaları okuyabilir ancak hiçbir şeyi değiştiremez. | `organization_handle`, `email` |
| `invite_organization_member` | Bir e-posta adresini, mevcut bir Tuist kullanıcısına ait olup olmadığına bakılmaksızın bir kuruluşa davet edin. Tuist, 14 gün sonra sona eren bir kabul bağlantısı e-postası gönderir; sunucu e-posta gönderemediğinde `email_sent` değeri `false` olur ve bağlantının panodan kopyalanması gerekir. `user` (varsayılan), `admin` veya `viewer` kabul edilir. Kuruluş yöneticisi izni gerektirir. | `organization_handle`, `email` |
| `cancel_organization_invitation` | Bekleyen bir kuruluş davetini iptal edin, böylece bağlantısı artık kabul edilemez. Kuruluş yöneticisi izni gerektirir. | `organization_handle`, `email` |
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

Bu araçlar, kimliği doğrulanmış kullanıcının kendi bildirim kurallarını yönetir: Kuralın projelerinde (veya hiçbirini listelemediğinde bildirim alabileceğiniz herhangi bir projede) yeni bir önizleme gibi bir olay gerçekleştiğinde ve koşulları karşıladığında, Tuist uygulama cihazlarınıza push bildirimi gibi eylemlerini çalıştırır. Kurallar olmadan bildirim almazsınız. Kullanıcı kimlik doğrulaması gerektirirler, yalnızca kendi kurallarınız üzerinde işlem yaparlar ve yalnızca ait olduğunuz hesaplara ait projeleri kabul ederler. Kurallar tüm hesaplarınızı kapsadığından pano sayfalarında sunulmazlar.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_notification_events` | Kuralların abone olabileceği olay türlerini, her biri için koşullarına ilişkin bir JSON Şeması ile birlikte listeleyin. | Yok |
| `list_notification_condition_options` | Bir projedeki bir olay için koşul değerlerini önerin, örneğin son önizlemelerinin kanalları ve dalları. | `event`, `account_handle`, `project_handle` |
| `list_notification_rules` | Kurallarınızı listeleyin. | Yok |
| `create_notification_rule` | Bir olaydan, isteğe bağlı projelerden ve koşullardan ve en az bir eylemden oluşan bir kural oluşturun. | `event`, `actions` |
| `update_notification_rule` | Bir kuralın etkin durumunu, projelerini, koşullarını veya eylemlerini değiştirin. | `rule_id` |
| `delete_notification_rule` | Bir kuralı silin. | `rule_id` |

#### Sürekli entegrasyon çalıştırıcıları

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_runner_jobs` | Bir hesap için sürekli entegrasyon çalıştırıcı işlerini listeleyin. | `account_handle` |
| `get_runner_job` | Bir sürekli entegrasyon çalıştırıcı işini alın; makinenin belleğinin dolup dolmadığı, neyi durdurduğu ve neyin değiştirileceği dahil. | `account_handle`, `workflow_job_id` |
| `list_runner_job_steps` | Bir sürekli entegrasyon çalıştırıcı işi için kaydedilen adımları listeleyin. | `account_handle`, `workflow_job_id` |
| `list_runner_job_metrics` | Bir sürekli entegrasyon çalıştırıcı işi için kaydedilen makine metriklerini listeleyin. | `account_handle`, `workflow_job_id` |
| `list_runner_job_logs` | Bir sürekli entegrasyon çalıştırıcı işi için yakalanan en fazla 500 günlük satırını listeleyin. | `account_handle`, `workflow_job_id` |
| `list_runner_workflows` | Bir hesap için sürekli entegrasyon iş akışı özetlerini listeleyin. | `account_handle` |
| `list_runner_profiles` | Bir hesap için sürekli entegrasyon çalıştırıcı profillerini, her birinin `runs-on` etiketiyle birlikte listeleyin. | `account_handle` |
| `get_runner_catalog` | Bir çalıştırıcı profilinin kullanabileceği makine şekillerini ve Xcode sürümlerini listeleyin. | `account_handle` |
| `create_runner_profile` | Bir platform, bir makine şekli ve macOS'ta bir Xcode sürümü ile bir çalıştırıcı profili oluşturun. İsteğe bağlı olarak hangi dalların önbellek birimlerini kaydedeceğini ayarlayın. Hesap yöneticiliği veya `account:runners:write` kapsamı gerektirir. | `account_handle`, `name`, `platform`, `vcpus`, `memory_gb` |
| `update_runner_profile` | Bir çalıştırıcı profilinin makine şeklini, Xcode sürümünü veya hangi dalların özel önbellek birimi değişikliklerini kaydettiğini değiştirin. Atlanmış alanlar değerlerini korur. Hesap yöneticiliği veya `account:runners:write` kapsamı gerektirir. | `account_handle`, `profile_name` |
| `delete_runner_profile` | Kullanıcı onayından sonra bir çalıştırıcı profilini silin. Varsayılan profiller silinemez. Hesap yöneticiliği veya `account:runners:write` kapsamı gerektirir. | `account_handle`, `profile_name` |

Çalıştırıcı birimi araçları, Birimler panosuyla aynı verileri gösterir. Okuma araçları çalıştırıcı erişimi gerektirir; temizleme işlemi hesap yöneticiliği veya `account:runners:write` kapsamı ve kullanıcı onayı gerektirir.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_runner_volumes` | Birimleri ada ve depoya göre filtreleyin, sıralayın ve sayfalandırın. | `account_handle` |
| `get_runner_volume` | Depo, platform, kapasite, kullanılan alan ve son kullanım. | `account_handle`, `volume_id` |
| `list_runner_volume_jobs` | Sayfalandırılmış iş ve iş akışı referansları, önbellek durumu, isabet sonucu ve bağlama zamanı. | `account_handle`, `volume_id` |
| `list_runner_job_volumes` | Bir iş tarafından bağlanan birimler. | `account_handle`, `workflow_job_id` |
| `get_runner_volume_analytics` | Depolama serileri, iş çalıştırmaları, isabet oranı ve eğilimler. İsteğe bağlı `volume_id`, `start` ve `end` (ISO 8601); varsayılan yedi gün, maksimum 90. | `account_handle` |
| `delete_runner_volume` | Bir birimi ve kaydedilen içeriğini silin. Çalışan işler kendi kopyalarını tutar ancak bunları kaydedemez; aynı anahtara sahip sonraki işler boş başlar. | `account_handle`, `volume_id` |

Listeler `page` ve `page_size` (en fazla 100) kabul eder. Birim envanteri ayrıca `name` ve `repository` (tam eşleşmeler, AND ile birleştirilmiş), `sort_by` (`volume`, `repository`, `used_space`, `capacity`, `last_used`) ve `sort_order` (`asc`, `desc`) kabul eder. Bilinmeyen ölçümler ve isabet sonuçları `null` olarak kalır. Önbellek durumu, birim değişikliklerinin kaydedilip kaydedilmediğini açıklar, iş başarısını değil.

#### Sandbox'lar

Sandbox araçları, Sandbox'lar panosuyla aynı verileri ve eylemleri, [API](https://tuist.dev/api/docs) ile aynı erişimle sunar: hesap üyeleri hesaptaki her sandbox'ta her aracı kullanabilir. Salt okunur görüntüleyiciler bunları kullanamaz. Hesabın sandbox'ların etkinleştirilmiş olması gerekir. Panonun sandbox sayfaları salt okunur araçları kaydeder.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_sandboxes` | Sandbox'ları durumları, şekilleri ve zaman damgalarıyla sayfalandırın. İsteğe bağlı `search` (sandbox'taki metin, Amp Orb veya Anthropic oturum kimliği), `status`, `vcpus`, `sort_by` (`created`, `last_active`, `identifier`) ve `sort_order`. | `account_handle` |
| `get_sandbox` | Bir sandbox'ın durumu, şekli, düğümü, arşivi ve zaman damgaları. | `account_handle`, `sandbox_id` |
| `get_sandbox_analytics` | vCPU-saatleri, oluşturulan sandbox'lar, oturum, kurulum ve başlama süresi süreleri ve hesabın sınırlarına karşı tepe vCPU'lar, bellek ve disk, eğilimlerle birlikte. İsteğe bağlı `start` ve `end` (ISO 8601); varsayılan 30 gün, maksimum 90. | `account_handle` |
| `create_sandbox` | Boş bir sandbox önyükleyin ve çalıştığında onu döndürün. İsteğe bağlı `platform` (`linux` veya `darwin`), `xcode_version` (bir macOS sandbox'ının tam Xcode sürümü, aracın açıklamasında listelenenlerden; `darwin` anlamına gelir), `template`, `memory_mb` ile `vcpus` (Linux: 2x4096, 4x8192 veya 8x16384, varsayılan 2x4096; macOS: 8x8192, 8x16384 veya 8x24576, varsayılan 8x8192) ve `workspace_gb`. Açıklaması, araca Mac'te `mise install` ile deposunun sabitlenmiş Tuist'ini yüklemesini söyler, bu da ardından kendi başına <.localized_link href="/guides/features/sandboxes#tuist-in-sandbox">hesabın önbelleğini kullanır</.localized_link>. | `account_handle` |
| `pause_sandbox` | Çalışan bir sandbox'ın anlık görüntüsünü düğümünün diskine alın. | `account_handle`, `sandbox_id` |
| `resume_sandbox` | Duraklatılmış veya arşivlenmiş bir sandbox'ı devam ettirin. | `account_handle`, `sandbox_id` |
| `archive_sandbox` | Duraklatılmış bir sandbox'ın disklerini nesne depolamaya taşıma işlemini sıraya alın. | `account_handle`, `sandbox_id` |
| `delete_sandbox` | Kullanıcı onayından sonra bir sandbox'ı ve disklerini silin. | `account_handle`, `sandbox_id` |

#### Amp çalışma alanları

Bu araçlar, orb'ların belirteç olmadan Tuist'te oturum açmasına olanak tanıyan <.localized_link href="/guides/server/authentication#amp-orbs">Amp çalışma alanı bağlantılarını</.localized_link> yönetir. Panonun Entegrasyonlar sayfasıyla aynı yalnızca yönetici iznini kullanırlar. Bir orb'daki bir ajan, kendi kimliklerini `$AMP_WORKSPACE_ID` ve `$AMP_PROJECT_ID` üzerinden okuyabilir. Bir bağlantının kabul ettiği her orb, hesaptaki tüm projelere CI erişimi kazanır, bu nedenle ajanlar bağlanmadan önce kullanıcıyla onaylamalıdır.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_amp_workspace_connections` | Hesabın bağlı Amp çalışma alanlarını ve her birinin sınırlandırıldığı projeyi, varsa listeleyin. | `account_handle` |
| `connect_amp_workspace` | Bir Amp çalışma alanını bağlayın. İsteğe bağlı `project_id`, oturum açmayı tek bir Amp projesinin orb'larıyla sınırlar. | `account_handle`, `workspace_id` |
| `disconnect_amp_workspace` | Bir çalışma alanının bağlantısını kesin. Orb'larının zaten sahip olduğu oturumlar, süresi dolana kadar geçerli kalır. | `account_handle`, `connection_id` |

#### Claude ortamları

Bu araçlar, Claude Yönetilen Ajanların kendi kendine barındırılan ortamlarını bağlar, böylece oturumları Ayarlar → Entegrasyonlar → Claude gibi Tuist sandbox'larında çalışır. Hesap yöneticiliği ve etkinleştirilmiş sandbox'lar gerektirirler. Bir ajan, ortamı Anthropic'in API'si ile oluşturabilir, ancak yalnızca Claude Konsolu ortam anahtarını oluşturur, bu nedenle ajan kullanıcıdan bunu ister. Tuist, oturumları bir Anthropic API anahtarı veya iş yükü kimlik federasyonu ile başlatır ve kaydetmeden önce o kimlik bilgisiyle ortamı getirir. Anthropic tarafındaki kurulum, kullanıcının kendi Anthropic kimlik bilgilerini kullanır; Tuist bunları asla almaz. Anahtarlar istemci ve model üzerinden geçtiğinden, bunları yalnızca açıkça sağlayın.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_claude_environments` | Bağlı ortamları ve her birinin kullandığı kimlik bilgisini, ayrıca bir federasyon kuralının güvenmesi gereken yayıncı URL'sini ve konu önekini listeleyin. | `account_handle` |
| `connect_claude_environment` | Bir ortamı `api_key` ile veya `organization_id`, `workspace_id`, `service_account_id` ve `federation_rule_id` ile bağlayın. İsteğe bağlı `platform`, `vcpus` ve `memory_mb` sandbox boyutunu belirler. | `account_handle`, `environment_id`, `environment_key` |

#### Organizasyon Yapay Zekası

Bu araçlar, Ayarlar → Yapay Zeka gibi bir organizasyonun sunucu tarafı yapay zeka görevlerinin kullandığı modelleri yönetir ve aynı kuralları paylaşır: yalnızca organizasyon yöneticileri için ve yalnızca yapay zeka ayarlarına sahip organizasyonlar için geçerlidir. `pulse_grouping` veya `pulse_explanation` gibi her görev, varsa kendi görev rotasını kullanır; aksi takdirde varsayılan modeli kullanır; ikisi de yoksa istek göndermez. Her araç, her görevin mevcut modelini ve bunun rotasından, varsayılandan mı yoksa hiçbirinden mi geldiğini içeren tüm yapılandırmayı döndürür. Bir sağlayıcı eklemek veya düzenlemek bir API anahtarı gerektirdiğinden, bu işlem panoda veya REST API (`/api/accounts/{handle}/ai`) üzerinden yapılır, bu araçlar üzerinden değil.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `get_organization_ai_configuration` | Sağlayıcıları (anahtarlar olmadan), modelleri, varsayılan modeli, görev rotalarını ve her görevin mevcut modelini okuyun. | `account_handle` |
| `save_organization_ai_model` | Bir model ekleyin (`name`, `provider_id`, `upstream_model_id`) veya `id` ile birini güncelleyin. | `account_handle` |
| `remove_organization_ai_model` | Bir modeli ve onun görev rotalarını kaldırın. | `account_handle`, `model_id` |
| `set_organization_ai_default_model` | Varsayılan modeli seçin veya null ile temizleyin. | `account_handle`, `model_id` |
| `save_organization_ai_task_route` | Bir `task` öğesini yapılandırılmış bir `model_id` öğesine yönlendirin veya `id` ile bir rotayı güncelleyin. Bir görevin en fazla bir rotası olabilir. | `account_handle` |
| `remove_organization_ai_task_route` | Bir rotayı kaldırın, böylece görev tekrar varsayılan modeli kullansın. | `account_handle`, `route_id` |
| `remove_organization_ai_provider` | Anahtarı, modelleri ve bunların rotalarıyla birlikte bir sağlayıcıyı kaldırın; bağlantılı bir Claude organizasyonunun bağlantısını kesin. | `account_handle`, `provider_id` |

#### Webhook'lar

Webhook araçları, pano ile aynı yalnızca yönetici iznini kullanır. Teslimat denemeleri, uç nokta için kaydedilen istek ve yanıt verilerini içerir ancak asla uç nokta imzalama gizli anahtarını içermez.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_webhook_endpoints` | Bir hesap için webhook uç noktalarını listeleyin. | `account_handle` |
| `get_webhook_endpoint` | Bir webhook uç noktası alın. | `account_handle`, `webhook_endpoint_id` |
| `list_webhook_delivery_attempts` | Bir uç nokta için teslimat denemelerini listeleyin. | `account_handle`, `webhook_endpoint_id` |
| `get_webhook_delivery_attempt` | Bir teslimat denemesi alın. | `account_handle`, `webhook_endpoint_id`, `delivery_attempt_id` |

#### Xcode derlemeleri

Xcode, Gradle, Bazel, Mix ve Cargo için derleme ayrıntısı araçları, bildirildiğinde altyapı gözlemleri dahil olmak üzere mevcut `custom_metadata: {tags, values}` yapısını ortaya çıkarır. Değerler dize olarak kalır ve bilinmeyen anahtarlar korunur. Örneğin, `tuist.cpu.available_processors` çalışma zamanında kullanılabilen mantıksal işlemcileri tanımlarken, `tuist.gradle.max_workers` bir Gradle işçi sınırıdır ve `tuist.jvm.max_heap_bytes` bir JVM yığın sınırıdır, ana makine belleği değildir. Bunlar güvenilir olmayan istemci gözlemleridir, doğrulanmış çalıştırıcı kimlikleri değildir. Eksik gözlemler eksik kalır; içe aktarılan günlükler ve eski istemcilerde altyapı meta verileri olmayabilir. Meta veri, koordineli bir istemci/protokol güncellemesini beklemektedir.

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_xcode_builds` | Bir proje için Xcode derleme çalıştırmalarını listeleyin. | `account_handle`, `project_handle` |
| `get_xcode_build` | Ham `.xcactivitylog` dosyasını içeren arşiv için geçici bir indirme URL'si dahil olmak üzere belirli bir Xcode derleme çalıştırması hakkında ayrıntılı bilgi alın. | `build_run_id` |
| `list_xcode_build_targets` | Belirli bir Xcode derleme çalıştırması için derleme hedeflerini listeleyin. | `build_run_id` |
| `list_xcode_build_files` | Belirli bir Xcode derleme çalıştırması için derlenmiş dosyaları listeleyin. | `build_run_id` |
| `list_xcode_build_steps` | Kayıt altına alınan derleme adımlarını zamanlamalar ve sonuçlarla birlikte, günlük metni olmadan listeleyin. | `build_run_id` |
| `get_xcode_build_step` | Günlüğü ve kesme bayrağı dahil olmak üzere tek bir kayıt altına alınmış derleme adımını alın. | `build_run_id`, `step_id` |
| `list_xcode_build_issues` | Belirli bir derleme çalıştırması için derleme sorunlarını (uyarılar ve hatalar) listeleyin. | `build_run_id` |
| `list_xcode_build_cache_tasks` | Belirli bir Xcode derleme çalıştırması için önbelleklenebilir görevleri (önbellek isabetleri/kaçışları) listeleyin. | `build_run_id` |
| `list_xcode_build_cas_outputs` | Belirli bir Xcode derleme çalıştırması için [içerik adreslenebilir depolama](https://en.wikipedia.org/wiki/Content-addressable_storage) çıktılarını listeleyin. | `build_run_id` |

`list_xcode_build_steps`, varsayılan olarak 20 adımdan oluşan sayfalar döndürür (maksimum 100 `page_size` aracılığıyla), gezinme için `page` ve `pagination_metadata` ile birlikte. Başlıkları, projeleri veya hedefleri eşleştirmek için `search` kullanın veya tam `project`, `target`, `category` (örneğin, `swiftCompilation`) ve `status` (`success` veya `failure`) filtreleyin. En yavaş olanı önce getirmek için `duration_ms` (varsayılan) veya kronolojik sıra için `start_ms` ile sıralayın. Adım kimlikleri beraberlikleri bozar ve tam 64 bit hassasiyetlerini korumak için ondalık dizeler olarak döndürülür. Kimlikler bir derlemeyle sınırlıdır ve derlemeler arasında eşleştirilmemelidir.

İsteğe bağlı `start_ms` ve `end_ms`, derleme başlangıcından itibaren milisaniye cinsinden bir zaman aralığıyla örtüşen adımları seçer; bitiş hariçtir. Her iki araç da `build_run_id` olarak bir derleme UUID'sini veya pano URL'sini kabul eder. Döndürülen adım `id` değerini `step_id` olarak değiştirilmeden iletin ki günlüğünü alabilesiniz. Günlükler adım başına 64 KiB'a kadar saklanır, `log_truncated` atlanan çıktıyı belirtir.

Adımlar, Xcode derlemeleri işlendiğinde varsayılan olarak toplanır. Kaydedilen adım verileri 90 gün boyunca saklanır. Liste yanıtı `availability` içerir: Filtreler hiçbiriyle eşleşmese bile kaydedilmiş adımlar varsa `available`; derleme hala işleniyorsa ve henüz adım yoksa `processing`; veya adımlar kaydedilmediyse veya süresi dolduysa `unavailable`.

Aynı işlemler, aynı filtreler ve sayfalama ile `GET /api/projects/{account_handle}/{project_handle}/xcode/builds/{build_id}/steps` ve `GET /api/projects/{account_handle}/{project_handle}/xcode/builds/{build_id}/steps/{step_id}` HTTP API uç noktalarında kullanılabilir. Her ikisi de derlemenin projesine okuma erişimi gerektirir.

#### Gradle derlemeleri

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `get_gradle_integration_guide` | Tam kimlik doğrulama, proje kurulumu, Gradle eklentisi, önbellek politikası ve iki derlemeli doğrulama iş akışını döndürün. Ajanlar, mevcut bir Android veya Gradle projesini düzenlemeden önce bunu çağırmalıdır. | Yok |
| `list_gradle_builds` | Bir proje için özel meta veriler dahil olmak üzere Gradle derleme çalıştırmalarını listeleyin. İsteğe bağlı `tag` parametresi ile özel bir etikete göre filtreleyin. | `account_handle`, `project_handle` |
| `get_gradle_build` | Derleme meta verilerini, görev/önbellek sayılarını ve `failures` öğesini alın: başarısız olan her görevin ve yapılandırma adımının hata mesajı. | `build_run_id` |
| `list_gradle_build_tasks` | Görev sonuçlarını, bileşik derleme kimliğini, önbelleklenebilirliği, artımlı durumu ve hata mesajlarını listeleyin. | `build_run_id` |
| `list_gradle_build_steps` | Arama, meta veri ve örtüşen zaman filtreleri ile zamanlanmış görevleri, yapılandırmayı ve dönüşümleri listeleyin. | `build_run_id` |
| `get_gradle_build_step` | Opak kimliğe göre kaydedilen adım meta verilerini inceleyin; başarısız bir görevin veya yapılandırma adımının `log` değeri, onun hata mesajıdır. | `build_run_id`, `step_id` |

Gradle ve Bazel adım listeleri varsayılan olarak 20 sonuç döndürür (maksimum 100), `search`, tam `project`, `target`, `category` ve `status` desteği sunar, örtüşen `start_ms` / `end_ms` filtrelerini (bitiş hariç) ve `duration_ms` veya `start_ms` sıralamasını destekler. Döndürülen kimlikleri değiştirilmeden iletin; bunlar kendi derlemeleriyle sınırlıdır. Listeler `time_origin` ve `coverage` gösterir. Eski Gradle raporları, derleme başlangıcı yüklenmediği için `first_recorded_timestamp` kullanır. Bazel profilleri, tüm kaydedilen aralıkları `trace_profile` kapsamı ve zaman kökeni olarak `profile_start` ile gösterir. Daha eski derlemeler, saklanan BEP özetlerine geri döner. Kaynak kayıtlar 90 gün sonra süresi dolar. Bazel ayrıntıları, yayınlandığında sanitize edilmiş eylem günlüklerini içerir. Başarısız bir görevin veya yapılandırma adımının Gradle ayrıntıları, Tuist Gradle eklentisinin `log` olarak bildirdiği hata mesajını içerir: istisna mesajı ve neden zinciri, Gradle konsolunun yazdırdığı gibi, yığın izleri veya görev çıktısı olmadan, proje içindeki yollar göreceli hale getirilmiş ve kimlik bilgileri ile diğer yerel yollar sansürlenmiş olarak, adım başına en fazla 16 KiB ve derleme başına 32 başarısız adım. Diğer Gradle adımları, daha eski eklenti sürümleri tarafından bildirilen derlemeler ve kimlik bilgisi içermeyen raporlar null `log` değerine sahiptir. Yapılandırma adımları, başarısız olduklarında `failure` ve aksi takdirde `unknown` bildirir. `compare_builds` istemi, bu kapsamı tam Bazel izlerini saklanan özetlerden ayırt etmek için kullanır ve ajanları, daha geniş çağrı çıktısını kontrol etmeden önce eylem sonuçları ve günlükler için adım ayrıntılarına yönlendirir.

Tek adımlı araçlar `get_gradle_build_step` ve `get_bazel_build_step` bir adımı kimliğine göre alır ve zaman filtrelerini kabul etmez; adımları zaman aralığına göre filtrelemek için ilgili liste araçlarını kullanın.

Saklanan özetlerden döndürülen Bazel adım kimlikleri, listeleme ile bir adımı getirme arasında tam bir profil gelirse okunabilir kalır. Adım verilerinin süresi dolmuş indekslenmiş bir profil, kullanılamıyor olarak bildirir. Gradle adım listeleri, sıfır süreli önbelleğe alınmış ve atlanan işlemleri içerir.

#### Bazel çağrıları

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `get_bazel_integration_guide` | Kimlik doğrulama, proje kurulumu, Bazel yapılandırması ve doğrulama iş akışını döndürün. | Yok |
| `list_bazel_invocations` | Bir proje için en yeniden eskiye doğru tamamlanmış [Bazel Build Event Protocol](https://bazel.build/remote/bep) çağrılarını, derleme metrikleri, sınırlı bir yürütme zaman çizelgesi, kritik yol tanılama ve ilişkili uzak önbellek toplamları ile listeleyin. `status`, `git_branch`, `git_commit_sha`, `is_ci` ve `command` ile filtreleyin. | `account_handle`, `project_handle` |
| `get_bazel_invocation` | Derleme metrikleri, sınırlı bir yürütme zaman çizelgesi, kritik yol tanılama ve ilişkili uzak önbellek toplamları ile tek bir tamamlanmış Bazel çağrısını alın. | `account_handle`, `project_handle`, `invocation_id` |
| `list_bazel_build_steps` | Filtreler ve açık kapsam ile kaydedilen Bazel profil aralıklarını listeleyin. | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_build_step` | Kaydedilen bir Bazel adımını ve yayınlanan eylem sonucunu ve sanitize edilmiş günlüğünü inceleyin. | `account_handle`, `project_handle`, `invocation_id`, `step_id` |
| `list_bazel_invocation_logs` | Bir Bazel çağrısı için yakalanan sanitize edilmiş günlükleri yürütme sırasına göre listeleyin: Bazel'in ilerleme çıktısının sınırlı kuyruk kısmı ve `test.log` yapıtları. İsteğe bağlı `stream` (`stdout` veya `stderr`), `source` (`progress` veya `test_log`), `target_label` ve `errors` filtreleri sonuçları daraltır. | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_invocation_log` | Bir Bazel çağrısı için yakalanan tek bir sanitize edilmiş günlük parçasını alın. | `account_handle`, `project_handle`, `invocation_id`, `invocation_log_id` |
| `list_bazel_cache_events` | İşlemi, uç noktası ve gözlem zamanı ile ham Bazel uzak önbellek gözlemlerini listeleyin; isteğe bağlı olarak bir çağrı, sonuç veya işlemle daraltılabilir. | `account_handle`, `project_handle` |
| `get_bazel_cache_event` | Tek bir ham Bazel uzak önbellek gözlemini alın. | `account_handle`, `project_handle`, `cache_event_id` |

#### Uzak yürütme

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `get_remote_execution_activity` | Projenin çalışan Bazel çağrılarını ve şu anda çalışan ve kuyruğa alınmış uzak eylemlerini, her eylemin çağrısı, mnemoniği, hedefi, eylem özeti, makine boyutu ve bu duruma ne zaman girdiği ile birlikte listeleyin. Yürütme ağ geçidinin önceden hazırladığı bir VM üzerinde çalıştırdığı eylemler, bitene kadar listelenmez. | `account_handle`, `project_handle` |
| `get_remote_execution_usage` | Projenin uzak yürütmelerini ve `[from, to)` üzerindeki ölçülen yürütme süresini toplamda, makine boyutu başına, dağıtım modu başına ve saat, gün veya ay başına alın. Dönem varsayılan olarak son 30 gündür ve en fazla 366 günü kapsar. | `account_handle`, `project_handle` |

`list_bazel_invocations` filtreleri tam eşleşmelerdir ve aynı saniyede biten çağrılar çağrı kimliğine göre sıralanır. Bir dalda en son başarısız olan çağrıyı bulmak için `status: "failure"`, `git_branch` ve `page_size: 1` ile çağırın. REST uç noktası `GET /api/projects/{account_handle}/{project_handle}/bazel/invocations` aynı filtreleri kabul eder.

Yalnızca indekslenmiş profillerden güvenli bir şekilde ilişkilendirilmiş sunucu aşaması zamanlamalarına sahip eylemleri döndürmek için `list_bazel_build_steps` üzerinde `remote_execution: true` ayarlayın. Liste ve ayrıntı yanıtları, isteğe bağlı null yapılabilir `remote_queue_ms`, `remote_input_fetch_ms`, `remote_execution_ms` ve `remote_output_upload_ms` değerlerini gösterir. Değerler, eylem içindeki yeniden denemeler dahil olmak üzere kaydedilen aşamaları toplar; eksik veya null değerler sıfır değil, kullanılamaz anlamına gelir. Bunlar profil gözlemleridir, faturalandırılabilir kullanım veya yeni yürütme kanıtı değildir, çünkü önbelleğe alınmış sunucu sonuçları yürütme meta verileri taşıyabilir. İstemci yüklemeleri hariç tutulur. Daha eski veya belirsiz profiller, uzak iş gerçekleşse bile eşleşen eylem döndürmeyebilir. Adım REST uç noktası aynı `remote_execution=true` filtresini kabul eder. Panonun Uzak yürütme sekmesi aynı sorguyu ve 90 günlük saklama süresini kullanır.

Test günlükleri, geldikleri test sonucunun `target_label` ve deneme `status` değerlerini taşır, bu nedenle `target_label: "//foo:bar_test"` yalnızca o hedefin test günlüklerini döndürür. `errors: true` başarısız denemelerin test günlüklerini ve Bazel raporlayıcısının `ERROR:`, `FAIL:` veya `TIMEOUT:` ile başladığı bir satır içeren stderr ilerleme parçalarını döndürür. İlerleme çıktısı hedeflere atanmaz ve atama kaydedilmeden önce yazılan günlükler boş alanlara sahiptir. Başarısız eylemler ve kendi çıktıları `list_bazel_build_steps` üzerinden hedef başına ve test çalıştırma araçlarından test senaryosu başına başarısızlıklar olarak mevcuttur.

#### Cargo derlemeleri

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_cargo_builds` | Bir proje için Cargo derlemelerini, en yeniden eskiye sıralayarak listeler. `git_branch`, `status`, `is_ci` veya `command` ile filtreleyin. Cargo test yürütme sonuçları bu derleme listesi üzerinden değil, test araçları aracılığıyla kullanılabilir. | `account_handle`, `project_handle` |
| `get_cargo_build` | Derleme meta verilerini, toplam önbellek sayaçlarını ve tanılama bilgileriyle birlikte kaydedilmiş en fazla 500 derleyici işini alın. `compilations_truncated` atlanan işleri gösterir; tanılama yalnızca döndürülen işleri kapsar. | `account_handle`, `project_handle`, `build_id` |

Doğrulanmış görev kararlarını ve CAS işlemlerini almak, 4 MB ile sınırlı olarak, `get_cargo_build` üzerinde `include_cache_inspection: true` ayarlayın. Varsayılan olarak ve kayıtlar eksik veya geçersiz olduğunda `cache_inspection` null değerindedir. Kısmi yakalama `truncated` bayrağına saygı gösterin; aktarımlar her görev isabetinin yerel/uzak kökenini belirlemez. HTTP ayrıntı uç noktası aynı sorgu parametresini kabul eder.

#### Mix derlemeleri

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_mix_builds` | Bir proje için Mix (Elixir) derleme derlemelerini, özel meta veriler dahil olmak üzere en yeniden eskiye sıralayarak listeler. `git_branch`, `status`, `is_ci` veya `mix_env` ile filtreleyin. | `account_handle`, `project_handle` |
| `get_mix_build` | Derleme meta verilerini, tanılama sayılarını ve bağımlılık önbelleği özetini alın. | `account_handle`, `project_handle`, `build_id` |

#### Derleme izleri

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `get_build_trace` | [Perfetto](https://ui.perfetto.dev) içinde açabileceğiniz bir iz dosyası olarak bir Xcode, Gradle, Bazel veya Mix derlemesinin zaman çizelgesi için bir indirme bağlantısı alın. | `account_handle`, `project_handle`, `build_id` |

`build_id`, derleme çalıştırma kimliğidir (Bazel için çağrı kimliği) veya derlemenin pano URL'sidir. Döndürülen `trace_url`, bir [Chrome Trace Event](https://docs.google.com/document/d/1CvAClvFfyA5R-PhYUmn5OOQtYMH4h6I0nSsKchNAySU) JSON dosyası sunar. Bağlantıya sahip olan herkes, aramadan bir saat sonra sona eren `expires_at` tarihine kadar başka kimlik bilgisi olmadan o derlemenin izini indirebilir. Ajanlar bunu `curl` ile indirebilir, Perfetto'da açmanız için size verebilir veya Perfetto'nun `trace_processor` ile sorgulayabilir. İz, paralellik tarafından şeritlere paketlenmiş kaydedilmiş adımları, tüm derlemeyi kapsayan bir parçayı ve derleme makine ölçümlerini kaydettiğinde CPU ve bellek sayaçlarını içerir. Günlükler hariç, yukarıdaki adım araçlarıyla aynı verileri tutar. Pano, her derlemenin Zaman Çizelgesi sekmesinden aynı dosyayı sunar.

#### Once çalıştırmaları

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_once_runs` | Bir proje için Once çalıştırmalarını, en yeniden eskiye sıralayarak listeler. `kind` (`build`, `test` veya `generic`), `status`, `is_ci` veya `git_branch` ile filtreleyin. Tamamlanmamış çalıştırmaların durumu `in_progress` olur. | `account_handle`, `project_handle` |
| `get_once_run` | Eylem toplamları, önbellek özeti ve test çalıştırmaları için test toplamlarıyla birlikte bir çalıştırmayı alın. | `account_handle`, `project_handle`, `run_id` |

Cargo derleme, Mix derleme ve Once çalıştırma kimlikleri bir proje içinde benzersizdir. Aynı okumalar HTTP API üzerinden `GET /api/projects/{account_handle}/{project_handle}/cargo/builds`, `.../mix/builds` ve `.../once/runs` adreslerinde mevcuttur; her biri tek bir kimlik için bir ayrıntı uç noktasına sahiptir.

#### Görevler, eylemler, modüller ve dosyalar

Bu proje kapsamındaki araçlar, çalıştırmalar arasında kalıcı derleme kimliklerini inceler. `list_build_entities` ile başlayın, ardından döndürülen kararlı `id` değerini aynı `kind` ile birlikte `get_build_entity` veya `list_build_entity_history` öğesine, `account_handle` ve `project_handle` ile birlikte iletin. Derleme veya çağrı tanımlayıcısı gerekmez.

| Araç | Açıklama | Gerekli parametreler |
| --- | --- | --- |
| `list_build_entities` | Bir projenin derlemeleri arasında görülen tek bir türdeki görevleri, modülleri, eylemleri veya dosyaları listeler. | `account_handle`, `project_handle`, `kind` |
| `get_build_entity` | Seçilen dönem için yerel kimliği ve analitikleriyle birlikte tek bir derleme varlığını alın. | `account_handle`, `project_handle`, `kind`, `id` |
| `list_build_entity_history` | Tek bir derleme varlığının kaydedilmiş yürütmelerini, derlemelerini veya önbellek olaylarını, en yeniden eskiye sıralayarak listeler. | `account_handle`, `project_handle`, `kind`, `id` |

| `kind` | Araç zinciri | Geçmiş listeleri |
| --- | --- | --- |
| `bazel_actions` | Bazel eylemleri | BEP tarafından bildirilen eylem yürütmeleri |
| `gradle_tasks` | Gradle görevleri | Görev yürütmeleri |
| `xcode_modules` | Xcode modülleri | Derlemeler ve modül önbelleği olayları |
| `once_actions` | Once eylemleri | Yürütmeler |
| `mix_files` | Mix ile derlenmiş dosyalar | Derlemeler |
| `mix_modules` | Mix ile derlenmiş modüller | Derlemeler |
| `cargo_crates` | Cargo paketleri | Kaydedilmiş rustc çağrıları |

Bu araçlar kademeli olarak kullanıma sunulmaktadır ve yalnızca etkinleştirildiği projeler için veri döndürür; diğer projeler için boş sonuç yerine bir hata döndürür. Bir tür, yalnızca ilgili derleme araç zincirini kullanan projeler için kullanılabilir. Araçlar sınırlı `start_at`/`end_at` filtrelerini, `environment` (`any`, `ci` veya `local`) ve tam eşleşen bir `branch` kabul eder. `list_build_entities` `q` parametresini kabul eder; `list_build_entity_history` şeffaf olmayan `after`/`before` imleçlerini destekler. Bilinmeyen zamanlama veya önbellek gözlemleri sıfır veya isabetsizlik olarak değerlendirilmez, bunun yerine kullanılamaz durumda kalır. Geçmiş, mevcut çalıştırma araçlarını kullanarak detaylı inceleme yapmak üzere kaydedilen üst öğeyi ve yerel yürütmeyi referans alır.

`get_build_entity` metrikleri, kaydedilmiş zamanlamaya sahip gözlem sayısını içeren `duration_samples` değerini barındırır: Gerçek sıfır süreler sayılır, eksik zamanlama sayılmaz. Bu sayı, gözlem sayısından daha düşük olabilir; kullanılamayan süre istatistikleri null olarak kalır.

Xcode modül süreleri, derleme günlüklerindeki ölçülen hedef derlemelerden gelir. Modül önbelleği çözümlemeleri ve derleme işi içermeyen hedefler süre örneklerine katkıda bulunmaz. Derleme gözlemleri Xcode derlemesini referans alır; önbellek olayları ise oluşturma veya önbellek komutunu referans alır.

Bazel eylemleri, hedef etiketi, anımsatıcı ve yapılandırılmış birincil çıktı ile tanımlanır; böylece girişe bağlı önbellek özetlerine güvenmeden ayrı eylemler ve yapılandırmalar birbirinden ayırt edilir. Geçmiş, BEP tarafından bildirilen yürütmeleri kaydeder, önbellek aramalarını veya iz profili aşamalarını değil. Tam yürütme kapsamı `--build_event_publish_all_actions` gerektirir; yapıt teslimi en iyi çaba esasına göre yapılır, bu nedenle eksik gözlemler hiçbir işin çalışmadığına dair kanıt değildir. Kararlı kimliği veya yürütme başlangıcı olmayan eski Kura yükleri kabul edilmeye devam eder ancak dizine eklenmez. Eksik bitiş zamanı ölçümleri kullanılamaz durumda kalır ve gerçek sıfır süreler sayılır.

Mix modül süreleri, bağımsız olarak ölçülen modül işini değil, içeren dosyanın derlenmesini ölçer. Once eylemleri, istemci hedef eşlemelerini bildirdiğinde bildirilen hedef/yetenek/dizin yuvalarını kullanır; tanılama etiketleri tek başına kararlı kimlikler değildir. Mevcut istemciler ve çalıştırma düzeyindeki araçlar değiştirilmeden desteklenmeye devam eder.

Cargo paketleri, tam olarak kaydedilen paket kökü, adı ve türüne göre gruplanır. Çekme yolu değişiklikleri geçmişleri bölebilir ve derleme profilleri, özellikler ile hedef üçlüleri ayırt edilmez. Geçmiş, dosya başına işi veya önbellek isabetlerini değil, rustc çağrılarını ölçer; eksik işler kaldırmaları veya eksiksiz bir çalışma alanı envanterini doğrulamaz.

Analitik okumaların bellek ve yürütme süresi sınırları vardır. Bir sorgu bu sınırları aşarsa, araç boş bir sonuç uydurmak yerine bir hata döndürür.

Yeni gözlemler dağıtımdan sonra indekslenir; bu özellik mevcut çalıştırma telemetrisini geriye dönük olarak doldurmaz. Kimlik meta verileri, <.localized_link href="/guides/server/data-retention">veri saklama politikası</.localized_link> kapsamında bireysel gözlemlerden daha uzun süre korunur.

#### Testler

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_test_runs` | Bir proje için test çalıştırmalarını, her biri kendi `selective_testing_strategy` ile birlikte listeler. `selective_testing` (`coverage`, kapsam tabanlı seçimin yedeklerini içerir, veya `module_hash`) ile filtreleyin. `query` alanları `git_branch`, `scheme`, `status` ve `selective_testing` şeklindedir: `field:"value"` tam eşleşme sağlar, `field~"value"` büyük/küçük harf duyarsız alt dize eşleşmesi sağlar (`selective_testing` üzerinde değil) ve başındaki `-` herhangi bir operatörü olumsuzlar. Örneğin, `-git_branch~"gh-readonly-queue"` birleştirme kuyruğu dallarını dışlar. Boşlukla ayrılmış sorgu filtreleri ve açık argümanlar AND mantığıyla birleştirilir. | `account_handle`, `project_handle` |
| `get_test_run` | Bir test çalıştırması için ayrıntılı metrikleri alın; buna kendi kod kapsamı (`coverage`: herhangi bir ölçüm yapıp yapmadığı, satırları ve figürü, kısmi olup olmadığı veya kirli bir checkout'tan çalışıp çalışmadığı), seçici test özeti (`selective_testing`: strateji, temel commit ve istenen, seçilen, atlanan ve tahmini test sayıları; test seçimi etkinliğinin hesaplandığı değerler) ve sonuç paketi (`.xcresult`) ile oturum arşivi için geçici indirme URL'leri dahildir. | `test_run_id` |
| `list_test_module_runs` | Belirli bir test çalıştırması için test modülü çalıştırmalarını listeler. | `test_run_id` |
| `list_test_suite_runs` | Belirli bir test çalıştırması için test paketi çalıştırmalarını, isteğe bağlı olarak modüle göre filtrelenmiş şekilde listeler. | `test_run_id` |
| `list_test_cases` | Bir proje için test senaryolarını listeler (`flaky` gibi filtreleri destekler). | `account_handle`, `project_handle` |
| `get_test_case` | Güvenilirlik oranı, kararsızlık oranı ve çalıştırma sayıları dahil olmak üzere bir test senaryosu için ayrıntılı metrikleri alın. | `test_case_id` veya `identifier` + `account_handle` + `project_handle` |
| `list_test_case_runs` | Test senaryosu çalıştırmalarını, isteğe bağlı olarak test senaryosuna veya test çalıştırmasına göre filtrelenmiş şekilde listeler. | `account_handle`, `project_handle` |
| `get_test_case_run` | Belirli bir test senaryosu çalıştırması için hata ayrıntılarını ve tekrarları alın ve çalıştırmanın kapsam tabanlı seçimi testi koruduğunda nedenini belirtin (`selective_testing`: karar, neden, eşleşen değişen dosya ve parça). | `test_case_run_id` |
| `list_test_case_run_attachments` | Bir test senaryosu çalıştırması için ekleri listeler. Her ek, geçici bir indirme URL'si içerir. | `test_case_run_id` |
| `list_test_case_events` | Bir test senaryosu için durum değişikliklerini, örneğin sessize alma veya atlama gibi işlemleri listeler. | `test_case_id` |
| `update_test_case` | Bir test senaryosunun durumunu veya kararsız sınıflandırmasını güncelleyin. Bir değişiklik, harici hizmetler dahil olmak üzere yapılandırılmış webhook uç noktalarına bir olay gönderebilir. | `test_case_id` veya `identifier` + `account_handle` + `project_handle` |
| `list_xcode_test_targets` | Bir test çalıştırması için seçici test hedef sonuçlarını listeler. | `test_run_id` |
| `list_selective_testing_tests` | Bir test çalıştırmasının kapsama tabanlı seçiminin karar verdiği, seçtiği ve atladığı testleri, her kararın nedeni, onu seçen değişen dosya, parçası ve çalıştırmadaki sonucuyla birlikte listeler. `decision`, `reason` veya `search` ile filtreleyin. | `test_run_id` |
| `list_selective_testing_changed_files` | Bir test çalıştırmasının kapsama tabanlı seçim temel çizgisinden bu yana değişen dosyaları, her birinin kaç testi seçtiğini ve değişikliğinin seçimin geri düşmesine neden olan izlenen bir dosya olup olmadığını göstererek listeler. | `test_run_id` |
| `get_coverage` | Bir projenin kod kapsamını hedefleriyle birlikte, bir commit'te veya bir dalın en son tamamlanan commit'inde alın. `git_commit_sha` veya `branch` olmadan, varsayılan dalı okur. | `account_handle`, `project_handle` |
| `list_coverage_files` | Bir commit'in kod kapsamının ölçtüğü dosyaları, satır kapsamlarıyla birlikte, bir commit'te veya bir dalın en son tamamlanan commit'inde listeler. `search`, sıralama ve sayfalama desteklenir. | `account_handle`, `project_handle` |
| `get_coverage_file` | Bir dosyanın kod kapsamını ve fonksiyonlarını, bir commit'te veya bir dalın en son tamamlanan commit'inde alın. Her satırın yürütme sayısını almak için `include_lines` ayarlayın. | `account_handle`, `project_handle`, `path` |
| `list_coverage_branches` | Kod kapsamı olan dalları, varsayılan dal ilk sırada olacak şekilde listeler. | `account_handle`, `project_handle` |
| `list_coverage_commits` | Bir dalın commit'lerini kapsam durumları (`complete`, `incomplete`, `in_progress`, `not_measured`), oranı ve önceki tamamlanan commit'e göre değişimiyle birlikte, en yeniden eskiye doğru listeler. Sayfalama imleçlerle yapılır. | `account_handle`, `project_handle` |
| `list_coverage_runs` | Bir commit veya dal arkasındaki kod kapsamına sahip test çalıştırmalarını, her biri `full`, `partial` veya `discarded` (kirli checkout) olarak işaretlenmiş şekilde listeler. Sayfalama imleçlerle yapılır. | `account_handle`, `project_handle` |
| `list_coverage_targets` | Bir commit'in hedef başına kapsamını, ardından çalıştırmalarının kapsam sayaçları olmadan ikili önbellekten aldığı hedefleri (`measured: false`) listeler. `search`, sıralama ve sayfalama desteklenir. | `account_handle`, `project_handle` |

Kod kapsamı araçları, kod kapsamı etkinleştirilmiş hesaplara sunulur.

#### Paketler

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_bundles` | Bir proje için paketleri (uygulama ikililerini) listeler. İsteğe bağlı olarak `git_branch` ve `tags` ile filtreleyin (tüm etiketler tam eşleşmelidir). | `account_handle`, `project_handle` |
| `get_bundle` | Özel etiketler dahil olmak üzere belirli bir paket hakkında ayrıntılı bilgi alın. | `bundle_id` |
| `get_bundle_artifact_tree` | Bir paketin tam yapıt ağacını, yola göre sıralanmış düz bir liste olarak alın. | `bundle_id` |

`list_bundles`, derleme çeşitlerini veya ortamları ayırt etmek için `tags: ["paid", "production"]` kabul eder. Etiketler, büyük/küçük harfe duyarlı, harf, rakam, tire veya alt çizgi içeren etiketlerdir; en fazla 10 etiket ve etiket başına 50 karakter olabilir. Liste ve ayrıntı sonuçları `custom_metadata.tags` içerir. Sayfalama sayıları ve dal filtreleri etiketli sonuçlara uygulanır; `tags` atlandığında filtrelensiz davranış korunur. Geçersiz etiket filtreleri sorguyu genişletmek yerine hata döndürür.

#### Nesiller

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_generations` | Bir proje için nesil çalıştırmalarını listeler. | `account_handle`, `project_handle` |
| `get_generation` | Belirli bir nesil çalıştırması hakkında ayrıntılı bilgi alın. | `generation_id` |

#### Önbellek çalıştırmaları

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_cache_runs` | Bir proje için önbellek çalıştırmalarını listeler. | `account_handle`, `project_handle` |
| `get_cache_run` | Belirli bir önbellek çalıştırması hakkında ayrıntılı bilgi alın. | `cache_run_id` |
| `list_xcode_module_cache_targets` | Bir nesil veya önbellek çalıştırması için modül önbelleği hedeflerini, hedef başına önbellek isabeti/isabetsizliği durumunu ve ek karma girişleri de içeren tanılama bileşeni karmalarını göstererek listeler. | `run_id` |

#### Önizlemeler

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_previews` | Bir proje için paylaşılabilir uygulama önizlemelerini listeler. | `account_handle`, `project_handle` |
| `get_preview` | Bir önizlemeyi ve derlemeleri için geçici indirme URL'lerini alın. | `preview_id` |
| `get_latest_preview` | Çalışan bir uygulama ikilisi için en son önizlemeyi bulun. | `account_handle`, `project_handle`, `binary_id`, `build_version` |

#### Otomasyonlar

| Araç | Açıklama | Gerekli parametreler |
|------|-------------|---------------------|
| `list_automation_alerts` | Bir proje için otomasyon uyarılarını listeler. | `account_handle`, `project_handle` |
| `get_automation_alert` | Bir otomasyon uyarısını alın. | `alert_id` |
| `list_automation_alert_revisions` | Bir otomasyon uyarısının revizyon geçmişini listeler. Eylem kimlik bilgileri gizlenmiştir. | `alert_id` |
| `list_project_notification_alerts` | Proje bildirim uyarısı kurallarını listeler. Kontrol paneli ayarları sayfasıyla aynı yönetici iznini gerektirir. Webhook adresleri gizlenmiştir. | `account_handle`, `project_handle` |

### Olaylar

Durumsuz `2026-07-28` Model Bağlam Protokolü yaşam döngüsünü kullanan istemciler, olayları ve yük şemalarını keşfetmek için `events/list` çağrısı yapabilir:

| Olay | Gönderilme zamanı | Abonelik filtresi |
|-------|-----------------|---------------------|
| `test_case.marked_flaky` | Bir test senaryosu kararsız olmayan durumdan kararsız duruma geçer. | `account_handle`, `project_handle` |
| `build.failed` | Yerel veya sürekli entegrasyon Xcode, Gradle ya da Bazel derlemesi bir hata ile sonlanır. | `account_handle`, `project_handle` |
| `test_run.failed` | Yerel veya sürekli entegrasyon test çalıştırması bir hata ile sonlanır; birleştirilmiş parçalı çalıştırma veya terk edilmiş çalıştırma dahildir. | `account_handle`, `project_handle` |
| `ci_job.failed` | Bir Tuist runner işi bir hata ile tamamlanır. | `account_handle` |

Abone olmak için istemci, olay adını, yukarıda listelenen tanıtıcıları `arguments` içinde ve bir `https://` geri çağırma URL’si ile bir `whsec_` imzalama gizli anahtarı içeren bir `webhook` teslimatıyla birlikte `events/subscribe` çağırır. Proje olayları hesap üyeliği ve ilgili test veya derleme verilerine okuma erişimi gerektirir; runner işi olayları hesap üyeliği ve runner okuma erişimi gerektirir. Talep edilmiş [`auth.md`](https://workos.com/auth-md) erişim belirteçleri, talep edilmiş hesap belirteçleri ve tarayıcı yetkilendirme izinleri abonelik oluşturabilir; ilişkili kimlik bilgisi artık etkin olmadığında teslimat durur. Her kullanıcı en fazla 25 aktif abonelik tutabilir. Tuist, aboneliği kaydetmeden önce geri çağırmaya bir doğrulama sorgusu gönderir. Geri çağırma, aynı `challenge` değerini içeren bir nesne döndürmelidir. Abonelik varsayılan olarak yedi gün sürer, tekrar abone olunarak yenilenebilir ve kullanıcının erişimi veya kimlik bilgisi kaldırıldığında teslimat durur. İsteğe bağlı `ttlMs` bir saat ile 30 gün arasında sınırlıdır. Tuist zaman aşımına uğramış bir geri çağırmayı yeniden dener ve beş dakikayı kapsayan en az üç ardışık zaman aşımından sonra aboneliği iptal eder; geri çağırmayı restore ettikten sonra tekrar abone olun.

Bir olay gerçekleştiğinde Tuist, kaynak tanımlayıcısını ve kontrol paneli URL’sini geri çağırmaya gönderir. Derleme ve test çalıştırması hataları ayrıca `is_ci` ve `git_branch` içerir, böylece istemciler yerel hataları yok sayabilir veya dala göre filtreleyebilir. Derleme olayları `build_system` içerir; runner işi olayları hem `workflow_job_id` hem de `workflow_run_id` içerir. İstek, istemcinin kaynağını doğrulayabilmesi için bir abonelik tanımlayıcısı ve [Standard Webhooks](https://www.standardwebhooks.com/) imza başlıkları içerir. Tuist başarısız teslimatları yeniden dener, bu nedenle istemciler yinelenenleri elemek için kararlı `eventId` kullanmalıdır. Yük, test adlarını, günlükleri ve hata mesajlarını içermez; istemci bu ayrıntıları yukarıdaki araçlarla alabilir ve bir ekibi bilgilendirmeye veya hata ayıklamaya başlamaya karar verebilir. İstemciler teslimatı `events/unsubscribe` ile durdurabilir.

### İstemler

| İstem | Açıklama |
|--------|-------------|
| `fix_flaky_test` | Hata kalıplarını analiz ederek, kök nedeni belirleyerek ve hedefe yönelik bir düzeltme uygulayarak kararsız bir testi düzeltmeniz konusunda size rehberlik eder. |
| `compare_builds` | Performans gerilemelerini, önbellek değişikliklerini ve derleme sorunlarını belirlemek için derlemeleri karşılaştırmanız konusunda size rehberlik eder. Xcode, Gradle, Bazel ve Cargo projeleri için yerel araçları kullanır. Cargo karşılaştırmaları kısmi derleyici kapsamını korur ve tahmini derleyici işini geçen süreden tasarruf edilen miktardan ayırır. |
| `compare_test_runs` | Gerilemeleri, yeni hataları ve kararsız testleri belirlemek için iki test çalıştırmasını karşılaştırmanız konusunda size rehberlik eder. |
| `compare_bundles` | Yapıt ağacı genelinde boyut değişikliklerini belirlemek için iki paketi karşılaştırmanız konusunda size rehberlik eder. |
| `compare_test_case` | Bir test senaryosunun davranışını iki dal veya zaman dilimi arasında karşılaştırmanız konusunda size rehberlik eder. |
| `compare_generations` | Performans gerilemelerini ve modül önbelleği değişikliklerini belirlemek için iki nesil çalıştırmasını karşılaştırmanız konusunda size rehberlik eder. |
| `compare_cache_runs` | Önbellek etkinliği değişikliklerini ve hedef düzeyindeki gerilemeleri belirlemek için iki önbellek çalıştırmasını karşılaştırmanız konusunda size rehberlik eder. |
| `integrate_gradle_project` | Tuist’i mevcut bir Gradle projesine entegre etmeniz konusunda size rehberlik eder. Ayrı araç ve Gradle kimlik doğrulaması, hesap keşfi, proje oluşturma, uzak önbellek politikası, derleme içgörileri ve geri okuma doğrulamasını içerir. |
| `integrate_bazel_project` | Bir Bazel projesi oluşturmanız veya seçmeniz, komut satırını kimlik doğrulamanız, uzak önbelleği ve derleme içgörilerini yapılandırmanız ve entegrasyonu Tuist derleme verileri aracılığıyla doğrulamanız konusunda size rehberlik eder. |
| `integrate_xcode_project` | Tuist’i mevcut bir Xcode projesine entegre etmeniz konusunda size rehberlik eder. Xcode önbelleğini, derleme içgörilerini, test içgörilerini ve test parçalama özelliğini destekler. |
| `ask_tuist` | Bağlam için genel materyalleri kullanarak ve mevcut davranış için gerçek kaynak olarak odaklanmış uygulama ve test kanıtlarını kullanarak bir Tuist sorusunu yanıtlar. Bir `question` gerektirir ve revizyon sabitli kanıtlara atıfta bulunur. |

Proje verisi istemleri, araştırmayı belirli bir projeyle sınırlamak için `account_handle` ve `project_handle` kabul eder. Karşılaştırma istemleri ayrıca karşılaştırılacak iki öğeyi (ID, kontrol paneli URL’si veya dal adına göre) belirtmek için `base` ve `head` bağımsız değişkenlerini kabul eder. `ask_tuist`, proje parametreleri yerine bir `question` kabul eder. `integrate_gradle_project` ayrıca uygulanacak Gradle entegrasyonlarının virgülle ayrılmış bir listesini olan `features` kabul eder: `remote_cache`, `build_insights`, `test_insights`, `flaky_tests` ve `test_sharding`. `integrate_bazel_project`, kendi kendine barındırılan veya yerel kurulumlar için isteğe bağlı bir `server_url` kabul eder. `integrate_xcode_project`, `xcode_cache`, `build_insights`, `test_insights` ve `test_sharding` ile `features` kabul eder.

#### Gradle entegrasyonu istemi özellikleri

`integrate_gradle_project` istemi ve `get_gradle_integration_guide` aracı, eksiksiz kurulum iş akışını belgeler. Araç ayrıca sunucunun başlatma talimatlarında referans gösterilir; bu da istemleri numaralandırmayan ajanlar tarafından keşfedilmesini sağlar.

| Özellik | Ajanın yapılandırdığı şey |
|---------|---------------------------|
| `remote_cache` | Gradle’ın derleme önbelleğini etkinleştirir, Tuist uzak önbellek yükleme politikasını yapılandırır ve yalnızca yerel salt okunur kullanıma sahip sürekli entegrasyon runner’larından yüklemeleri önerir. |
| `build_insights` | Tuist Gradle eklentisini uygular ve gerektiğinde derleme analitiği yükleme davranışını yapılandırır. |
| `test_insights` | Gradle `Test` görev sonuçlarının otomatik olarak yüklenmesi için Tuist Gradle eklentisini uygular. |
| `flaky_tests` | Kararsız test algılama kurulumu, isteğe bağlı Gradle Test Retry eklentisi kullanımı ve test karantina yapılandırması konusunda rehberlik eder. |
| `test_sharding` | `tuistPrepareTestShards` için sürekli entegrasyon iş akışını, parça matrisi oluşturmayı ve `TUIST_SHARD_INDEX` tabanlı test yürütmeyi ekler. |

`features` atlandığında, istem ajandan kullanıcının hangi entegrasyonları istediğini netleştirmesini veya Gradle projesini düzenlemeden önce istekten en küçük yararlı seti çıkarmasını ister.

#### Xcode entegrasyonu istemi özellikleri

`integrate_xcode_project` istemi, Tuist’in desteklediği her Xcode entegrasyonunu belgeler:

| Özellik | Ajanın yapılandırdığı şey |
|---------|---------------------------|
| `xcode_cache` | `tuist setup cache`, oluşturulan proje önbellek ayarlarını, manuel Xcode önbelleği derleme ayarlarını ve yalnızca sürekli entegrasyon runner’larıyla sınırlı bir yükleme politikasını yapılandırır. |
| `build_insights` | `tuist inspect build`, `tuist xcodebuild`, `-resultBundlePath` ve isteğe bağlı makine metriklerini `tuist setup insights` aracılığıyla yapılandırır. |
| `test_insights` | `tuist inspect test`, şema test son eylemlerini ve sürekli entegrasyon test çalıştırmaları için sonuç paketi oluşturmayı yapılandırır. |
| `test_sharding` | Xcode veya oluşturulan proje parça planlamasını ve `TUIST_SHARD_INDEX` ile parça yürütme iş akışını ekler. |

`features` atlandığında, istem ajandan kullanıcının hangi entegrasyonları istediğini netleştirmesini veya Xcode projesini düzenlemeden önce istekten en küçük yararlı seti çıkarmasını ister.
