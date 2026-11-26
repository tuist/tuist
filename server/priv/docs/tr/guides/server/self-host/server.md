---
{
  "title": "Sunucu",
  "titleTemplate": ":title | Kendi Altyapınızda Barındırma | Sunucu | Kılavuzlar | Tuist",
  "description": "Tuist sunucusunu kendi altyapınıza nasıl dağıtacağınızı öğrenin."
}
---
# Sunucu {#server}

Altyapıları üzerinde daha fazla kontrol gerektiren kuruluşlar için Tuist sunucusunun kendi kendine barındırılan bir sürümünü sunuyoruz. Bu sürüm, Tuist'i kendi altyapınızda barındırmanıza olanak tanır ve verilerinizin güvenli ve özel kalmasını sağlar.

> [!WARNING]
> **Lisans gerekli**
>
> Tuist'i kendi kendine barındırmak için yasal olarak geçerli ücretli bir lisans gerekir. Tuist'in şirket içi sürümü yalnızca Enterprise planındaki kuruluşlar için kullanılabilir. Bu sürümle ilgileniyorsanız lütfen [contact@tuist.dev](mailto:contact@tuist.dev) adresiyle iletişime geçin.

> [!WARNING]
> **Eski önbellek hizmeti**
>
> Eski kendi kendine barındırılan önbellek düğümü teknolojisi yeni kurulumlar için kullanımdan kaldırılmıştır. Güncel kendi kendine barındırılan önbellek altyapısı için <.localized_link href="/guides/features/cache/self-hosting">kendi kendine barındırılan önbellek kılavuzunu</.localized_link> kullanın.
>
> Mevcut dağıtımlar, GitHub'ın Markdown görüntüleyicisindeki eski kaynak belgelerine hâlâ başvurabilir: [önbellek düğümleri](https://github.com/tuist/tuist/blob/main/server/priv/docs/en/guides/cache/self-host.md) ve [önbellek mimarisi](https://github.com/tuist/tuist/blob/main/server/priv/docs/en/guides/cache/architecture.md).

## Yayın sıklığı {#release-cadence}

Tuist sunucusu ve Kura önbellek sunucusu üç GHCR görüntü kanalı üzerinden sunulur: **canary** (`main` ana dalına yapılan her commit), **aday sürüm** (her Pazartesi kesilir, bir hafta bekletilir) ve **kararlı** (bir sonraki Pazartesi terfi edilir). Yalnızca kararlı sürümler `:latest` etiketini ilerletir ve varsayılan olarak çözülür; canary ve aday sürümler, etiketlerini sabitleyerek opt-in yaptığınız GitHub ön sürümleridir. Sunucu ve Kura aynı haftalık döngüyü takip eder ve <.localized_link href="/cli/release/channels">Tuist CLI'nin yayın takvimi</.localized_link> ile eş zamanlı hareket eder.

Öngörülebilir sürümleme ve uyumluluk sağlamak için [anlamsal sürümlemeyi](https://semver.org/) izliyoruz. Ana bileşen, Tuist sunucusunda kendi kendine barındırma kullanıcılarıyla koordinasyon gerektirecek kırıcı değişiklikleri işaretlemek için kullanılır; bunu kullanmamızı beklememelisiniz ve gerekirse geçişi sorunsuz hale getirmek için sizinle birlikte çalışacağımızdan emin olabilirsiniz.

Her kanalın nasıl kesildiğini, dağıtımınızda birini nasıl sabitleyeceğinizi ve üretim ortamını yavaş ilerleyen kararlı bir hatta tutarken hazırlama ortamının yaklaşan sürümü bekletmesi için önerilen stratejiyi görmek için <.localized_link href="/guides/server/self-host/release/channels">Yayın kanalları</.localized_link> sayfasına bakın.

## Tarayıcı oturumu yükseltmesi {#browser-session-upgrade}

Tarayıcı oturumları, kimliği doğrulanmış sayfa istekleri veya LiveView etkileşimi olmadan yedi gün sonra ve kimlik doğrulamadan en geç 30 gün sonra sona erer. Beni hatırla seçeneği aynı sunucu tarafı oturumunu geri yükler ve herhangi bir süreyi uzatamaz. Etkinlik dakikada bir kaydedilir, bu nedenle boşta kalan bir oturum en fazla 59 saniye daha erken sona erebilir. WebSocket kalp atışları, otomatik yeniden bağlanmalar ve arka plan güncellemeleri etkinliği yenilemez. Bu süre sınırları makine kimlik bilgilerini veya API belirteci ömürlerini değiştirmez.

Güncellenmiş uygulama işlemlerini başlatmadan önce eklemeli `users_tokens` geçişini çalıştırın. Mevcut satırlar geriye dönük olarak doldurulmaz: oluşturulma zamanları hareketsizliği ve mutlak sona ermeyi sınırlar ve SSO zorunlu kılınan bir kuruluşa erişmeden önce yeniden kimlik doğrulaması yapmaları gerekir. Geri çağrının sağlayıcısı, yayıncı veya doğrulanmış Çalışma Alanı ve özel SSO bağlantısı sunucu tarafında saklanır ve kuruluşun mevcut ayarlarıyla karşılaştırılır. Bağlı bir hesap, oturum kimlik doğrulama kanıtı değildir.

İlkeyi uygulanmış olarak kabul etmeden önce hizmet veren her web çoğaltmasını yükseltin. Daha eski ikililer hâlâ eski 60 günlük oturumlarını kabul edebilir ve yeni LiveView sınırını uygulamaz; karışık sürümler şema açısından uyumludur ancak ilke açısından eşdeğer değildir. Kullanıcıların tekrar oturum açmasını bekleyin. Daha eski ikililere geri dönüş bu kontrolleri zayıflatır; şema geri dönüşü gerekiyorsa, yeni alanları okuyan tüm ikilileri bunları kaldırmadan önce durdurun. Yeniden kimlik doğrulamayı önlemek için eski oturumları asla uzatmayın veya köken çıkarmayın.

## Kimlik doğrulayıcı uygulaması MFA {#authenticator-app-mfa}

Sunucu, yerel kimlik doğrulayıcı uygulaması (TOTP) iki faktörlü kimlik doğrulamayı içerir. Kontrol panelinde henüz buna bağlantı yoktur; sonraki bir sürüm ayarlar giriş noktasını ekleyecektir. Aktivasyon bayrağı, barındırılan hizmet bağımlılığı veya kimlik sağlayıcı kimlik bilgileri gerektirmez: yalnızca PostgreSQL, aşağıdaki geçiş, bir TOTP kimlik doğrulayıcı ve tüm hizmet veren çoğaltmalar tarafından paylaşılan kararlı bir şifreleme anahtarı (`TUIST_SECRET_KEY_ENCRYPTION`, yedek olarak `TUIST_SECRET_KEY_BASE` kullanılır). Sunucu ve kimlik doğrulayıcı saatlerini senkronize tutun. MFA doğrulaması ve beş dakikada beş başarısız kodluk ortak bütçesi Redis yerine PostgreSQL satır kilitlerini kullanır.

Kurulum, son beş dakika içinde bir oturum açmayı, kurulum anahtarını bir TOTP kimlik doğrulayıcı uygulamasına girmeyi ve uygulama tarafından oluşturulan bir kodu onaylamayı gerektirir. On adet tek kullanımlık kurtarma kodu bir kez gösterilir; bunları güvenli bir şekilde saklayın. Faktörü devre dışı bırakmak da yakın zamanda bir oturum açmayı ve kullanılmamış bir kimlik doğrulayıcı veya kurtarma kodunu gerektirir. Faktör değişiklikleri diğer tarayıcı oturumlarını iptal eder. Parola sıfırlamaları MFA'yı kaldırmaz ve bu uygulama, kaybedilen bir faktör için yalnızca e-posta tabanlı veya yönetici bypass'ı sağlamaz.

Kayıt olduktan sonra, federatif oturum açma dahil olmak üzere her yeni tarayıcı oturum açması, bir oturum almadan veya tarayıcı tabanlı CLI/cihaz yetkilendirmesini tamamlamadan önce yerel ikinci faktörü gerektirir. Doğrudan parola ve Apple API girişi, kayıtlı kullanıcıları reddeder ve tarayıcı oturum açmasını kullanmalarını talimat verir. Kayıtlı kullanıcılar için yeni e-posta aracısı talepleri MFA doğrulamalı bir tarayıcı oturumu gerektirir; yalnızca posta kutusuna dayalı eski talepler reddedilir. Mevcut API belirteçleri, makine kimlik bilgileri, iş yükü kimlikleri ve bunların yenileme kuralları değişmez. Bu, kullanıcı başına isteğe bağlı destek olup, kuruluş çapında bir MFA zorunluluğu veya bir kimlik sağlayıcının kendi MFA politikasının doğrulanması değildir. Kuruluş SSO'su, yerel faktöre ek olarak doğru yapılandırılmış sağlayıcı/yayıncıyı hâlâ gerektirir.

Kayıt, oturum açma, kurtarma kodu kullanımı veya MFA'yı devre dışı bırakma için e-posta gerekli değildir. Faktör değişikliği bildirimleri mümkün olan en iyi şekilde gönderilir; teslimat hatası tamamlanmış bir değişikliği geri almaz.

Yeni ikili dosyadan önce ayrı eklemeli `user_mfa`/`users_tokens.mfa_verified_at` geçişini çalıştırın. TOTP gizli anahtarı mevcut Vault şifreleme anahtarını kullanır; bu anahtarı ve yedeklerini koruyun. MFA kaydına izin vermeden önce **tüm kimlik doğrulama sunan kopyaların yükseltmesini tamamlayın**. Eski ikili dosyalar yerel MFA'yı atlayabilir, bu nedenle kayıt olduktan sonra politika uyumlu bir geri alma hedefi değildirler. MFA şemasının silinmesi kayıt ve kurtarma durumunu yok eder; önce okuyucuları durdurun ve şifrelenmiş bir yedeği saklayın. Karışık sürüm şema uyumluluğu, MFA veya tarayıcı oturum kontrollerinin uygulandığına dair kanıt değildir.

## OAuth yükseltme ve geri alma sınırı {#oauth-upgrade-and-rollback-boundary}

OAuth varlık önbelleğinin kaldırılması, mevcut kurulumlar için aşamalı bir yükseltme gerektirir. OAuth önbellek geçersiz kılmalarını durduran bir sürümü dağıtmadan önce, yetkili okuma uyumluluk sürümünü [#14040](https://github.com/tuist/tuist/pull/14040) üzerinden **tüm OAuth okuyucu ve yazıcılara** dağıtın. Bu uyumluluk aşaması ilk olarak **1.355** sürüm serisinde görünür: `ghcr.io/tuist/tuist:1.355.0-rc.1` bunu içerir; üretim dağıtımları, tanıtıldıktan sonra kararlı bir `1.355.x` sürümü kullanmalıdır. 1.354 veya daha önceki sürümlerdeki kurulumlar, kaldırmayı içeren daha sonraki bir sürüme yükseltmeden önce bu aşamayı tamamlamalıdır. 1.355 serisini yalnızca uyumluluk için tutun: geçersiz kılma kaldırmayı bu seriye geri taşımayın.

Orijinal uyumluluk commit'i ayrıca `ghcr.io/tuist/tuist:sha-c8e54471a425` olarak mevcuttur. Başka bir imaj, eski tüketiciler mevcutken yetkili okumaları koruduğu **ve eski geçersiz kılmaları sakladığı** sürece uyumluluk aşaması olarak uygundur. Trafik sunmadan önce, yenileme belirteci arama indeksini de dahil olmak üzere o aşamanın normal veritabanı geçişlerini çalıştırın.

Her ortamda tüm web kopyalarını, arka plan çalışanlarını, zamanlanmış işleri ve ayrı sabitlenmiş işlemci imajlarını kontrol edin. Geçersiz kılmaları kaldırmadan önce uyumluluk yayılımının bitmesini bekleyin ve önbellek okuyan hiçbir ikili dosyanın kalmadığını doğrulayın. Otomatik bir yükseltme sırasında kayan bir imaj etiketinin bu aşamayı atlamasına izin vermeyin. Eski tüketicisi olmayan yeni kurulumlar ara bir dağıtıma ihtiyaç duymaz.

> [!WARNING]
> **Yetkili okuma geri alma hedefini koruyun**
>
> Geçersiz kılmalar kaldırıldıktan sonra, olağan bir kademeli geri alma #14040 veya başka bir yetkili okuma sürümünü hedeflemelidir. Saklanan OAuth önbellek girdileri, geçersiz kılma yapmayan her süreç durduktan sonra bile eskimiş olabilir ve yeniden başlatılan bir önbellek okuyan kopya bunları eşlerden içe aktarabilir.
>
> Daha fazla geri alma, geçersiz kılma yapmayan **tüm** OAuth tüketicilerini durdurup boşaltmayı, ardından herhangi bir önbellek okuyan tüketiciyi başlatmadan önce saklanan **her** Boruta önbellek katılımcısını temizlemeyi veya değiştirmeyi gerektirir. Saklanan katılımcıların yeniden katılmasını engelleyin. Yalnızca girişi boşaltmak veya yalnızca web kopyalarını yeniden başlatmak yetersizdir; önbellekleri otomatik olarak temizlemek veya veritabanı geçişlerini geri almak yerine, bu kurtarmayı Tuist destek kişinizle koordine edin.

## Çoklu kopya kümeleme {#multi-replica-clustering}

Desteklenen çoklu kopya web dağıtımları, kimlik doğrulama otoritesi olarak değil, kopyalar arası Phoenix PubSub ve Oban PG bildirimleri için Erlang kümelemesi gerektirir. Grafik, `server.cluster.enabled` false olduğunda, bir kopyadan fazlasına büyüyebilen bir otomatik ölçeklendirici dahil olmak üzere birden fazla kopyayı reddeder. Daha önce kabul edilen kümelenmemiş dağıtımlar, korumayı atlamak yerine bu yükseltmeyi planlamalıdır. Üyeliği değiştirmeden önce, geçersiz kılma kaldırması da dahil olmak üzere <.localized_link href="/guides/server/self-host/server#oauth-upgrade-and-rollback-boundary">OAuth yükseltme sırasını</.localized_link> tamamlayın.

Gizli yöneticiniz kullanarak release namespace'inde özel bir çerez Secret'ı oluşturun, ardından adını ve anahtarını yapılandırın:

```yaml
server:
  replicaCount: 2
  cluster:
    enabled: true
    distributionPort: 9100
    cookieExistingSecret: tuist-server-cluster
    cookieExistingSecretKey: release-cookie
```

Çerez yüksek entropili olmalı ve katılan tüm web kopyaları tarafından paylaşılmalıdır. Yayınlanan bir imaja gömülü çerezi asla kullanmayın: bir dağıtım çerezine sahip olmak, düğümlerinde uzaktan yürütme izni verir. Dağıtılmış release başlatma artık eksik bir özel `RELEASE_COOKIE` veya geçersiz bir portu, DNS keşfi olmadan açıkça yapılandırılmış `RELEASE_DISTRIBUTION=name` veya `sname` dahil olmak üzere reddeder. Grafik dışı dağıtımlar ayrıca `TUIST_CLUSTER_DNS_SERVICE`, `TUIST_CLUSTER_APP_NAME` ve pod IP/düğüm adını tutarlı bir şekilde yapılandırmalıdır. Keşif şu anda IPv4 A kayıtlarını kullanır.

Normal sunucu bağlantılı `helm upgrade` ile, `cookieExistingSecret` boş bırakıldığında bir çerez Secret'ı oluşturulur ve sonraki yükseltmelerde mevcut değeri yeniden kullanılır. Çevrimdışı `helm template`, Argo CD ve canlı Secret araması olmayan diğer GitOps renderlayıcılar oluşturulan bu değeri koruyamaz; ayrı yönetilen, kararlı bir Secret ile desteklenen `cookieExistingSecret` kullanmaları gerekir. Canlı bir kümeyi örtük olarak döndürmek için çerez anahtarını değiştirmeyin. Çerez döndürme, her katılımcının koordineli bir geçiş/yeniden başlatmasını gerektirir; yalnızca bir Secret'ı güncellemek mevcut işlemleri güncellemez.

İmaj tabanlı çerezlerden ilk yayılım, tüm web kopyaları özel Secret'ı kullanana kadar ayrı eski/yeni üyelik adacıkları oluşturur. Gerçek zamanlı güncellemeler için bir geçiş penceresi planlayın. Sonraki kademeli dağıtımlar karışık sürüm kümeleri oluşturur, bu nedenle PubSub, Oban bildirimlerini ve eş değiştirmeyi gerçek eski/yeni sürümler arasında nitelendirin. Bu bildirimler dayanıklı teslimat garantileri değildir. Uyumlu bir sürümü geri alırken yetkili okuma geri alma imajını koruyun ve aynı özel çerezi saklayın.

EPMD'ye (TCP 4369) ve yapılandırılmış dağıtım portuna yalnızca güvenilir sunucu eşleri arasında izin verin, kiracı iş yüklerinden veya genel ağdan asla izin vermeyin. Ortamınızda gerçek giriş/çıkış izolasyonunu doğrulayın; bir NetworkPolicy renderlamak uygulamayı veya arka uç erişilebilirliğini kanıtlamaz. Sürekli yük altında iki kopyalı bir canary, terfi edilmeden önce katılma, kademeli değiştirme ve hata/kurtarma testlerinden geçmelidir. DNS, eşleri keşfetmek için kullanılır, geçici bir başarısız veya kısmi yanıtta sağlıklı düğümlerin bağlantısını kesmek için değil; gerçek düğüm kaybı ve OTP bölüm önleme hala geçerlidir. libcluster, bağlantıyı kapatmadan kalıcılık geri çağrısı için başarılı bir "bağlantı kesildi" işlemini yine de günlüğe kaydedebilir; gerçek üyeliği yalnızca bu günlük satırından değil, düğüm yukarı/aşağı olaylarından veya `Node.list()` üzerinden belirleyin.

## Sürekli dağıtım {#continuous-deployment}

Üretim ortamını kararlı bir alt sürüm hattında sabit tutmanızı öneririz (örneğin `ghcr.io/tuist/tuist:1.351`), böylece günlük yükseltmeler yalnızca geriye aktarılan düzeltmeleri içerir. Kararlı hatlar, sürüm adayı kanalında bir hafta boyunca bekletildikten sonra her Pazartesi saat 06:00 UTC'de yayına alınır; canary veya mevcut sürüm adayı etiketindeki bir hazırlık ortamı, regresyonları kullanıcılarınıza ulaşmadan önce yakalar. Önerilen sabitleme stratejisi için <.localized_link href="/guides/server/self-host/release/channels">Sürüm kanalları</.localized_link> bölümüne bakın.

Manifest dosyalarınıza dokunmadan yeni özellikleri kararlı hale geldikçe benimsemeyi tercih ediyorsanız, `:latest` etiketini sabitleyin. Etiket her Pazartesi sabahı bir kez güncellenir, bu nedenle dağıtım pencerenizi buna göre planlayın. İşte bu tempoda en son kararlı imajı kontrol eden ve dağıtan örnek bir GitHub Actions iş akışı:

```yaml
name: Update Tuist Server
on:
  schedule:
    - cron: '0 8 * * 1' # Mondays 08:00 UTC, after the weekly stable promote
  workflow_dispatch: # Allow manual runs

jobs:
  update:
    runs-on: ubuntu-latest
    steps:
      - name: Check and deploy latest version
        run: |
          # Your deployment commands here
          # Example: docker pull ghcr.io/tuist/tuist:latest
          # Deploy to your infrastructure
```

<span id="network-trusted-report-publishing"></span>
<span id="network-trusted-cache-access"></span>

## Ağ güvenilen erişim {#network-trusted-access}

Kendi sunucunuzda barındırılan kurulumlar, güvenilir bir ağdaki geliştiricilerin oturum açmadan içgörüler göndermesine, önbelleği kullanmasına veya her ikisini yapmasına olanak tanır. Kontrol paneli ve yönetim işlemleri yine de kimlik doğrulama gerektirir.

Yalnızca ihtiyacınız olan yetenekleri etkinleştirin:

| Sunucu ortam değişkeni | Oturum açmadan izin verir |
| --- | --- |
| `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS=true` | Derleme ve test içgörülerini gönder |
| `TUIST_NETWORK_TRUSTED_CACHE_ACCESS=true` | Önbelleğe alınmış derleme çıktılarını oku ve yaz |

Her iki ayar da varsayılan olarak **kapalıdır**, bağımsızdır ve özel projeler dahil olmak üzere tüm hesaplar ve projeler genelinde örnek bazında uygulanır. Barındırılan Tuist'te kullanılamazlar ve kendi kendine barındırma lisansının yerine geçmezler.

Eski `TUIST_NETWORK_TRUSTED_REPORT_PUBLISHING` adı, `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS` ayarlanmadığında uyumluluk yedeği olarak kalır.

> [!WARNING]
> Bu ayarları yalnızca zorunlu ofis ağı veya VPN sınırı arkasında etkinleştirin. Etkin bir uç noktaya erişebilen herkes rapor gönderebilir veya önbellek erişimi etkinse önbelleğe alınmış çıktıları okuyup üzerine yazabilir. Bu durum sahte telemetriye, önbellek zehirlenmesine ve kapasite tükenmesine izin verir. Raporlama yanıtları ayrıca özel proje tanıtıcılarını ve derleme sistemlerini ortaya çıkarabilir. Tuist, VPN üyeliğini doğrulamaz veya iletilen IP başlıklarını üyelik kanıtı olarak güvenmez.

### Örneği yapılandır {#network-trusted-instance-configuration}

1. Tuist sunucusunu, her Kura HTTP/gRPC dinleyicisini ve herhangi bir Bazel BES girişini güvenlik duvarı veya özel giriş kullanarak güvenilir ağınızla sınırlayın.
2. İstemcileri yükseltmeden önce her sunucu ve Kura kopyasını yükseltin. Kura kimlik doğrulamasını `KURA_AUTH_TUIST_URL` ve kontrol düzlemi kimlik bilgileriyle etkin tutun; bunu devre dışı bırakmak bu kısıtlamaları atlar. Önbellek uç noktanızı <.localized_link href="/guides/features/cache/self-hosting">kendi kendine barındırılan önbellek kılavuzu</.localized_link>nu kullanarak yapılandırın.
3. Yukarıdaki istenen değişkenleri ilgili her Tuist sunucu kopyasında ayarlayın, ardından bunları yeniden başlatın veya yeniden dağıtın. Yalnızca tam olarak `true` değeri bir ayarı etkinleştirir. Kontrol panelinde bir geçiş anahtarı veya ayrı bir Kura bayrağı yoktur.

### İstemcileri yapılandır {#network-trusted-client-configuration}

Uyumlu her istemcide nihai kendi kendine barındırılan sunucu URL'sini ve projeyi yapılandırın. İstemciler, kimlik bilgileri olmadığında hangi yeteneklerin etkin olduğunu otomatik olarak keşfeder; istemci tarafında ek bir onay gerekmez. Keşif işlemi yönlendirmeleri takip etmez. Mevcut kimlik bilgileri kullanılmaya devam eder ve geçersiz veya yenilemesi başarısız olan kimlik bilgileri anonim geri dönüş yerine hata oluşturur. Kurtarmak için tekrar oturum açın veya açıkça oturumu kapatın.

İçgörü erişimini etkinleştirmeden önce, kimlik bilgilerini paylaşan tüm araçları bozuk veya reddedilen kimlik bilgilerini koruyan, okunamayan kimlik bilgisi dizinlerini reddeden ve imzalanmamış raporlardan Git kökenlerini çıkaran sürümlere yükseltin. Daha eski araçlar kimlik bilgilerini silebilir ve istemeden anonim geri düşüşe izin verebilir; yalnızca sunucu tarafında yapılan bir yükseltme bunu çözemez. Sunucuda keşif desteği yoksa veya daha eski bir sürüme geri alınırsa, istemcilerin kimlik doğrulaması yapması gerekir. Eski `TUIST_NETWORK_TRUSTED_PUBLISHING` istemci ayarı artık geçerli değildir.

- **İçgörüler:** Yalnızca tamamlanmış Xcode, Gradle, Elixir/Mix ve Bazel raporlarını gönderin; arşiv, ek, kapsam, parça planlama veya mevcut rapor erişimi olmadan. Aktör iddiaları doğrulanmamıştır; imzalanmamış telemetri güvenilir test kanıtlarını veya otomasyonu yönlendirmez. İstemci kurulumu ve gizlilik detayları için <.localized_link href="/guides/features/build-insights/xcode#network-trusted-publishing">Xcode</.localized_link>, <.localized_link href="/guides/features/build-insights/gradle#network-trusted-publishing">Gradle</.localized_link> ve <.localized_link href="/guides/features/build-insights/elixir#network-trusted-publishing">Elixir</.localized_link> kılavuzlarına bakın.
- **Önbellek:** Desteklenen CLI derleme/modül önbelleğe alma, Bazel önbelleğe alma ve Gradle görev önbelleğe alma. Önbellek temizleme ve Uzak Varlık indirmeleri hala kimlik bilgisi gerektirir. Desteği olmayan istemciler kimlik doğrulamaya devam etmelidir.
- **Bazel:** Raporlama, açık bir `TUIST_BAZEL_BES_BACKEND` ve uyumlu Kura gerektirir. Önbellek ve raporlama seçenekleri bağımsız olarak etkinleştirilir. Kimlik bilgilerini veya herhangi bir ayarı değiştirdikten sonra `tuist bazel setup` komutunu yeniden çalıştırın; derleme önbelleği yapılandırma değişiklikleri için `tuist cache config` komutunu yeniden çalıştırın.

Rapor istekleri proje başına 8 MB, dakikada 60 istek ve günde 10.000 istekle sınırlıdır. Birden fazla kopya ile dağıtım genelinde kota yönetimi için paylaşılan Valkey'i yapılandırın; aksi takdirde limitler süreç başına uygulanır. Yapılandırılmış paylaşılan kota arka ucu kullanılamıyorsa, imzalanmamış raporlama reddedilir. Giriş bağlantısı, gövde ve hız limitlerini de ekleyin.

### Ağ güvenilen erişimi devre dışı bırak {#disable-network-trusted-publishing}

İlgili değişkeni `false` olarak ayarlayın, ardından **ilgili tüm sunucu kopyalarını** yeniden başlatın. Eski kopyalar, değiştirilene kadar kimlik bilgisi gerektirmeyen istekleri kabul etmeye devam edebilir. Son kopya geçiş yaptıktan sonraki 60 saniye içinde yeni istekler için önbellek erişimi durur; devam eden aktarımlar iptal edilmez. Acil iptal gerekiyorsa trafiği önce giriş noktasında engelleyin. Mevcut raporlar normal görünürlüklerini ve saklama sürelerini korur ve kimliği doğrulanmış istemciler çalışmaya devam eder.

## Çalışma zamanı gereksinimleri {#runtime-requirements}

Bu bölüm, Tuist sunucusunu altyapınızda barındırmak için gereken gereksinimleri özetlemektedir.

### Uyumluluk matrisi {#compatibility-matrix}

Tuist sunucusu test edilmiş ve aşağıdaki minimum sürümlerle uyumludur:

| Bileşen | Minimum Sürüm | Notlar |
| --- | --- | --- |
| PostgreSQL | 15 | |
| ClickHouse | {{minimum_supported_clickhouse_version}} | Analitikler için gereklidir |

### Docker sanallaştırılmış imajları çalıştırma {#running-dockervirtualized-images}

Sunucuyu [Docker](https://www.docker.com/) imajı olarak [GitHub’ın Konteyner Kaydı](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry) üzerinden dağıtıyoruz.

Çalıştırmak için altyapınızın Docker imajlarını çalıştırması gerekir. Çoğu altyapı sağlayıcısının bunu desteklediğini unutmayın, çünkü üretim ortamlarında yazılım dağıtmak ve çalıştırmak için standart konteyner haline gelmiştir.

### Postgres veritabanı {#postgres-database}

Docker imajlarını çalıştırmaya ek olarak, ilişkisel verileri depolamak için bir [Postgres veritabanına](https://www.postgresql.org/) ihtiyacınız olacaktır. Çoğu altyapı sağlayıcısı tekliflerine Postgres veritabanlarını dahil eder (örneğin, [AWS](https://aws.amazon.com/rds/postgresql/) ve [Google Cloud](https://cloud.google.com/sql/docs/postgres)).

> [!NOTE]
> **Migrasyonlar**
>
> Docker imajının giriş noktası, hizmeti başlatmadan önce bekleyen tüm şema migrasyonlarını otomatik olarak çalıştırır.


### ClickHouse veritabanı {#clickhouse-database}

Tuist, büyük miktarda analitik veriyi depolamak ve sorgulamak için [ClickHouse](https://clickhouse.com/) kullanır. ClickHouse, derleme içgörileri gibi özellikler için **gereklidir**. ClickHouse'u kendi sunucunuzda barındırmayı veya onların barındırılan hizmetini kullanmayı seçebilirsiniz.

> [!NOTE]
> **Migrasyonlar**
>
> Docker imajının giriş noktası, hizmeti başlatmadan önce bekleyen tüm ClickHouse şema migrasyonlarını otomatik olarak çalıştırır.

Birlikte verilen Docker Compose ve Helm gömülü ClickHouse yapılandırmaları, ClickHouse metin günlük düzeyini imajın `trace` varsayılanından `information` değerine düşürür; `system.text_log` hacminin çoğu buradan gelir. İkisi de aksi takdirde sınırsız olan ClickHouse'un kendi `system.*` operasyonel günlük tablolarını da sınırlayabilir, ancak bu varsayılan olarak kapalıdır - aşağıya bakın. Harici ClickHouse dağıtımları bu operasyonel günlükleri doğrudan ClickHouse hizmetlerinde yapılandırmalıdır.

#### ClickHouse çoğaltma topolojisi {#clickhouse-replication-topology}

Tuist arkasındaki çok kopyalı ClickHouse yalnızca ClickHouse Cloud üzerinde desteklenir. Kendi kendine yönetilen ClickHouse tek kopyalıdır.

Alım migrasyonları düz bir `MergeTree` motoru oluşturur. Cloud üzerinde bu şeffaf bir şekilde `SharedMergeTree` haline gelir, böylece yazılar paylaşılan nesne depolama alanına gider ve herhangi bir kopya sayısı çalışır. Kendi kendine yönetilen ClickHouse'ta `MergeTree` yalnızca bir kopyadaki yerel diske yazar; çok kopyalı bir kurulum ya alımı kopyalar arasında sessizce böler ya da CREATE işlemini `UNKNOWN_STORAGE: Only tables with a Replicated engine or tables which do not store data on disk are allowed in a Replicated database.` ile reddeder; bu, bağlanan kullanıcıda `database_replicated_allow_only_replicated_engine` ayarının nasıl yapıldığına bağlıdır.

Kendi kendine yönetilen ClickHouse'ta bir kopya ile tek bir parça çalıştırın ve ClickHouse veri dizininin düzenli yedeklerini alın. Düğüm kaybolursa geri dönülecek ikinci bir kopya yoktur.

#### Operasyonel günlük saklama süresini sınırlama {#capping-operational-log-retention}

Saklama süresi `system.text_log`, `system.query_log`, `system.query_thread_log`, `system.query_views_log`, `system.trace_log`, `system.metric_log`, `system.asynchronous_metric_log` ve `system.part_log` için uygulanabilir.

Bunu açmak, zaten verisi olan bir örnekte tek seferlik, tek yönlü bir adımdır; bu nedenle hiçbir paket bunu sizin için yapmaz. Herhangi bir saklama penceresi, bu tablo tanımlarının yapılandırmalarıyla eşleşmeyi durdurmasına neden olur, bu nedenle ClickHouse her birini yeniden adlandırır ve [kullanımdan kaldırılmış günlük tabloları](#superseded-log-tables) altında açıklandığı gibi yeni bir tablo başlatır. Geride bırakılan nesil, o ana kadar biriken her şeyi tutar ve kendi saklama süresi yoktur, bu nedenle aynı adımda geri almazsanız kalıcı olarak diskte kalır ve yeni pencere yalnızca o andan itibaren yazılan satırları sınırlar. İkisini birlikte etkinleştirin:

```yaml
clickhouse:
  embedded:
    systemLogs:
      ttlDays: 14
      supersededTables: delete
```

Bu tek `helm upgrade` kendi kendine yeterlidir, çünkü `ttlDays` değerini boştan ayarlanmışa taşımak tak-çalıştır bağlantısını ekler ve ClickHouse pod'unu döndürür: yeniden başlar, tabloları kullanımdan kaldırır ve yükseltme sonrası Job bunları siler. Pod Job çalışmadan önce döndürülsün diye `helm upgrade --wait` ile dağıtın; aksi takdirde nesiller Job baktıktan sonra görünür ve bir sonraki `helm upgrade` bunları bunun yerine geri alır.

Docker Compose ile, `docker-compose.yml` içindeki `clickhouse` hizmetindeki `clickhouse-log-ttl.xml` birimini yorumdan çıkarın ve `.env` içinde her iki değişkeni de ayarlayın:

```bash
CLICKHOUSE_SYSTEM_LOG_TTL_DAYS=14
CLICKHOUSE_SUPERSEDED_LOG_TABLES=delete
```

Alan geri alındıktan sonra, daha sonraki bir ClickHouse yükseltmesinin geçmişi kendi başına atmaması için `supersededTables`/`CLICKHOUSE_SUPERSEDED_LOG_TABLES` değerini tekrar `ignore` olarak ayarlayabilirsiniz.

#### Kullanımdan kaldırılmış günlük tabloları {#superseded-log-tables}

ClickHouse, başlangıçta her sistem günlük tablosunun yapılandırmasıyla hala eşleşip eşleşmediğini kontrol eder. Eşleşmediğinde, mevcut tabloyu `system.<name>_0`, ardından `_1`, `_2` ve benzeri şekilde yeniden adlandırır ve yeni bir tane başlatır. Bu, saklama penceresini değiştirdiğinizde ve bir sistem günlük şemasını değiştiren herhangi bir ClickHouse yükseltmesinde gerçekleşir.

Bir tabloyu yeniden adlandırmak verilerini kopyalamaz, bu nedenle ek disk tüketmez. Kullanımdan kaldırılan tabloya sonrasında ne olacağı, geldiği tabloya bağlıdır, çünkü kullanımdan kaldırıldığı anda canlı tablonun sahip olduğu saklama süresini korur. Saklamayı ilk kez etkinleştirdiğinizde, kullanımdan kaldırılan tablonun saklama süresi yoktur, bu nedenle o ana kadar biriken tüm geçmişi tutar ve süresiz olarak saklar. Pencerede yapılan daha sonraki bir değişiklik, zaten bir TTL taşıyan bir tabloyu kullanımdan kaldırır, bu nedenle bunlar kendi kendilerinin süresi dolar ve geride boş bir tablo bırakır. ClickHouse tabloları asla silmez, bu nedenle uzun ömürlü bir örnekte her iki durumda da birikirler.

Kullanımdan kaldırılan tablolar varsayılan olarak tutulur, böylece bir yükseltme operasyonel geçmişi asla kendi başına atmaz. Bunları bunun yerine silmek için politikayı `delete` olarak ayarlayın; bu, `docker compose up` ve her `helm upgrade` sırasında gerçekleşir:

```bash
CLICKHOUSE_SUPERSEDED_LOG_TABLES=delete
```

Helm grafiğiyle, aynı politikayı bir değer olarak yapılandırın:

```yaml
clickhouse:
  embedded:
    systemLogs:
      supersededTables: delete
```

Kullanımdan kaldırılmış bir tabloyu silmek disk alanını geri kazandırır. Canlı tabloya asla dokunulmaz ve kullanımdan kaldırılmasından bu yana yazılan satırlara da dokunulmaz.

Politikayı değiştirmeden alanı bir kez geri kazanmak için tabloları manuel olarak silin:

```sql
SELECT name FROM system.tables WHERE database = 'system' AND match(name, '_log_[0-9]+$');
DROP TABLE IF EXISTS system.text_log_0 SYNC;
```

`system` veritabanı, düz bir `DROP TABLE` işlemini `database_atomic_delay_before_drop_table_sec` (varsayılan olarak sekiz dakika) kadar erteleyen `Atomic` motorunu kullanır. `SYNC` verileri hemen kaldırır; disk dolu olduğu için bunları silerken istediğiniz budur.


### Depolama {#storage}

Dosyaları depolamak için de bir çözüme ihtiyacınız olacaktır (örneğin, çerçeve ve kütüphane ikili dosyaları). Tuist sunucusu, sunucu tarafından sahip olunan yapıtlar için S3 uyumlu depolamayı ve Azure Blob Storage'ı destekler.

> [!TIP]
> **Optimize edilmiş önbellekleme**
>
> Amacınız öncelikli olarak önbellek gecikmesini azaltmaksa, tüm sunucuyu kendi kendinize barındırmanız gerekmeyebilir. Kendi kendine barındırılan Kura düğümlerini CI veya geliştirici ağınıza yakın konuşlandırabilir ve bunları barındırılan Tuist sunucusuna veya kendi kendine barındırılan sunucunuza bağlayabilirsiniz.
>
> <.localized_link href="/guides/cache/self-host">kendi kendine barındırılan önbellek kılavuzuna</.localized_link> bakın.


### Kendi kendine barındırılan Kura düğümleri {#self-hosted-cache-nodes}

Kendi kendine barındırılan bir Tuist sunucusuyla kendi kendine barındırılan Kura düğümlerini kullanmak için:

1. Tuist sunucusunda `KURA_CONTROL_PLANE_CLIENT_ID` ve `KURA_CONTROL_PLANE_CLIENT_SECRET` yapılandırın. İstemci kimliği **bir UUID olmalıdır**. UUID ve rastgele bir gizli anahtarı <.localized_link href="/guides/cache/self-host#control-plane-client">kendi kendine barındırılan önbellek kılavuzundaki</.localized_link> komutları kullanarak oluşturun ve dağıtım gizli anahtarlarınızda saklayın.
2. Aynı kontrol düzlemi kimlik bilgilerini kullanarak <.localized_link href="/guides/cache/self-host">kendi kendine barındırılan önbellek kılavuzunu</.localized_link> takip ederek Kura düğümlerini dağıtın.
3. Her Kura düğümünü `KURA_REGISTRATION_URL` ve `KURA_ADVERTISED_HTTP_URL` ile yapılandırın. Kayıt kalp atışları, sunucuya CLI'ye duyurabileceği hazır, istemciye yönelik Kura uç noktalarını bildirir.

## Yapılandırma {#configuration}

Hizmetin yapılandırması, çalışma zamanında ortam değişkenleri aracılığıyla yapılır. Bu değişkenlerin hassas doğası göz önüne alındığında, bunları şifrelemenizi ve güvenli parola yönetimi çözümlerinde saklamanızı öneririz. Tuist'in bu değişkenleri son derece dikkatle ele aldığını ve asla günlüklerde görüntülenmediklerini bilerek içiniz rahat olsun.

> [!NOTE]
> **Başlatma kontrolleri**
>
> Gerekli değişkenler başlangıçta doğrulanır. Herhangi biri eksikse, başlatma başarısız olur ve hata mesajı eksik değişkenleri ayrıntılı olarak belirtir.


### Lisans yapılandırması {#license-configuration}

Şirket içi bir kullanıcı olarak, bir ortam değişkeni olarak ayarlamanız gereken bir lisans alırsınız. Lisans, dağıtımı doğrulamak ve hizmetin sözleşme koşulları çerçevesinde çalıştığını sağlamak için kullanılır.

| Ortam değişkeni | Açıklama | Zorunlu | Varsayılan | Örnek |
| --- | --- | --- | --- | --- |
| `TUIST_LICENSE` | Hizmet düzeyi sözleşmesinin imzalanmasından sonra sağlanan lisans. Sunucunun harici hizmetlerle iletişim kuramadığı, izole ortamlarda kullanılan standart lisans anahtarını veya base64 kodlu sertifikayı kabul eder. | Evet | | `******` |

> [!WARNING]
> **Son kullanma tarihi**
>
> Lisansların bir son kullanma tarihi vardır. Lisansın 30 günden daha kısa bir sürede sona ermesi durumunda, kullanıcılar sunucuyla etkileşime giren Tuist komutlarını kullanırken bir uyarı alır. Lisansınızı yenilemek istiyorsanız lütfen [contact@tuist.dev](mailto:contact@tuist.dev) adresine ulaşın.


### Temel ortam yapılandırması {#base-environment-configuration}

| Ortam değişkeni | Açıklama | Zorunlu | Varsayılan | Örnek |
| --- | --- | --- | --- | --- |
| `TUIST_APP_URL` | Örneğe İnternet üzerinden erişmek için temel URL | Evet | | https://tuist.dev |
| `TUIST_SECRET_KEY_BASE` | Bilgileri (örneğin, bir çerezdeki oturumları) şifrelemek için kullanılacak anahtar | Evet | | `c5786d9f869239cbddeca645575349a570ffebb332b64400c37256e1c9cb7ec831345d03dc0188edd129d09580d8cbf3ceaf17768e2048c037d9c31da5dcacfa` |
| `TUIST_SECRET_KEY_PASSWORD` | Hashlenmiş parolalar oluşturmak için kullanılan tuz (pepper) | Hayır | `$TUIST_SECRET_KEY_BASE` | |
| `TUIST_SECRET_KEY_TOKENS` | Rastgele belirteçler oluşturmak için gizli anahtar | Hayır | `$TUIST_SECRET_KEY_BASE` | |
| `TUIST_SECRET_KEY_TOKENS_PREVIOUS` | Daha önceki `TUIST_SECRET_KEY_TOKENS`, döndürme öncesinde verilen belirteçleri hala doğrular. Süreleri dolduğunda (30 gün) kaldırın. | Hayır | | |
| `TUIST_SECRET_KEY_ENCRYPTION` | Hassas verilerin AES-GCM ile şifrelenmesi için anahtar. 32 bayttan uzun değerler ilk 32 bayta kesilir; `TUIST_SECRET_KEY_ENCRYPTION_KEYS` tercih edin. | Hayır | `$TUIST_SECRET_KEY_BASE` | |
| `TUIST_SECRET_KEY_ENCRYPTION_KEYS` | Virgülle ayrılmış `id:base64` şifreleme anahtarları, her biri 32 bayt (`openssl rand -base64 32`). İlk anahtar yeni verileri şifreler; diğerleri ve `TUIST_SECRET_KEY_ENCRYPTION` (kimlik `V1`) mevcut verilerin şifresini çözmeye devam eder. Mevcut verileri geçerli anahtara taşımak için `bin/tuist eval 'Tuist.Release.reencrypt_vault("<id>")'` kullanın. | Hayır | | `k2:3q2+7w...` |
| `TUIST_SECRET_KEY_ENCRYPTION_CURRENT_KEY` | Yeni verileri şifreleyen anahtarın kimliği, `TUIST_SECRET_KEY_ENCRYPTION_KEYS` içindeki ilk anahtar olmaması gerektiğinde | Hayır | | `V1` |
| `TUIST_USE_IPV6` | `1` olduğunda uygulamayı IPv6 adreslerini kullanacak şekilde yapılandırır | Hayır | `0` | `1`|
| `TUIST_LOG_LEVEL` | Uygulama için kullanılacak günlük seviyesi | Hayır | `info` | [Günlük seviyeleri](https://hexdocs.pm/logger/1.12.3/Logger.html#module-levels) |
| `TUIST_GITHUB_APP_NAME` | GitHub uygulamanızın slug'ı, `https://github.com/apps/<slug>` adresinden alınır. Uygulamayı yüklemek için gereklidir. Bkz. <.localized_link href="/guides/server/self-host/server#platform-github">GitHub</.localized_link> | Hayır | | `my-app` |
| `TUIST_GITHUB_APP_PRIVATE_KEY_BASE64` | GitHub uygulamasının otomatik PR yorumları gönderme gibi ek işlevlerin kilidini açmak için kullandığı base64 kodlu özel anahtar | Hayır | `LS0tLS1CRUdJTiBSU0EgUFJJVkFUR...` | |
| `TUIST_GITHUB_APP_PRIVATE_KEY` | GitHub uygulamasının otomatik PR yorumları gönderme gibi ek işlevlerin kilidini açmak için kullandığı özel anahtar. **Özel karakterlerle ilgili sorunları önlemek için base64 kodlu sürümü kullanmanızı öneririz** | Hayır | `-----BEGIN RSA...` | |
| `TUIST_OPERATOR_EMAIL_DOMAIN` | E-posta adresi `@<this-domain>` ile biten ve bu adresin kontrolünü kanıtlayan kullanıcılar, işlem URL'lerine (`/ops/*`) erişebilir. Ayarlanmadığında kimse bunlara erişemez. Bkz. [İşlemler](#operations) | Hayır | | `example.com` |
| `TUIST_SERVER_VERSION_IDENTIFIER` | Sunucu örneğini tanımlamak amacıyla gösterge paneli gezinme çubuğunda rozet olarak görüntülenen bir etiket (örneğin, bir sürüm numarası veya dal adı) | Hayır | Geliştirme ortamındaki Git dalı | `v1.2.3` |
| `TUIST_WEB` | Web sunucusu uç noktasını etkinleştir | Hayır | `1` | `1` veya `0` |
| `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS` | Oturum açmadan derleme ve test içgörülerinin gönderilmesine izin ver. Kurulum ve güvenlik gereksinimleri için bkz. [Ağ güvenilir erişim](#network-trusted-access). | Hayır | `false` | `true` |
| `TUIST_NETWORK_TRUSTED_CACHE_ACCESS` | Oturum açmadan önbellek okuma ve yazma işlemlerine izin ver. Kurulum ve güvenlik gereksinimleri için bkz. [Ağ güvenilir erişim](#network-trusted-access). | Hayır | `false` | `true` |
| `TUIST_OTEL_EXPORTER_OTLP_ENDPOINT` | İzleri göndermek için bir OpenTelemetry Collector'ın gRPC uç noktası | Hayır | | `http://localhost:4317` |
| `TUIST_LOKI_URL` | Günlükleri göndermek için Loki uyumlu bir uç noktanın temel URL'si (örneğin, Grafana Alloy veya Loki) | Hayır | | `http://localhost:3100` |

> [!WARNING]
> **Uygulamayı HTTPS üzerinden sunun**
>
> Oturum çerezleri `Secure` olarak işaretlenir, bu nedenle tarayıcılar düz `http://` üzerinden bunları reddeder ve kullanıcılar oturum açamaz. TLS'yi sunucunun önünde sonlandırın (dahili CA'nızdan alınan sertifikaya sahip bir ters proxy yeterlidir) ve dahili veya yalnızca VPN bağlantılı dağıtımlar için bile `TUIST_APP_URL` değerini `https://` URL'sine ayarlayın.

#### Ters proxy arkasındaki istemci adresleri {#client-addresses-behind-a-reverse-proxy}

Sunucu, istemci adresine göre oturum açma ve API hız sınırlarını anahtarlar ve istekleri günlüğe kaydeder. Bir ters proxy arkasında bu adresi `X-Forwarded-For` üzerinden okur ve yalnızca özel bir ağdaki (RFC 1918, operatör düzeyi NAT, döngü, bağlantı yerel veya IPv6 benzersiz yerel adresler) bir proxy'nin yazdıklarına inanır: başlıktaki en sağdaki genel adresi alır, böylece bir istemci başlığı göndererek kendi adresini seçemez. `203.0.113.7:51234` gibi bir bağlantı noktası içeren girdiler de okunur.

Proxy sunucuya genel bir adresten bağlanıyorsa, sunucu başlığı yoksayar ve her istek proxy'den geliyormuş gibi sayılır, bu nedenle tüm istemciler tek bir hız sınırı bütçesini paylaşır. İstemci başına sınırları korumak için proxy'yi sunucuya özel bir ağ üzerinden bağlayın. Daha önceki sürümler, herhangi bir bağlantıdan en soldaki `X-Forwarded-For` girdisini alırdı.

### Veritabanı yapılandırması {#database-configuration}

Veritabanı bağlantısını yapılandırmak için aşağıdaki ortam değişkenleri kullanılır:

| Ortam değişkeni | Açıklama | Zorunlu | Varsayılan | Örnek |
| --- | --- | --- | --- | --- |
| `DATABASE_URL` | Postgres veritabanına erişmek için URL. URL'nin kimlik doğrulama bilgilerini içermesi gerektiğini unutmayın | Evet | | `postgres://username:password@cloud.us-east-2.aws.test.com/production` |
| `TUIST_DATABASE_SCHEMA` | Tuist'in uygulama tabloları tarafından kullanılan PostgreSQL şeması. Veritabanı politikanız `public` şemasının kullanılmasına izin vermiyorsa bunu ayarlayın. Şema adı, tırnaksız bir PostgreSQL tanımlayıcısı olmalıdır. | Hayır | `public` | `tuist` |
| `TUIST_MIGRATION_DATABASE_URL` | Yalnızca `Tuist.Release.migrate` tarafından kullanılan isteğe bağlı Postgres URL'si. `DATABASE_URL` daha kısıtlı bir çalışma zamanı rolüne işaret ettiğinde bunu bir sahip rolü URL'sine ayarlayın. | Hayır | `DATABASE_URL` | `postgres://owner:password@cloud.us-east-2.aws.test.com/production` |
| `TUIST_DATABASE_RUNTIME_ROLE` | Taşımalar tamamlandıktan sonra uygulama tablosu ayrıcalıklarının verilmesi gereken çalışma zamanı Postgres rolü. Web sunucusunun şema sahibi olarak bağlanmaması gerektiğinde bunu `TUIST_MIGRATION_DATABASE_URL` ile kullanın. | Hayır | | `tuist_web` |
| `TUIST_CLICKHOUSE_URL` | ClickHouse veritabanına erişmek için URL. URL'nin kimlik doğrulama bilgilerini içermesi gerektiğini unutmayın | Hayır | | `http://username:password@cloud.us-east-2.aws.test.com/production` |
| `TUIST_USE_SSL_FOR_DATABASE` | Doğru olduğunda, veritabanına bağlanmak için [SSL](https://en.wikipedia.org/wiki/Transport_Layer_Security) kullanır. `TUIST_DATABASE_SSL_VERIFY` etkinleştirilmedikçe sunucu sertifikası doğrulanmaz | Hayır | `1` | `1` |
| `TUIST_DATABASE_SSL_VERIFY` | Doğru olduğunda, veritabanı sunucu sertifikasının güvenilir bir CA'ya zincirlenmesi ve `DATABASE_URL` ana bilgisayar adıyla eşleşmesi gerekir. `TUIST_USE_SSL_FOR_DATABASE` gerektirir. Etkinleştirmenizi öneririz | Hayır | `0` | `1` |
| `TUIST_DATABASE_SSL_CA_CERT_FILE` | Veritabanı sunucusunu doğrulamak için kullanılan CA sertifikalarını içeren bir PEM dosyasının yolu. Ayarlanmadığında, işletim sisteminin güven deposu kullanılır | Hayır | | `/etc/tuist/rds-global-bundle.pem` |
| `TUIST_DATABASE_POOL_SIZE` | Bağlantı havuzunda açık tutulacak bağlantı sayısı | Hayır | `10` | `10` |
| `TUIST_DATABASE_QUEUE_TARGET` | Havuzdan alınan tüm bağlantıların kuyruk aralığını aşıp aşmadığını kontrol etme aralığı (milisaniye cinsinden) [(Daha fazla bilgi)](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config) | Hayır | `300` | `300` |
| `TUIST_DATABASE_QUEUE_INTERVAL` | Havuzun yeni bağlantıları bırakmaya başlayıp başlamayacağını belirlemek için kullandığı kuyruktaki eşik süresi (milisaniye cinsinden) [(Daha fazla bilgi)](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config) | Hayır | `1000` | `1000` |
| `TUIST_CLICKHOUSE_FLUSH_INTERVAL_MS` | ClickHouse arabellek temizlemeleri arasındaki milisaniye cinsinden zaman aralığı | Hayır | `5000` | `5000` |
| `TUIST_CLICKHOUSE_MAX_BUFFER_SIZE` | Zorlamalı temizleme öncesi maksimum ClickHouse arabellek boyutu (bayt cinsinden) | Hayır | `1000000` | `1000000` |
| `TUIST_CLICKHOUSE_BUFFER_POOL_SIZE` | Çalıştırılacak ClickHouse arabellek işlemi sayısı | Hayır | `5` | `5` |

Varsayılan olarak Tuist, veritabanı bağlantısını şifreler ancak sunucu sertifikasını doğrulamaz, bu nedenle ağ yolundaki bir saldırgan veritabanı taklidi yapabilir. Doğrulamak için `TUIST_DATABASE_SSL_VERIFY=1` ayarlayın. Sağlayıcınız Amazon RDS ve Google Cloud SQL'in yaptığı gibi kendi CA'sı ile sertifika imzaluyorsa, CA paketini indirin, konteynere bağlayın ve `TUIST_DATABASE_SSL_CA_CERT_FILE` değerini buna yönlendirin. `DATABASE_URL` içindeki ana bilgisayar adı, sertifikadaki bir ad veya IP adresiyle eşleşmelidir. Doğrulama etkinleştirildiğinde, bu kontrolleri geçemeyen bir sertifika her veritabanı bağlantısının başarısız olmasına neden olur; bu nedenle etkinleştirdikten sonra sunucu günlüklerinde `Bad Certificate` veya `Unknown CA` hatalarını kontrol edin.

`TUIST_DATABASE_SCHEMA`, `public` olmadığında, sürüm taşımaları Ecto taşıma zincirini çalıştırmadan önce şema yoksa oluşturur. Taşıma rolü şema oluşturamıyorsa, şemayı önceden oluşturun ve taşıma rolünü bunun sahibi yapın.

Tuist, oturum `search_path` değerini ayarlayarak bağlantıyı özel şemaya yönlendirir. Bazı havuzlu veya proxy'li Postgres kurulumları (örneğin PgBouncer veya başlatma parametrelerini kısıtlayan yönetilen veritabanları) bunu uygulamaz ve oturum `public` değerine geri döner; bu durum taşımalar sırasında `permission denied for schema public` olarak ortaya çıkar. Böyle bir kurulum üzerinden bağlanırken, proxy'den bağımsız olarak her oturumun bu şemada başlamasını sağlamak için şemayı doğrudan rol üzerinde sabitleyin:

```sql
CREATE SCHEMA IF NOT EXISTS tuist AUTHORIZATION <migration_role>;
ALTER ROLE <migration_role> IN DATABASE <database> SET search_path = tuist;
-- If the web server connects as a separate runtime role (TUIST_DATABASE_RUNTIME_ROLE):
ALTER ROLE <runtime_role> IN DATABASE <database> SET search_path = tuist;
```

### Kimlik doğrulama ortamı yapılandırması {#authentication-environment-configuration}

Kimlik doğrulamayı [kimlik sağlayıcılar (IdP)](https://en.wikipedia.org/wiki/Identity_provider) aracılığıyla kolaylaştırıyoruz. Bunu kullanmak için seçilen sağlayıcıya yönelik tüm gerekli ortam değişkenlerinin sunucu ortamında bulunduğundan emin olun. **Eksik değişkenler**, Tuist'in o sağlayıcıyı atlamasına neden olur.

#### E-posta ve parola {#email-and-password}

E-posta ve parola ile oturum açma ve kendi kendine kayıt varsayılan olarak dahili olarak gelir ve etkindir. Bir kimlik sağlayıcı zorunlu kılmak istediğiniz bir örnekte (örneğin, SSO uygularken) bunları tamamen kapatabilirsiniz. Bu, oturum açma deneyiminden e-posta/parola formunu, kayıt bağlantısını ve parola sıfırlama akışını kaldırır ve CLI'nin kullandığı e-posta/parola uç noktası (`tuist auth`) dahil olmak üzere ilgili tüm sunucu tarafı uç noktalarını kapatır.

| Ortam değişkeni | Açıklama | Zorunlu | Varsayılan | Örnek |
| --- | --- | --- | --- | --- |
| `TUIST_EMAIL_AUTH_ENABLED` | E-posta ve parolanın oturum açmak ve kaydolmak için kullanılıp kullanılamayacağı. E-posta/parola formunu, kayıt bağlantısını ve parola sıfırlama akışını oturum açma sayfasından kaldırmak ve ilgili sunucu tarafı uç noktalarını kapatmak için `0` olarak ayarlayın | Hayır | `1` | `0` |

#### Yapılandırılmış bir kimlik sağlayıcının devre dışı bırakılması {#disabling-a-configured-identity-provider}

Varsayılan olarak, bir sağlayıcı yapılandırıldığında oturum açma seçeneği olarak görünür. Bir sağlayıcıyı yapılandırılmış halde tutarken (kimlik bilgileri ayarlı kalır) oturum açma ve kayıt sayfalarından kaldırmak için ilgili anahtarı `0` olarak ayarlayın. GitHub, Google ve Apple için bu aynı zamanda oturum açma geri çağrısını da kapatır, böylece yöntem uçtan uca kullanılamaz hale gelir.

| Ortam değişkeni | Açıklama | Zorunlu | Varsayılan | Örnek |
| --- | --- | --- | --- | --- |
| `TUIST_GITHUB_AUTH_ENABLED` | GitHub'ın oturum açmak için kullanılıp kullanılamayacağı (Uygulamanın kimlik bilgilerini neden oturum açma ile paylaştığını öğrenmek için [GitHub](#github) bölümüne bakın) | Hayır | `1` | `0` |
| `TUIST_GOOGLE_AUTH_ENABLED` | Google'ın oturum açmak için kullanılıp kullanılamayacağı | Hayır | `1` | `0` |
| `TUIST_OKTA_AUTH_ENABLED` | Yapılandırılmış Okta sağlayıcısının bir oturum açma seçeneği olarak görünüp görünmediği | Hayır | `1` | `0` |
| `TUIST_APPLE_AUTH_ENABLED` | Apple'ın oturum açmak için kullanılıp kullanılamayacağı | Hayır | `1` | `0` |

#### GitHub {#github}

Kimlik doğrulama için bir [GitHub Uygulaması](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps) kullanmanızı öneririz ancak [OAuth Uygulaması](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/creating-an-oauth-app)nı da kullanabilirsiniz. Sunucu ortamında GitHub tarafından belirtilen tüm temel ortam değişkenlerinin bulunduğundan emin olun. Eksik değişkenler Tuist'in GitHub kimlik doğrulamasını gözden kaçırmasına neden olur. GitHub uygulamasını doğru şekilde ayarlamak için:
- GitHub uygulamasının genel ayarlarında:
    - `Client ID` öğesini kopyalayın ve `TUIST_GITHUB_APP_CLIENT_ID` olarak ayarlayın
    - Yeni bir `client secret` oluşturun, kopyalayın ve `TUIST_GITHUB_APP_CLIENT_SECRET` olarak ayarlayın
    - `Callback URL` değerini `http://YOUR_APP_URL/users/auth/github/callback` olarak ayarlayın. `YOUR_APP_URL` sunucunuzun IP adresi de olabilir.
- Aşağıdaki izinler gereklidir:
  - Depolar:
    - Çekme istekleri: Okuma ve yazma
  - Hesaplar:
    - E-posta adresleri: Salt okunur

`Permissions and events` bölümünün `Account permissions` kısmında, `Email addresses` iznini `Read-only` olarak ayarlayın.

Ardından, Tuist sunucusunun çalıştığı ortamda aşağıdaki ortam değişkenlerini açığa çıkarmanız gerekir:

| Ortam değişkeni | Açıklama | Zorunlu | Varsayılan | Örnek |
| --- | --- | --- | --- | --- |
| `TUIST_GITHUB_APP_CLIENT_ID` | GitHub uygulamasının istemci kimliği | Evet | | `Iv1.a629723000043722` |
| `TUIST_GITHUB_APP_CLIENT_SECRET` | Uygulamanın istemci gizli anahtarı | Evet | | `232f972951033b89799b0fd24566a04d83f44ccc` |
| `TUIST_GITHUB_AUTH_ENABLED` | GitHub'ın oturum açmak için kullanılıp kullanılamayacağı. Platform entegrasyonları (PR yorumları vb.) için yapılandırdığınız GitHub Uygulaması, istemci kimlik bilgilerini oturum açma ile paylaşır, bu nedenle aksi takdirde bir oturum açma seçeneği olarak görünür. Uygulamayı korurken GitHub'ı oturum açma sayfasından kaldırmak için `0` olarak ayarlayın. | Hayır | `1` | `0` |

#### Google {#google}

[OAuth 2](https://developers.google.com/identity/protocols/oauth2) kullanarak Google ile kimlik doğrulamayı ayarlayabilirsiniz. Bunun için OAuth istemci kimliği türünde yeni bir kimlik bilgisi oluşturmanız gerekir. Kimlik bilgilerini oluştururken uygulama türü olarak "Web Uygulaması"nı seçin, adını `Tuist` olarak belirleyin ve yönlendirme URI'sini `{base_url}/users/auth/google/callback` olarak ayarlayın; burada `base_url` barındırılan hizmetinizin çalıştığı URL'dir. Uygulamayı oluşturduktan sonra istemci kimliğini ve gizli anahtarını kopyalayın ve bunları sırasıyla `GOOGLE_CLIENT_ID` ve `GOOGLE_CLIENT_SECRET` ortam değişkenleri olarak ayarlayın.

> [!NOTE]
> **Onay ekranı kapsamları**
>
> Bir onay ekranı oluşturmanız gerekebilir. Bunu yaparken `userinfo.email` ve `openid` kapsamlarını eklediğinizden ve uygulamayı dahili olarak işaretlediğinizden emin olun.


#### Okta {#okta}

[OAuth 2.0](https://oauth.net/2/) protokolü aracılığıyla Okta ile kimlik doğrulamayı etkinleştirebilirsiniz. Okta'da [bir uygulama oluşturmanız](https://developer.okta.com/docs/en/guides/implement-oauth-for-okta/main/#create-an-oauth-2-0-app-in-okta) ve <.localized_link href="/guides/integrations/authentication/sso#okta">bu talimatları</.localized_link> izlemeniz gerekir.

Okta uygulamasının kurulumu sırasında istemci kimliğini ve gizli anahtarını elde ettikten sonra aşağıdaki ortam değişkenlerini ayarlamanız gerekir:

| Ortam değişkeni | Açıklama | Zorunlu | Varsayılan | Örnek |
| --- | --- | --- | --- | --- |
| `TUIST_OKTA_1_CLIENT_ID` | Okta'ya karşı kimlik doğrulaması yapmak için kullanılan istemci kimliği. Numara, kuruluş kimliğiniz olmalıdır. | Evet | | |
| `TUIST_OKTA_1_CLIENT_SECRET` | Okta'ya karşı kimlik doğrulaması yapmak için kullanılan istemci gizli anahtarı. | Evet | | |

`1` numarası, kuruluş kimliğinizle değiştirilmelidir. Bu genellikle 1 olur, ancak veritabanınızı kontrol edin.

### Depolama ortamı yapılandırması {#storage-environment-configuration}

 Tuist, API üzerinden yüklenen yapıtları barındırmak için depolamaya ihtiyaç duyar. Tuist'in etkili bir şekilde çalışması için desteklenen depolama çözümlerinden birini yapılandırmak **zorunludur**.

Sunucu yapıtı arka ucunu seçmek için `TUIST_OBJECT_STORAGE_PROVIDER` değerini ayarlayın:

| Ortam değişkeni | Açıklama | Zorunlu | Varsayılan | Örnek |
| --- | --- | --- | --- | --- |
| `TUIST_OBJECT_STORAGE_PROVIDER` | Sunucu yapıtı depolama arka ucu. S3 uyumlu depolama için `s3` veya Azure Blob Storage için `azure_blob` kullanın. | Hayır | `s3` | `azure_blob` |

#### S3 uyumlu depolama alanları {#s3compliant-storages}

Yapıları depolamak için herhangi bir S3 uyumlu depolama sağlayıcısı kullanabilirsiniz. Depolama sağlayıcısıyla entegrasyonu kimlik doğrulamak ve yapılandırmak için aşağıdaki ortam değişkenleri gereklidir:

| Ortam değişkeni | Açıklama | Zorunlu | Varsayılan | Örnek |
| --- | --- | --- | --- | --- |
| `TUIST_S3_ACCESS_KEY_ID` veya `AWS_ACCESS_KEY_ID` | Depolama sağlayıcısına karşı kimlik doğrulaması yapmak için erişim anahtarı kimliği. | Evet | | `AKIAIOSFOD` |
| `TUIST_S3_SECRET_ACCESS_KEY` veya `AWS_SECRET_ACCESS_KEY` | Depolama sağlayıcısına karşı kimlik doğrulaması yapmak için gizli erişim anahtarı. | Evet | | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY` |
| `TUIST_S3_REGION` veya `AWS_REGION` | Kovanın bulunduğu bölge. | Hayır | `auto` | `us-west-2` |
| `TUIST_S3_ENDPOINT` veya `AWS_ENDPOINT` | Depolama sağlayıcısının uç noktası | Evet | | `https://s3.us-west-2.amazonaws.com` |
| `TUIST_S3_BUCKET_NAME` | Yapıtların depolanacağı kovanın adı | Evet | | `tuist-artifacts` |
| `TUIST_S3_CA_CERT_PEM` | S3 HTTPS bağlantılarını doğrulamak için PEM kodlu CA sertifikası. Kendinden imzalı sertifikalar veya dahili Sertifika Yetkilileri ile hava boşluklu ortamlar için kullanışlıdır. | Hayır | Sistem CA paketi | `-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----` |
| `TUIST_S3_CONNECT_TIMEOUT` | Depolama sağlayıcısına bağlantı kurmak için zaman aşımı (milisaniye cinsinden) | Hayır | `3000` | `3000` |
| `TUIST_S3_RECEIVE_TIMEOUT` | Depolama sağlayıcısından veri almak için zaman aşımı (milisaniye cinsinden) | Hayır | `5000` | `5000` |
| `TUIST_S3_POOL_TIMEOUT` | Depolama sağlayıcısına bağlantı havuzu için zaman aşımı (milisaniye cinsinden). Zaman aşımı olmaması için `infinity` kullanın | Hayır | `5000` | `5000` |
| `TUIST_S3_POOL_MAX_IDLE_TIME` | Havuzdaki bağlantılar için maksimum boşta kalma süresi (milisaniye cinsinden). Bağlantıları süresiz olarak canlı tutmak için `infinity` kullanın | Hayır | `infinity` | `60000` |
| `TUIST_S3_POOL_SIZE` | Havuz başına maksimum bağlantı sayısı | Hayır | `500` | `500` |
| `TUIST_S3_POOL_COUNT` | Kullanılacak bağlantı havuzu sayısı | Hayır | Sistem zamanlayıcılarının sayısı | `4` |
| `TUIST_S3_PROTOCOL` | Depolama sağlayıcısına bağlanırken kullanılacak protokol (`http1` veya `http2`) | Hayır | `http1` | `http1` |
| `TUIST_S3_VIRTUAL_HOST` | URL'nin alt alan adı (sanal ana bilgisayar) olarak kova adıyla oluşturulup oluşturulmayacağı | Hayır | `false` | `1` |

> [!NOTE]
> **Ortam değişkenlerinden AWS web kimliği kimlik doğrulaması**
>
> Depolama sağlayıcınız AWS ise ve bir web kimliği belirteci kullanarak kimlik doğrulamak istiyorsanız, ortam değişkeni `TUIST_S3_AUTHENTICATION_METHOD` değerini `aws_web_identity_token_from_env_vars` olarak ayarlayabilirsiniz; Tuist, geleneksel AWS ortam değişkenlerini kullanarak bu yöntemi uygulayacaktır.


#### Google Cloud Storage {#google-cloud-storage}
Google Cloud Storage için, `AWS_ACCESS_KEY_ID` ve `AWS_SECRET_ACCESS_KEY` çiftini almak üzere [bu belgeleri](https://cloud.google.com/storage/docs/authentication/managing-hmackeys) izleyin. `AWS_ENDPOINT`, `https://storage.googleapis.com` olarak ayarlanmalıdır. Diğer ortam değişkenleri, diğer S3 uyumlu depolama alanlarındakiyle aynıdır.

#### Azure Blob Storage {#azure-blob-storage}

Azure Blob Storage için `TUIST_OBJECT_STORAGE_PROVIDER=azure_blob` değerini ayarlayın ve Azure depolama hesabı kimlik bilgilerini yapılandırın:

| Ortam değişkeni | Açıklama | Zorunlu | Varsayılan | Örnek |
| --- | --- | --- | --- | --- |
| `TUIST_AZURE_STORAGE_ACCOUNT_NAME` | Azure Depolama hesabı adı | Evet | | `tuiststorage` |
| `TUIST_AZURE_STORAGE_ACCOUNT_KEY` | Azure Blob REST isteklerini ve SAS URL'lerini imzalamak için kullanılan depolama hesabı erişim anahtarı | Evet | | `******` |
| `TUIST_AZURE_BLOB_CONTAINER_NAME` | Sunucu yapıtlarının depolandığı kapsayıcı | Evet | | `tuist-artifacts` |
| `TUIST_AZURE_BLOB_ENDPOINT` | Blob hizmeti uç noktası. `https://<account>.blob.core.windows.net` kullanmak için boş bırakın | Hayır | Hesap adından türetilir | `https://tuiststorage.blob.core.windows.net` |
| `TUIST_AZURE_BLOB_SERVICE_VERSION` | İmzalı istekler ve SAS URL'leri için kullanılan Azure Blob REST API sürümü | Hayır | `2020-12-06` | `2020-12-06` |

Helm şemasını kullanırken `server.storage.provider=azure_blob` değerini ayarlayın ve `server.azureBlob.*` alanlarını doldurun. Şemanın üst düzey `objectStorage` ayarları S3 uyumlu kalır çünkü isteğe bağlı önbellek ve kayıt defteri yansısı iş yükleri hâlâ S3 uyumlu depolama bekler. Bu iş yükleri devre dışıysa ve sunucu Azure Blob kullanıyorsa, gömülü MinIO hizmetinin dağıtılmasını önlemek için `objectStorage.mode=external` değerini ayarlayın ve harici nesne depolama uç noktası ile kimlik bilgilerini boş bırakın.

#### Yapıt saklama süresi {#artifact-retention}

Kendinden barındırılan örneklerde yapıt temizliği varsayılan olarak devre dışıdır. Desteklenen her yapıt türünün kendi ortam değişkeni vardır. Bir yapıt türü için temizliği etkinleştirmek amacıyla ilgili değişkene pozitif bir tam sayı gün değeri atayın. Bir değişkeni ayarlamamak veya boş bırakmak, temizliği yalnızca o yapıt türü için devre dışı bırakır.

```bash
TUIST_CACHE_ARTIFACT_RETENTION_DAYS=30
TUIST_APP_PREVIEW_RETENTION_DAYS=30
TUIST_BUILD_ARCHIVE_RETENTION_DAYS=60
TUIST_RUN_ARTIFACT_RETENTION_DAYS=30
TUIST_TEST_ATTACHMENT_RETENTION_DAYS=30
TUIST_SHARD_BUNDLE_RETENTION_DAYS=14
```

Helm şemasıyla aynı süre aralıklarını bir eşleme olarak yapılandırın:

```yaml
server:
  artifactRetentionDays:
    cacheArtifacts: 30
    appPreviews: 30
    buildArchives: 60
    runArtifacts: 30
    testAttachments: 30
    shardBundles: 14
```

Altı anahtarın tümü isteğe bağlıdır. Bu örnek, bağımsız saklama süreleriyle desteklenen her yapıt türünü etkinleştirir. Bir yapıt türü için temizliğin devre dışı kalmasını sağlamak üzere anahtarı atlayın veya değerini boş bırakın. Kendinden barındırılan saklama sürelerinde 30 günlük bir üst sınır yoktur. Pozitif tam sayı olmayan yapılandırılmış değerler sunucunun başlatma sırasında başarısız olmasına neden olur.

Bir saklama süresi değişkenini değiştirdikten sonra sunucuyu yeniden başlatın. Kuyruktaki her kendinden barındırılan temizlik partisi, dosyaları silmeden önce geçerli yapılandırmayı denetler; bu nedenle bir değişkeni ayarlamamak veya boş bırakmak ya da süresini uzatmak, yeniden başlatmadan sonra bekleyen işlerden dosyaları korur.

| Ortam değişkeni | Nesne depolamadan kaldırılan yapıt dosyaları |
| --- | --- |
| `TUIST_CACHE_ARTIFACT_RETENTION_DAYS` | Xcode önbelleği, eski içerik adreslenebilir depolama önbelleği, modül önbelleği ve Gradle önbellek dosyaları |
| `TUIST_APP_PREVIEW_RETENTION_DAYS` | Uygulama önizleme derlemeleri ve simgeleri |
| `TUIST_BUILD_ARCHIVE_RETENTION_DAYS` | Güncel ve eski derleme arşivleri |
| `TUIST_RUN_ARTIFACT_RETENTION_DAYS` | Süresi dolmuş bir çalıştırmanın yapıt öneki altında depolanan tüm nesneler; sonuç paketleri, çağrı kayıtları ve oturum arşivleri dahil |
| `TUIST_TEST_ATTACHMENT_RETENTION_DAYS` | Test çalıştırması ekleri |
| `TUIST_SHARD_BUNDLE_RETENTION_DAYS` | Test parça paketleri |

Zamanlanmış temizlik yalnızca yapıt bloblarını kaldırır. İlgili PostgreSQL ve ClickHouse satırlarını korur; böylece indirmelerin süresi dolduktan sonra bile derleme, test, çalıştırma, önizleme ve parça meta verileri panolarda görünür kalabilir. Bu yapılandırma, ClickHouse tablosu saklama kurallarını değiştirmez.

### E-posta yapılandırması {#email-configuration}

Tuist, kullanıcı kimlik doğrulaması ve işlem bildirimleri (örneğin parola sıfırlama, hesap bildirimleri) için e-posta işlevselliği gerektirir. Şu anda e-posta sağlayıcısı olarak **yalnızca Mailgun desteklenmektedir**.

| Ortam değişkeni | Açıklama | Zorunlu | Varsayılan | Örnek |
| --- | --- | --- | --- | --- |
| `TUIST_MAILGUN_API_KEY` | Mailgun ile kimlik doğrulamak için kullanılan API anahtarı | Evet* | | `key-1234567890abcdef` |
| `TUIST_MAILING_DOMAIN` | E-postaların gönderileceği alan adı | Evet* | | `mg.tuist.io` |
| `TUIST_MAILING_FROM_ADDRESS` | "Kimden" alanında görünecek e-posta adresi | Evet* | | `noreply@tuist.io` |
| `TUIST_MAILING_REPLY_TO_ADDRESS` | Kullanıcı yanıtları için isteğe bağlı yanıtla adresi | Hayır | | `support@tuist.dev` |
| `TUIST_SKIP_EMAIL_CONFIRMATION` | Yeni kullanıcı kayıtları için e-posta onayını atla. Etkinleştirildiğinde, kullanıcılar otomatik olarak onaylanır ve kayıt sonrası hemen giriş yapabilir | Hayır | E-posta yapılandırılmadıysa `true`, e-posta yapılandırıldıysa `false` | `true`, `false`, `1`, `0` |

\* E-posta yapılandırma değişkenleri yalnızca e-posta göndermek istiyorsanız gereklidir. Yapılandırılmamışsa, e-posta onayı otomatik olarak atlanır.

> [!NOTE]
> **SMTP desteği**
>
> Genel SMTP desteği şu anda mevcut değildir. Kendi altyapınızda barındırdığınız kurulumunuz için SMTP desteğine ihtiyacınız varsa, gereksinimlerinizi görüşmek üzere lütfen [contact@tuist.dev](mailto:contact@tuist.dev) adresine ulaşın.


> [!NOTE]
> **Air-gapped (internetsiz) kurulumlar**
>
> İnternet erişimi veya e-posta sağlayıcı yapılandırması olmayan yerel kurulumlarda, e-posta onayı varsayılan olarak otomatik olarak atlanır. Kullanıcılar kayıt olduktan hemen sonra giriş yapabilir. E-posta yapılandırılmış olsa bile onayı atlamak istiyorsanız, `TUIST_SKIP_EMAIL_CONFIRMATION=true` ayarlayın. E-posta yapılandırıldığında e-posta onayını zorunlu kılmak için `TUIST_SKIP_EMAIL_CONFIRMATION=false` ayarlayın.

> [!NOTE]
> **E-posta kotaları ve parola sıfırlama bağlantıları**
>
> E-posta yapılandırıldığında, davet e-postaları (oluşturulan, toplu veya yeniden gönderilen) her alıcı için beş dakikada bir adetle ve organizasyon başına ve davet eden başına saatte 50 adet yenilenen 50'lik patlamalarla sınırlıdır. Bir daveti iptal etmek bütçeyi geri yüklemez ve davetler API'si tükenmiş bütçe için `429` ve `Retry-After` ile yanıt verir. Birden fazla kopya bulunduğunda, kurulum genelinde kotalar için paylaşılan Valkey'i yapılandırın; yapılandırılmış ancak kullanılamaz durumdaysa, davet e-postaları reddedilir. Parola sıfırlama bağlantıları 15 dakika sonra sona erer.


### Git platformu yapılandırması {#git-platform-configuration}

Tuist, çekme isteklerinize otomatik olarak yorum eklemek gibi ek özellikler sağlamak için <.localized_link href="/guides/server/authentication">Git platformlarıyla entegre olabilir</.localized_link>.

#### GitHub {#platform-github}

Kendinden barındırılan bir Tuist sunucusu, `https://tuist.dev` üzerinde çalışan GitHub Uygulamasını yükleyemez. GitHub Uygulamaları, onları kaydeden sunucuya bağlıdır; bu nedenle kurulumunuzun github.com üzerinde kendi Uygulamasına ihtiyacı vardır.

##### Uygulamayı kaydetme {#platform-github-registering-the-app}

GitHub organizasyonunuzun sahibi olduğu bir [GitHub Uygulaması oluşturun](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps). Bir OAuth Uygulaması oluşturmadıysanız, kimlik doğrulama için oluşturduğunuz Uygulamayı yeniden kullanabilirsiniz. Aşağıdakilerle yapılandırın ve `YOUR_APP_URL` değerini `TUIST_APP_URL` değeriyle değiştirin:

| Ayar | Değer |
| --- | --- |
| Geri çağırma URL'leri | `YOUR_APP_URL/users/auth/github/callback` ve `YOUR_APP_URL/integrations/github/authorize` |
| Kurulum URL'si | `YOUR_APP_URL/integrations/github/setup` |
| Güncellemede yönlendir | Etkin |
| Webhook URL'si | `YOUR_APP_URL/webhooks/github` |
| Webhook gizli anahtarı | Herhangi bir rastgele dize. Bunu `TUIST_GITHUB_APP_WEBHOOK_SECRET` olarak ayarlayacaksınız |

Aşağıdaki depo izinlerini verin:

| İzin | Erişim |
| --- | --- |
| İçerikler | Salt okunur |
| Meta veriler | Salt okunur |
| Sorunlar | Okuma ve yazma |
| Çekme istekleri | Okuma ve yazma |
| Denetimler | Okuma ve yazma |

Ayrıca **Üyeler: salt okunur** organizasyon iznini verin. github.com kurulumu sırasında, Tuist bir organizasyon kurulumunu bağlayan kişinin yalnızca depolarından birine erişimi olan biri değil, aktif bir GitHub organizasyon sahibi olduğunu kontrol eder.

Uygulamayı `Check run`, `Pull request` ve `Issue comment` olaylarına abone edin.

GitHub'ın yükleyicileri Kurulum URL'sine göndermesi için **Kurulum sırasında kullanıcı yetkilendirmesi (OAuth) iste** seçeneğini devre dışı bırakın. Tuist, kurulum sahipliğini doğrulamak için ek `/integrations/github/authorize` geri çağırmasını kullanarak ayrı bir yetkilendirme adımı başlatır. GitHub'da kurulum başladığında, yükleyici ardından bir Tuist organizasyonu seçer. Bir GitHub organizasyonundaki kurulumlar her zaman bu seçeneği gösterir; Tuist'te başlatılan kurulumlar organizasyonlarını korur.

##### Sunucuyu yapılandırma {#platform-github-configuring-the-server}

Aşağıdaki ortam değişkenlerini ayarlayın, ardından sunucuyu yeniden başlatın:

| Ortam değişkeni | Açıklama | Gerekli | Varsayılan | Örnek |
| --- | --- | --- | --- | --- |
| `TUIST_GITHUB_APP_NAME` | Uygulamanın slug'ı; genel sayfa URL'sinin son yol bileşenidir `https://github.com/apps/<slug>` | Evet | | `my-company-tuist` |
| `TUIST_GITHUB_APP_ID` | Kurulum sahipliğini doğrulamak için kullanılan sayısal Uygulama Kimliği | Evet | | `123456` |
| `TUIST_GITHUB_APP_CLIENT_ID` | GitHub uygulamasının istemci kimliği | Evet | | `Iv1.a629723000043722` |
| `TUIST_GITHUB_APP_CLIENT_SECRET` | Uygulamanın istemci gizli anahtarı | Evet | | `232f972951033b89799b0fd24566a04d83f44ccc` |
| `TUIST_GITHUB_APP_PRIVATE_KEY_BASE64` | GitHub uygulamasının base64 ile kodlanmış özel anahtarı. Platformunuzun satır sonlarını nasıl işlediğine duyarlı olan `TUIST_GITHUB_APP_PRIVATE_KEY` yerine tercih edilir | Evet | | `LS0tLS1CRUdJTiBSU0EgUFJJVkFUR...` |
| `TUIST_GITHUB_APP_WEBHOOK_SECRET` | GitHub uygulamasında yapılandırılan webhook gizli anahtarı | Hayır | | `a4c1e0f2b8d6...` |

> [!IMPORTANT]
> **Gerekli tüm Uygulama kimlik bilgilerini yapılandırın**
>
> Organizasyonun entegrasyonlar sayfasındaki **GitHub Uygulamasını Yükle** düğmesi, `TUIST_GITHUB_APP_NAME`, `TUIST_GITHUB_APP_CLIENT_ID`, `TUIST_GITHUB_APP_CLIENT_SECRET` ve özel anahtar ayarlanana kadar devre dışı kalır. Kurulum sahipliğini doğrulamak için sayısal `TUIST_GITHUB_APP_ID` de gereklidir. Kurulum URL'si Uygulama slug'ını içerir; bu nedenle özellikle eksik bir `TUIST_GITHUB_APP_NAME`, GitHub'ın 404 yanıtı verdiği bir bağlantı oluşturur.

Sunucu yeniden başladıktan sonra, organizasyon yöneticileri <.localized_link href="/guides/integrations/gitforge/github">GitHub entegrasyon kılavuzu</.localized_link>nu izleyerek Uygulamayı yükler ve depoları projelere bağlar.

##### OIDC kimlik doğrulaması buna bağlıdır {#platform-github-oidc}

<.localized_link href="/guides/server/authentication#oidc-tokens">OIDC kimlik doğrulaması</.localized_link>, CI belirtecindeki depo talebini projelerinizle bağlantılı depolara göre çözer ve bağlantı yalnızca yüklü bir GitHub Uygulaması aracılığıyla oluşturulabilir. CI iş akışlarınız OIDC ile kimlik doğrulaması yapmadan önce yukarıdaki kurulumu tamamlayın.

Tuist sunucunuzun imzalama anahtarlarını almak için CI sağlayıcınızın OIDC yayıncısına giden erişime de ihtiyacı vardır:

| CI sağlayıcısı | Ana bilgisayar |
| --- | --- |
| GitHub Actions | `token.actions.githubusercontent.com` |
| CircleCI | `oidc.circleci.com` |
| Bitrise | `token.builds.bitrise.io` |

##### GitHub Enterprise Server {#platform-github-enterprise-server}

Yukarıdaki ortam değişkenleri yalnızca Tuist'in github.com Uygulamasını yapılandırır. Bunun yerine Tuist'i bir GitHub Enterprise Server (GHES) örneğiyle entegre etmek için organizasyon yöneticileri entegrasyonlar sayfasındaki **Kurumsal sunucu** sekmesine geçer ve GHES temel URL'sini girer — Tuist, GHES örneklerine yeni bir Tuist Uygulaması kaydetmek için GitHub'ın [Uygulama bildirim akışı](https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-from-a-manifest)nı adım adım gösterir. Yeni Uygulamanın kimlik bilgileri her kurulum için şifrelenmiş olarak saklanır; ek `TUIST_GITHUB_APP_*` ortam değişkenlerine gerek yoktur.

#### Origin {#platform-origin}

Kendinden barındırılan bir Tuist sunucusu, kendi Origin uygulamasına ihtiyaç duyar; bu uygulama, kurulumunuzun URL'leri ve imzalama anahtarı ile yapılandırılır. Kurulumların ve kimlik bilgilerinin bağımsız kalması için her Tuist ortamı için ayrı bir uygulama kaydedin.

##### Uygulamayı kaydetme {#platform-origin-registering-the-app}

1. Ed25519 desteği olan OpenSSL kullanarak bir Ed25519 imzalama anahtar çifti oluşturun:

   ```sh
   umask 077
   openssl genpkey -algorithm ED25519 -out origin-app-private.pem
   openssl pkey -in origin-app-private.pem -pubout -out origin-app-public.pem
   ```

2. [Origin uygulama ayarları](https://cursor.com/codebase/settings/apps)nda bir uygulama oluşturun. `origin-app-public.pem` içeriğini genel imzalama anahtarı olarak kaydedin. `origin-app-private.pem` dosyasını gizli tutun; bunu Cursor'a yüklemek yerine Tuist sunucusuna sağlayacaksınız.
3. Aşağıdaki ayarları yapılandırın ve `YOUR_APP_URL` değerini Tuist kurulumunuzun HTTPS temel URL'si ile değiştirin:

   | Ayar | Değer |
   | --- | --- |
   | Ana Sayfa URL'si | `YOUR_APP_URL` |
   | Yönlendirme URI'si | `YOUR_APP_URL/integrations/origin/setup` |
   | Webhook URL'si | `YOUR_APP_URL/webhooks/origin` |

4. `app_` ile başlayan kayıtlı Uygulama Kimliğini kopyalayın.

Tuist kurulum sırasında aşağıdaki izinleri ister:

| Kapsam | Kullanım amacı |
| --- | --- |
| `repository:pull_requests:read` | Çekme isteklerini ve mevcut head commit'lerini bulma. |
| `repository:pull_requests:reviews:write` | Rapor yorumlarını okuma, gönderme ve güncelleme. Origin buna karşılık gelen review-read iznini içerir. |
| `repository:metadata:read` | Depoları keşfetme ve varsayılan dallarını okuma. Origin tarafından otomatik olarak verilir. |

İsteğe bağlı depo webhook olaylarını seçili bırakmayın. Kurulum yaşam döngüsü bildirimleri yeterlidir; kaynak kodu erişimi, birleştirme izinleri ve check-run izinleri gerekli değildir.

##### Sunucuyu yapılandırma {#platform-origin-configuring-the-server}

Aşağıdaki ortam değişkenlerini ayarlayın, ardından sunucuyu yeniden başlatın:

| Ortam değişkeni | Açıklama | Gerekli | Varsayılan | Örnek |
| --- | --- | --- | --- | --- |
| `TUIST_ORIGIN_APP_ID` | Origin uygulama ayarlarından kopyalanan Uygulama Kimliği. | Evet | | `app_...` |
| `TUIST_ORIGIN_APP_PRIVATE_KEY` | `BEGIN PRIVATE KEY` ve `END PRIVATE KEY` satırları ile tüm satır sonları dahil olmak üzere `origin-app-private.pem` dosyasının tam içeriği. | Evet | | `-----BEGIN PRIVATE KEY-----...` |

Özel anahtarı kurulumunuzun gizli yöneticisinde saklayın. Çok satırlı PEM formatını koruyun; bu ayar base64 kodlu bir yedek kabul etmez. Anahtarı asla kaynak kontrolüne eklemeyin veya günlüklerde açığa çıkarmayın. Her iki değişken de aynı kayıtlı uygulamaya ait olmalıdır.

Tuist sunucunuzun `api.cursor.com` adresine giden HTTPS erişimine ihtiyacı vardır. Cursor webhook URL'sine istek gönderebilmeli ve yöneticiler tarayıcılarında yönlendirme URI'sine dönebilmelidir. Kayıtlı her iki URL de kurulumunuzun HTTPS temel URL'siyle eşleşmelidir.

##### Uygulamayı yükleme {#platform-origin-installing-the-app}

Sunucu yeniden başladıktan sonra bir yönetici **Ayarlar → Entegrasyonlar** bölümünü açar, Origin altındaki **Bağlan** seçeneğini belirler ve uygulamanın ilgili Origin hesabına ve depolara erişimini onaylar. Bu akış boyunca Tuist organizasyonu korunur. Doğrudan Origin üzerinden başlatılan kurulumlar bunun yerine yöneticiden giriş yapmasını ve bağlanacak Tuist organizasyonunu seçmesini ister. Ardından bir Tuist projesini yerel bir depoya bağlamak için **Yeni proje bağlantısı ekle** seçeneğini belirlerler.

Proje bağlantıları ve sonuç yükleme gereksinimleri için <.localized_link href="/guides/integrations/gitforge/origin">Origin entegrasyon kılavuzu</.localized_link>nu izleyin. Uygulamayı yüklemek derleme veya test iş akışlarını başlatmaz; bu iş akışları sonuçları Tuist sunucunuza raporlamaya devam eder.

#### Entire {#platform-entire}

Kendinden barındırılan bir Tuist sunucusu, kendi Entire eklentisine ihtiyaç duyar; bu eklenti, kurulumunuzun URL'leri ve imzalama anahtarı ile yapılandırılır. Entire eklentileri ortak kaydı gerektirir, bu nedenle başlamadan önce Entire ile iletişime geçin. Kurulumların ve kimlik bilgilerinin bağımsız kalması için her Tuist ortamı için ayrı bir eklenti veya en azından ayrı bir imzalama anahtarı kaydedin.

##### Eklentiyi kaydetme {#platform-entire-registering-the-plugin}

1. Ed25519 desteği olan OpenSSL kullanarak bir Ed25519 imzalama anahtar çifti oluşturun:

   ```sh
   umask 077
   openssl genpkey -algorithm ED25519 -out entire-plugin-private.pem
   openssl pkey -in entire-plugin-private.pem -pubout -out entire-plugin-public.pem
   ```

2. Eklentiyi Entire'ın [eklenti kayıt kılavuzu](https://docs.entire.com/guides/api/plugins/register)nu izleyerek kaydedin. Eklentinin imzalama anahtarı olarak `entire-plugin-public.pem` içeriğini veya bunu yayınlayan bir JWKS URL'sini paylaşın. `entire-plugin-private.pem` dosyasını gizli tutun; bunu Entire'a değil, Tuist sunucusuna sağlayacaksınız.
3. Aşağıdaki URL'leri yapılandırın ve `YOUR_APP_URL` değerini Tuist kurulumunuzun HTTPS temel URL'si ile değiştirin:

   | Ayar | Değer |
   | --- | --- |
   | Kurulum sonrası URL | `YOUR_APP_URL/integrations/entire/callback` |
   | Webhook URL'si | `YOUR_APP_URL/webhooks/entire` |

4. Entire'ın onayladığı eklenti slug'ını ve sağladığı webhook imzalama anahtarı URL'sini not edin.

Aşağıdaki izinleri isteyin:

| İzin | Kullanım amacı |
| --- | --- |
| `contents:read` | Trail olaylarını alın ve baş commit'leriyle birlikte açık ve taslak Trail'leri bulun. |
| `checks:write` | Tuist kapısını yayınlayın. |
| `findings:write` | Başarısız ve kararsız test bulgularını yayınlayın ve çözümleyin. |
| `discussions:write` | Özet yorumunu gönderin ve güncelleyin. Bu izni vermemiş kurulumlar yine de kapıyı ve bulguları alır. |

Depo yazma erişimi gerekli değildir. Mevcut bir kayda izin eklerseniz Entire'dan bunu güncellemesini isteyin ve kurulumların yeni izinleri verdiğini doğrulayın. Entire'ın [Checks](https://docs.entire.com/guides/api/plugins/report-checks), [Findings](https://docs.entire.com/guides/api/plugins/trail-findings) ve [Trail comments](https://docs.entire.com/guides/api/plugins/trail-comments.md) sözleşmelerine bakın.

##### Sunucuyu yapılandırma {#platform-entire-configuring-the-server}

Aşağıdaki ortam değişkenlerini ayarlayın, ardından sunucuyu yeniden başlatın:

| Ortam değişkeni | Açıklama | Gerekli | Varsayılan | Örnek |
| --- | --- | --- | --- | --- |
| `TUIST_ENTIRE_PLUGIN_SLUG` | Entire tarafından onaylanan eklenti slug'ı. | Evet | | `tuist` |
| `TUIST_ENTIRE_PLUGIN_PRIVATE_KEY` | `entire-plugin-private.pem` dosyasının tamamı; `BEGIN PRIVATE KEY` ve `END PRIVATE KEY` satırları ile tüm satır sonları dahil. | Evet | | `-----BEGIN PRIVATE KEY-----...` |
| `TUIST_ENTIRE_DELIVERY_JWKS_URL` | Kayıt sırasında Entire tarafından sağlanan webhook imzalama anahtarı URL'si. | Evet | | |
| `TUIST_ENTIRE_PLUGIN_KEY_ID` | İmzalama anahtarını bir JWKS üzerinden kaydettiğinizdeki anahtar kimliği. | Hayır | | |
| `TUIST_ENTIRE_CORE_URL` | Kurulum istekleri için kullanılan Entire Core URL'si. | Hayır | `https://eu.auth.entire.io` | |

Özel anahtarı kurulumunuzun gizli yöneticisinde saklayın ve çok satırlı PEM formatını koruyun. Anahtarı asla kaynak kontrolüne kaydetmeyin veya günlüklerde açığa çıkarmayın. Tuist Helm grafiğiyle bunun yerine PEM'i 1Password kasasında `ENTIRE_PLUGIN/private_key` olarak saklayabilir ve `server.config.managedSecrets` yanında `server.config.entirePluginKey.enabled` seçeneğini etkinleştirebilirsiniz; öğe ve alan adları `server.config.entirePluginKey.item` ve `.field` aracılığıyla yapılandırılabilir. Bu eşleme slug'ı veya webhook imzalama anahtarı URL'sini ayarlamaz.

Tuist sunucunuzun Entire Core'a ve depolarınıza hizmet veren bölgesel Entire API sunucularına giden HTTPS erişimine ihtiyacı vardır; tümü `entire.io` veya `entire.com` altındadır. Tuist, kurulum makbuzlarını ve webhook imzalarını doğrular, kısa ömürlü depo kapsamlı jetonlar basar ve jetonları rapor bağlantalarına asla gömmez.

##### Entegrasyonu etkinleştirme {#platform-entire-enabling-the-integration}

Uygulamayı dağıtmadan önce sunucu migrasyonlarını uygulayın, ardından entegrasyonu tüm hesaplara veya seçili hesaplara sunmak için `entire_trails` özellik bayrağını genel olarak etkinleştirin. Bayrağı etkinleştirmek Entire'da eklentiyi kimlerin yükleyebileceğini değiştirmez; bunu eklentinin sahibi olduğu Entire projesinin dışında sunmak için Entire temsilcinizden buna izin vermesini isteyin. Entegrasyon, Tuist'in CI yürütme yapılandırmasından bağımsızdır.

Uygulamayı geri alırsanız, daha sonraki bir yükseltmenin devam eden yayınlamaları kurtarabilmesi için `entire_trail_reports` tablosunu saklayın.

Yöneticiler daha sonra eklentiyi yükler ve <.localized_link href="/guides/integrations/gitforge/entire">Entire entegrasyon kılavuzu</.localized_link>nu izleyerek depoları projelere bağlar. Eklentiyi yüklemek derleme veya test iş akışlarını başlatmaz; bu iş akışları sonuçları Tuist sunucunuza raporlamaya devam eder.

## Yerel olarak test etme {#testing-locally}

Altyapınıza dağıtmadan önce Tuist sunucusunu yerel makinenizde test etmek için gereken tüm bağımlılıkları içeren kapsamlı bir Docker Compose yapılandırması sunuyoruz:

- PostgreSQL 15
- Analitik için ClickHouse 26.5
- Koordinasyon için ClickHouse Keeper
- S3 uyumlu depolama için MinIO
- Yerel kendi kendine barındırılan önbellek testi için Kura
- Veritabanı yönetimi için pgweb

> [!CAUTION]
> **Lisans gerekli**
>
> Tuist sunucusunu çalıştırmak için, yerel geliştirme örnekleri dahil, yasal olarak geçerli bir `TUIST_LICENSE` ortam değişkeni gereklidir. Lisansa ihtiyacınız varsa lütfen [contact@tuist.dev](mailto:contact@tuist.dev) adresinden bizimle iletişime geçin.


**Hızlı Başlangıç:**

1. Yapılandırma dosyalarını indirin:
   ```bash
   curl -O https://tuist.dev/server/self-host/docker-compose.yml
   curl -O https://tuist.dev/server/self-host/clickhouse-config.xml
   curl -O https://tuist.dev/server/self-host/clickhouse-log-level.xml
   curl -O https://tuist.dev/server/self-host/clickhouse-log-ttl.xml
   curl -O https://tuist.dev/server/self-host/clickhouse-keeper-config.xml
   curl -O https://tuist.dev/server/self-host/.env.example
   ```

2. Ortam değişkenlerini yapılandırın:
   ```bash
   cp .env.example .env
   # Edit .env and add your TUIST_LICENSE, TUIST_SECRET_KEY_BASE, and authentication credentials
   ```

   Birlikte verilen ClickHouse hizmeti şu isteğe bağlı operasyonel günlük denetimlerini kabul eder:

   | Ortam değişkeni | Açıklama | Varsayılan | Örnek |
   | --- | --- | --- | --- |
   | `CLICKHOUSE_SYSTEM_LOG_TTL_DAYS` | `system.*` gibi `text_log`, `query_log`, `trace_log`, `metric_log` ve `part_log` ClickHouse günlük tabloları için gün cinsinden saklama süresi | `14` | `7` |
   | `CLICKHOUSE_TEXT_LOG_LEVEL` | ClickHouse sunucu günlükçüsü ve `system.text_log` seviyesi | `information` | `warning` |
   | `CLICKHOUSE_SUPERSEDED_LOG_TABLES` | ClickHouse bir sistem günlüğü tablosunu değiştirdiğinde geride bıraktığı `<name>_N` tablolarıyla ne yapılacağı. `ignore` onları tutar, `delete` siler | `ignore` | `delete` |

3. Tüm hizmetleri başlatın:
   ```bash
   docker compose up -d
   # or with podman:
   podman compose up -d
   ```

   Apple Silicon'da Docker Desktop, Tuist ve bağımlılık imajlarının `linux/arm64` varyantlarını otomatik olarak çeker. Hata ayıklama için amd64 öykünmesini zorlamak üzere Compose'u `DOCKER_DEFAULT_PLATFORM=linux/amd64` ile çalıştırın.

   Birlikte verilen compose dosyası kalıcı veriler için adlandırılmış Docker birimlerini kullanır. Bunları ana bilgisayar bağlama noktalarıyla değiştirirseniz, önce ana bilgisayar dizinlerini oluşturun ve özellikle ClickHouse ile ClickHouse Keeper veri dizinlerini kapsayıcı kullanıcıları tarafından yazılabilir hale getirin.

4. Sunucuya http://localhost:8080 adresinden erişin

**Hizmet Uç Noktaları:**
- Tuist Sunucusu: http://localhost:8080
- Kura önbelleği (tek bağlantı noktasında HTTP + REAPI gRPC): http://localhost:4000
- MinIO Konsolu: http://localhost:9003 (kimlik bilgileri: `tuist` / `tuist_dev_password`)
- MinIO API: http://localhost:9002
- pgweb (PostgreSQL Kullanıcı Arayüzü): http://localhost:8081
- Prometheus Metrikleri: http://localhost:9091/metrics
- ClickHouse HTTP: http://localhost:8124

**Yaygın Komutlar:**

Hizmet durumunu kontrol edin:
```bash
docker compose ps
# or: podman compose ps
```

Günlükleri görüntüleyin:
```bash
docker compose logs -f tuist
```

Hizmetleri durdurun:
```bash
docker compose down
```

Her şeyi sıfırlayın (tüm verileri siler):
```bash
docker compose down -v
```

**Yapılandırma Dosyaları:**
- [docker-compose.yml](/server/self-host/docker-compose.yml) - Tam Docker Compose yapılandırması
- [clickhouse-config.xml](/server/self-host/clickhouse-config.xml) - ClickHouse yapılandırması
- [clickhouse-keeper-config.xml](/server/self-host/clickhouse-keeper-config.xml) - ClickHouse Keeper yapılandırması
- [.env.example](/server/self-host/.env.example) - Örnek ortam değişkenleri dosyası

## Helm ile Kubernetes {#kubernetes-with-helm}

Tuist, Kubernetes üzerinde dağıtım için resmi bir Helm grafiği sağlar. Grafik, Tuist sunucusunu ve önbellek hizmetini paketler; ayrıca gerektiğinde harici sağlayıcılarla değiştirebileceğiniz gömülü altyapı bağımlılıklarını içerir.

### Grafiği yükleme {#installing-the-chart}

```bash
helm install tuist oci://ghcr.io/tuist/charts/tuist \
  --set server.license.key="YOUR_LICENSE_KEY"
```

Belirli bir grafik sürümünü sabitlemek için:

```bash
helm install tuist oci://ghcr.io/tuist/charts/tuist \
  --set server.license.key="YOUR_LICENSE_KEY" \
  --version 0.1.0
```

### Lisans {#helm-license}

`server.license.key` değeri hem standart lisans anahtarını hem de hava boşluklu kurulumlar için Base64 kodlu lisans sertifikasını kabul eder; sunucu hangisi olduğunu otomatik olarak algılar.

Lisansı `--set` ile geçirmek hızlı kurulum için işe yarar. Değerlerinizi sürüm kontrolünde tutuyorsanız, lisansı Helm dışında yönettiğiniz bir Kubernetes Secret'ında saklayın (örneğin Vault, Sealed Secrets veya SOPS ile) ve grafiği buna yönlendirin:

```yaml
# values.yaml
server:
  license:
    existingSecret: tuist-license
    existingSecretKeys:
      key: TUIST_LICENSE
      certificateBase64: ""
```

`existingSecretKeys.key` altındaki giriş, lisans değerini (lisans anahtarı veya hava boşluklu kurulumlar için Base64 kodlu lisans sertifikası) tutan Secret alanının adını belirtir. `existingSecretKeys` altındaki her giriş varsayılan olarak grafiğin kendi anahtar adını alır; bu nedenle yukarıdaki `certificateBase64` gibi, Secret'ınızın içermeyen girişleri boş dizeye ayarlayın. Aksi takdirde podlar var olmayan anahtarlara başvurur ve başlatılamaz. Grafiği yüklemeden veya yükseltmeden önce Secret'ı release namespace'inde oluşturun.

Lisansı yalnızca tek bir kaynaktan yapılandırın: `server.license.key` veya `server.license.existingSecret`. Hiçbiri ayarlanmadığında veya kaynaklar birleştirildiğinde grafik oluşturulamaz. `server.extraEnv` üzerinden geçirilen bir lisans kaynak olarak sayılmaz, bunun yerine `existingSecret` kullanın.

### Altyapı bağımlılıkları {#helm-infrastructure-dependencies}

Grafik üç altyapı bağımlılığını yönetir: `postgresql`, `clickhouse` ve `objectStorage`. Her biri varsayılan olarak **gömülü** moddadır; yani grafik bunları küme içinde dağıtır. Bunun yerine kendi harici örneklerinizi kullanmak için bağımlılığın `mode` değerini `external` olarak ayarlayın ve bağlantı ayrıntılarını `values.yaml` dosyanıza girin. Örneğin, harici bir PostgreSQL veritabanı kullanmak için:

```yaml
# values.yaml
postgresql:
  mode: external
  external:
    host: your-db-host
    port: 5432
    database: tuist
    username: tuist
    password: your-password
```

PostgreSQL kimlik bilgilerini Helm dışında yönetiyorsanız, grafiği bunun yerine mevcut bir Kubernetes Secret'ına yönlendirin:

```yaml
# values.yaml
postgresql:
  mode: external
  external:
    port: 5432
    database: tuist
    existingSecret: tuist-postgresql
    existingSecretKeys:
      host: host
      username: username
      password: password
```

Grafik ana bilgisayar adını, kullanıcı adını ve parolayı Secret'tan okur ve Kubernetes ortam değişkeni ikamesi yoluyla `DATABASE_URL` oluşturur; böylece parola Helm manifestosuna işlenmez. Secret'taki parola değeri bir veritabanı URL'sine eklendiği için URL uyumlu olmalıdır.

Aynı düzen `clickhouse` ve `objectStorage` için de geçerlidir. Yapılandırılabilir alanların tam listesi için grafiğin `values.yaml` dosyasındaki her bölüm altındaki `external` bloğuna bakın.

### Paylaşılan zamanlama ve etiketler {#helm-shared-scheduling-and-labels}

Grafik, operatörlerin her iş yükü için aynı değerleri tekrarlamadan dağıtımı kümelerine uyarlamasını sağlamak amacıyla `global` altında küçük bir paylaşılan pod ayarları kümesini sunar:

```yaml
global:
  podLabels:
    environment: production
  imagePullSecrets:
    - name: ghcr-pull-secret
  nodeSelector:
    nodepool: apps
  tolerations:
    - key: dedicated
      operator: Equal
      value: apps
      effect: NoSchedule
```

Bu ayarları şu durumlarda kullanın:

- her poda küme özel etiketler eklemek
- yansıtılmış görüntüleri özel bir kayıt defterinden çekmek
- özel bir düğüm havuzunu hedeflemek
- Tuist iş yükleri için ayrılmış lekeli düğümlere podlara izin vermek

### İş yükü kimliği ve hizmet hesapları {#helm-workload-identity}

Grafik, hizmet hesaplarını uygulama iş yükü başına kapsamlar; böylece kimliği yalnızca gerektiği yerde verebilirsiniz:

- `server.serviceAccount` Tuist sunucu dağıtımına ve geçiş işine uygulanır
- `cache.serviceAccount` önbellek dağıtımına uygulanır

Örneğin, önbellek EKS üzerinde harici bir S3 kovası kullandığında, gömülü veritabanlarına aynı IAM rolünü eklemeden önbellek iş yükü için IRSA'yı etkinleştirebilirsiniz:

```yaml
cache:
  serviceAccount:
    create: true
    annotations:
      eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/tuist-cache
```

### Uyumluluk geçersiz kılmaları {#helm-compatibility-overrides}

Grafik, depolama ve ağ örgüsü özgü ince ayarları isteğe bağlı tutar; böylece varsayılanlar taşınabilir kalır:

```yaml
cache:
  podSecurityContext:
    fsGroup: 990

clickhouse:
  embedded:
    service:
      nativePort: 9100
    systemLogs:
      ttlDays: 7
      supersededTables: delete
      level: warning
```

Bu geçersiz kılmaları yalnızca kümeniz gerektirdiğinde kullanın:

- `cache.podSecurityContext` varsayılan olarak boştur. Depolama sınıfınız veya CSI sürücünüz bağlanan birimlerde paylaşılan grup sahipliği gerektiriyorsa `fsGroup` ayarlayın.
- `clickhouse.embedded.service.nativePort` ClickHouse'un standart `9000` yerel hizmet portuna varsayılan olarak ayarlanır ve bir hizmet ağı veya platform rezervasyonu bu portla çakıştığında değiştirilebilir.
- `clickhouse.embedded.systemLogs.ttlDays` varsayılan olarak boştur; bu durum ClickHouse'un `system.text_log`, `system.query_log`, `system.trace_log`, `system.metric_log` ve `system.part_log` gibi gömülü dahili günlük tablolarındaki sınırsız saklama süresini bırakır. Ayarlamak bu tabloları bir kez geçersiz kılar, bu nedenle `supersededTables: delete` ile birlikte benimseyin — bkz. <.localized_link href="/guides/server/self-host/server#capping-operational-log-retention">işletimsel günlük saklama süresini sınırlama</.localized_link>.
- `clickhouse.embedded.systemLogs.level` gömülü ClickHouse sunucusu günlükçüsü ve `system.text_log` için varsayılan olarak `information` değerindedir. `ttlDays` aksine, herhangi bir tablo tanımının parçası değildir; bu nedenle değiştirmek hiçbir zaman bir tabloyu geçersiz kılmaz.
- `clickhouse.embedded.systemLogs.supersededTables` varsayılan olarak `ignore` değerindedir ve ClickHouse'un bir sistem günlük tablosunu geçersiz kıldığında geride bıraktığı `<name>_N` tablolarına ne olacağını belirler. Her `helm upgrade` sırasında bunları silmek için `delete` olarak ayarlayın.
- `ttlDays` ve `level` üzerindeki değişiklikler ClickHouse poduna yeniden başladığında ulaşır; çünkü ikisi de `subPath` bağlantılarıdır ve grafik ConfigMap'i değiştiğinde StatefulSet'i yeniden başlatmaz.

### Gözlemlenebilirlik {#helm-observability}

Grafik isteğe bağlı bir gözlemlenebilirlik yığını (OpenTelemetry Collector, Prometheus, Grafana, Loki ve Tempo) içerir. Varsayılan olarak **devre dışıdır**. `values.yaml` dosyanızda etkinleştirmek için:

```yaml
# values.yaml
observability:
  enabled: true
```

Etkinleştirildiğinde, Günlükler, İzler ve Metrikler derinlemesine incelemeleri önceden yapılandırılmış olarak Grafana'da kullanılabilir. Harici gözlemlenebilirlik için bunu devre dışı bırakın ve uç noktaları `server.extraEnv` üzerinden yapılandırın:

```yaml
# values.yaml
server:
  extraEnv:
    - name: TUIST_OTEL_EXPORTER_OTLP_ENDPOINT
      value: "http://your-otel-collector:4317"
    - name: TUIST_LOKI_URL
      value: "http://your-loki:3100"
```

### Değerler referansı {#helm-values-reference}

Yapılandırılabilir değerlerin tam listesi için grafiğin [`values.yaml`](https://github.com/tuist/tuist/blob/main/infra/helm/tuist/values.yaml) dosyasına bakın.

## Dağıtım {#deployment}

Resmi Tuist Docker görüntüsü şurada mevcuttur:
```
ghcr.io/tuist/tuist
```

Yayınlanan görüntü, `.xcactivitylog` arşivleri için gömülü Linux derleme işlemesini içerir; bu sayede kendi kendine barındırılan dağıtımlar ek bir hizmet çalıştırmadan derlemeleri işleyebilir — `ProcessBuildWorker` Oban işi her sunucu podunda süreç içinde çalışır. Derleme işlemesini özel bir çoğaltma kümesine aktarmak istiyorsanız (örneğin, web katmanından bağımsız olarak ayrıştırma verimini ölçeklendirmek için) Helm grafiğinde `processor.enabled: true` ayarlayın: grafik aynı görüntüyü yalnızca kuyruk tüketen bir tüketici olarak dağıtır (`TUIST_PROCESSOR_MODE=true`). Ayarlanabilir parametrelerin tam listesi için [`values.yaml`](https://github.com/tuist/tuist/blob/main/infra/helm/tuist/values.yaml) bölümüne bakın.

> [!NOTE]
> `.xcresult` ayrıştırma Xcode'dan `xcresulttool` aracına dayanır, bu nedenle yalnızca macOS üzerinde çalışabilir. CLI, kendi kendine barındırılan dağıtımlar için bunu şeffaf bir şekilde yönetir: `tuist test`, `tuist.dev` olmayan herhangi bir sunucuya karşı varsayılan olarak **yerel** işleme modunu kullanır, xcresult'ı geliştirici makinesinde (derleme için zaten Xcode'a sahip olan) ayrıştırır ve yapılandırılmış sonuçları yükler. Test sonuçları ek altyapı olmadan alınır.

### Docker görüntüsünü çekme {#pulling-the-docker-image}

Görüntüyü aşağıdaki komutu çalıştırarak alabilirsiniz:

```bash
docker pull ghcr.io/tuist/tuist:latest
```

Görüntü hem `linux/amd64` hem de `linux/arm64` için yayınlanır; bu nedenle Docker, ana bilgisayar için yerel Linux mimarisini otomatik olarak seçer.

Veya belirli bir sürümü çekin:
```bash
docker pull ghcr.io/tuist/tuist:0.1.0
```

### Docker görüntüsünü dağıtma {#deploying-the-docker-image}

Docker görüntüsünün dağıtım süreci, seçtiğiniz bulut sağlayıcısına ve kuruluşunuzun sürekli dağıtım yaklaşımına göre değişecektir. [Kubernetes](https://kubernetes.io/) gibi çoğu bulut çözümü ve aracı Docker görüntülerini temel birimler olarak kullandığından, bu bölümdeki örnekler mevcut kurulumunuzla iyi uyum sağlayacaktır.

> [!WARNING]
> Dağıtım hattınızın sunucunun çalışır durumda olduğunu doğrulaması gerekiyorsa, `/ready` adresine bir `GET` HTTP isteği gönderebilir ve yanıtta `200` durum kodunu doğrulayabilirsiniz.


#### Fly {#fly}

Uygulamayı [Fly](https://fly.io/) üzerinde dağıtmak için bir `fly.toml` yapılandırma dosyasına ihtiyacınız olacaktır. Bunu Sürekli Dağıtım (CD) hattınızda dinamik olarak oluşturmayı düşünebilirsiniz. Aşağıda kullanımınız için referans bir örnek bulunmaktadır:

```toml
app = "tuist"
primary_region = "fra"
kill_signal = "SIGINT"
kill_timeout = "5s"

[experimental]
  auto_rollback = true

[env]
  # Your environment configuration goes here
  # Or exposed through Fly secrets

[processes]
  app = "/usr/local/bin/hivemind /app/Procfile"

[[services]]
  protocol = "tcp"
  internal_port = 8080
  auto_stop_machines = false
  auto_start_machines = false
  processes = ["app"]
  http_options = { h2_backend = true }

  [[services.ports]]
    port = 80
    handlers = ["http"]
    force_https = true

  [[services.ports]]
    port = 443
    handlers = ["tls", "http"]
  [services.concurrency]
    type = "connections"
    hard_limit = 100
    soft_limit = 80

  [[services.http_checks]]
    interval = 10000
    grace_period = "10s"
    method = "get"
    path = "/ready"
    protocol = "http"
    timeout = 2000
    tls_skip_verify = false
    [services.http_checks.headers]

[[statics]]
  guest_path = "/app/public"
  url_prefix = "/"
```

Ardından uygulamayı başlatmak için `fly launch --local-only --no-deploy` komutunu çalıştırabilirsiniz. Sonraki dağıtımlarda, `fly launch --local-only` çalıştırmak yerine `fly deploy --local-only` çalıştırmanız gerekecektir. Fly.io özel Docker görüntülerinin çekilmesine izin vermez; bu nedenle `--local-only` bayrağını kullanmamız gerekir.


## Prometheus metrikleri {#prometheus-metrics}

Tuist, kendi kendine barındırılan örneğinizi izlemenize yardımcı olmak üzere `/metrics` adresinde Prometheus metriklerini sunar. Bu metrikler şunları içerir:

### Finch HTTP istemci metrikleri {#finch-metrics}

Tuist, HTTP istemcisi olarak [Finch](https://github.com/sneako/finch) kullanır ve HTTP istekleri hakkında ayrıntılı metrikler sunar:

#### İstek metrikleri
- `tuist_prom_ex_finch_request_count_total` - Toplam Finch istek sayısı (sayaç)
  - Etiketler: `finch_name`, `method`, `scheme`, `host`, `port`, `status`
- `tuist_prom_ex_finch_request_duration_milliseconds` - HTTP isteklerinin süresi (histogram)
  - Etiketler: `finch_name`, `method`, `scheme`, `host`, `port`, `status`
  - Kovalar: 10ms, 50ms, 100ms, 250ms, 500ms, 1s, 2.5s, 5s, 10s
- `tuist_prom_ex_finch_request_exception_count_total` - Toplam Finch istek istisna sayısı (sayaç)
  - Etiketler: `finch_name`, `method`, `scheme`, `host`, `port`, `kind`, `reason`

#### Bağlantı havuzu kuyruk metrikleri
- `tuist_prom_ex_finch_queue_duration_milliseconds` - Bağlantı havuzu kuyruğunda bekleme süresi (histogram)
  - Etiketler: `finch_name`, `scheme`, `host`, `port`, `pool`
  - Kovalar: 1ms, 5ms, 10ms, 25ms, 50ms, 100ms, 250ms, 500ms, 1s
- `tuist_prom_ex_finch_queue_idle_time_milliseconds` - Bağlantının kullanılmadan önce boşta geçirdiği süre (histogram)
  - Etiketler: `finch_name`, `scheme`, `host`, `port`, `pool`
  - Kovalar: 10ms, 50ms, 100ms, 250ms, 500ms, 1s, 5s, 10s
- `tuist_prom_ex_finch_queue_exception_count_total` - Toplam Finch kuyruk istisna sayısı (sayaç)
  - Etiketler: `finch_name`, `scheme`, `host`, `port`, `kind`, `reason`

#### Bağlantı metrikleri
- `tuist_prom_ex_finch_connect_duration_milliseconds` - Bağlantı kurmak için harcanan süre (histogram)
  - Etiketler: `finch_name`, `scheme`, `host`, `port`, `error`
  - Kovalar: 10ms, 50ms, 100ms, 250ms, 500ms, 1s, 2.5s, 5s
- `tuist_prom_ex_finch_connect_count_total` - Toplam bağlantı deneme sayısı (sayaç)
  - Etiketler: `finch_name`, `scheme`, `host`, `port`

#### Gönderme metrikleri
- `tuist_prom_ex_finch_send_duration_milliseconds` - İsteği göndermek için harcanan süre (histogram)
  - Etiketler: `finch_name`, `method`, `scheme`, `host`, `port`, `error`
  - Kovalar: 1ms, 5ms, 10ms, 25ms, 50ms, 100ms, 250ms, 500ms, 1s
- `tuist_prom_ex_finch_send_idle_time_milliseconds` - Bağlantının göndermeden önce boşta geçirdiği süre (histogram)
  - Etiketler: `finch_name`, `method`, `scheme`, `host`, `port`, `error`
  - Kovalar: 1ms, 5ms, 10ms, 25ms, 50ms, 100ms, 250ms, 500ms

Tüm histogram metrikleri, ayrıntılı analiz için `_bucket`, `_sum` ve `_count` varyantlarını sağlar.

### Diğer metrikler

Finch metriklerine ek olarak, Tuist şu metrikleri sunar:
- BEAM sanal makine performansı
- Özel iş mantığı metrikleri (depolama, hesaplar, projeler vb.)
- Veritabanı performansı (Tuist tarafından barındırılan altyapı kullanılırken)

## İşlemler {#operations}

Tuist, örneğinizi yönetmek için kullanabileceğiniz bir dizi yardımcı programı `/ops/` altında sunar.

> [!WARNING]
> **Yetkilendirme**
>
> Yalnızca e-posta alan adı `TUIST_OPERATOR_EMAIL_DOMAIN` ile eşleşen kullanıcılar `/ops/` uç noktalarına erişebilir. Değişken ayarlanmamışsa kimse bunlara erişemez. Posta kutularını kontrol ettiğiniz bir alan adına ayarlayın.
>
> Kullanıcının adresinin kontrolünü de kanıtlaması gerekir: bir onay veya şifre sıfırlama e-postasını takip ederek, Google, GitHub veya Apple ile oturum açarak ya da tek seferlik kodu girerek veya aracı oturum açma için doğrulanmış e-postayı sunarak. Varsayılan olarak posta sağlayıcı olmadan otomatik olarak onaylanan hesaplar, bunu yapana kadar uygun değildir. Hesap oluşturulduktan sonra, yalnızca adres `TUIST_OPERATOR_EMAIL_DOMAIN` içindeyken bir kanıt kaydedilir; bu nedenle değişkeni ayarladıktan veya değiştirdikten sonra, altında adresini kanıtlamamış operatörler bunu yeniden yapmalıdır. Bu sağlayıcılardan biriyle oturum açarak veya aracı oturum açma yoluyla oluşturulan hesaplar, oluşturma anından itibaren kanıtı taşır. Posta sağlayıcı olmadan, parolayla kaydedilen bir hesap bu sağlayıcılardan birini bağlayamaz; bu nedenle operatör hesaplarını Google, GitHub veya Apple ile oturum açarak oluşturun veya bir posta sağlayıcı yapılandırın.
>
> Bu kontrol mevcut olmadan önce oluşturulan hesaplar henüz bu kanıtı kaydetmemiştir, bu nedenle mevcut bir operatör parolasını sıfırladıktan veya bu sağlayıcılardan biriyle bir kez oturum açtıktan sonra erişimi geri kazanır.
>
> Operatör alanındaki bir hesap bu kanıta sahip olmadan ilk kez adresini bu şekilde kanıtladığında, Tuist parolasını, passkey'lerini ve kuruluş tek oturum açma sağlayıcılarına olan bağlantılarını kaldırır ve tarayıcıdan ve CLI'dan çıkış yapar çünkü adresi kaydeden kişi onun sahibi olmayabilir. Böyle bir hesapta yapılan parola sıfırlama işlemi, yeni parolayı ayarlamanın dışında aynı şeyi yapar. Hesapta kurulu bir kimlik doğrulayıcı uygulaması kalır; eğer bu sahibine ait değilse, onun için kaldırın. Operatör alanı dışındaki onaylanmış hesaplar kimlik bilgilerini korur. Sahip, sağlayıcıyla oturum açmaya devam eder veya sıfırlama yoluyla yeni bir parola belirler.
>
> SCIM sağlama tarafından oluşturulan veya yeniden adlandırılan hesapların, sahipleri kanıtı sağlayana kadar herhangi bir kanıtı yoktur.


- **Hatalar (`/ops/errors`):** Uygulamada oluşan beklenmeyen hataları görüntüleyebilirsiniz. Bu, hata ayıklama ve neyin yanlış gittiğini anlamak için yararlıdır ve sorunlarla karşılaşıyorsanız bu bilgiyi bizimle paylaşmanızı isteyebiliriz.
- **Gösterge Paneli (`/ops/dashboard`):** Uygulamanın performansı ve sağlığı hakkında içgörüler sağlayan bir gösterge panelini görüntüleyebilirsiniz (örn. bellek tüketimi, çalışan işlemler, istek sayısı). Bu gösterge paneli, kullandığınız donanımın yükü kaldırmak için yeterli olup olmadığını anlamak için oldukça yararlı olabilir.
