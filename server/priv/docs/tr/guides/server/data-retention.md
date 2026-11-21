---
{
  "title": "Veri saklama",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "Tuist'in indirilebilir yapıtları ve pano etkinlik verilerini ne kadar süreyle sakladığını öğrenin."
}
---
# Veri saklama {#data-retention}

Tuist, yüklenen yapıt dosyaları ile panolar ve içgörüler için kullanılan kayıtlar için ayrı saklama politikaları uygular. Süresi dolmuş bir yapıt dosyasının silinmesi, ilişkili içgörü kayıtlarını silmez.

Yapıt dosyaları için barındırılan Tuist sunucusu, 30 günle sınırlı plana dayalı zaman aralıkları kullanır. Kendi kendine barındırılan örneklerde yapıt temizleme varsayılan olarak devre dışıdır; operatörler katılım sağlayabilir ve desteklenen her yapıt türü için ayrı bir zaman aralığı yapılandırabilir.

## Yapıt dosyaları {#artifact-files}

### Barındırılan Tuist sunucusu {#hosted-artifact-files}

Bu zaman aralıkları, yapıt dosyalarının barındırılan Tuist sunucusunda ne kadar süreyle kullanılabilir kalacağını belirler.

| Yapıt | Air ve Açık Kaynak | Pro | Enterprise |
| --- | --- | --- | --- |
| Önbellek yapıtları; Xcode önbelleği, modül önbelleği, Gradle önbelleği, Bazel uzak önbellek dosyaları ve Tuist Runners’dan gelen GitLab CI önbellek arşivleri dahil | 14 gün | 30 gün | 30 gün |
| Uygulama önizleme derlemeleri ve simgeler | 30 gün | 30 gün | 30 gün |
| Derleme arşivleri | 7 gün | 30 gün | 30 gün |
| Çalıştırma yapıtları; sonuç paketleri, oturum arşivleri ve Bazel uzak eylem günlükleri dahil | 7 gün | 30 gün | 30 gün |
| Test çalıştırması ekleri | 30 gün | 30 gün | 30 gün |
| Parça paketleri | 7 gün | 14 gün | 30 gün |

Etkin hesap planı, barındırılan saklama zaman aralığını belirler. Bir hesabın etkin aboneliği yoksa Tuist Air saklama zaman aralığını kullanır. Bazı yapıt türleri yeniden oluşturulmaları beklendiği için daha kısa zaman aralıkları kullanır.

Tuist bir test çalıştırması tanımlayıcısını kaydetmeden önce oluşturulan test ekleri otomatik silme kapsamı dışındadır. Dosyaları, saklama temizliği sırasında sınırsız geçmiş sahiplik aramasından kaçınırken kullanılmaya devam eder.

### Kendi kendine barındırılan örnekler {#self-hosted-artifact-files}

Kendi kendine barındırılan yapıt temizleme isteğe bağlıdır, her yapıt türü için ayrı yapılandırılabilir ve 30 günle sınırlı değildir. Desteklenen yapıt türleri ve dağıtım seçenekleri için <.localized_link href="/guides/server/self-host/server#artifact-retention">kendi kendine barındırılan yapıt saklama yapılandırmasına</.localized_link> bakın.

## Pano ve etkinlik verileri {#dashboard-and-activity-data}

Pano ve etkinlik kayıtları, yapıt dosyası temizlemesinden bağımsız saklama politikalarına sahiptir. Aşağıdaki zaman aralıkları, Enterprise dahil olmak üzere barındırılan plana göre değişmez.

### Xcode derleme ve test içgörüleri {#xcode-build-and-test-insights}

Temel Xcode derleme ve test kayıtlarında şu anda sabit bir zaman bazlı silme programı yoktur. Zaman çizelgesi adımları ve makine ölçümleri gibi diğer rapor verileri ayrı olarak sona erer:

| Veri | Saklama |
| --- | --- |
| Derleme özetleri, dosya başına ve hedef başına derleme kayıtları ve derleme sorunları | Sabit zaman bazlı silme programı yok |
| Test çalıştırmaları, modül ve paket sonuçları ve bireysel test sonuçları | Sabit zaman bazlı silme programı yok |
| Derleme zaman çizelgesi adımları ve yakalanan günlükleri | 90 gün |
| Derleme makinesi ölçümleri | 90 gün |
| Xcode proje grafiği kayıtları | 30 gün |

Bu kayıtlar, [yapıt dosyası saklama zaman aralıkları](#hosted-artifact-files) kapsamında ele alınan indirilebilir derleme arşivlerinden, sonuç paketlerinden ve test eklerinden ayrıdır. Enterprise planında bu dosyalar 30 gün saklanır; ilişkili derleme ve test kayıtları dosyaların süresi dolduktan sonra da kullanılmaya devam eder. Sabit bir zaman bazlı silme programına sahip olmayan bir kayıt, kalıcı kullanılabilirlik garantisi değildir.

### Diğer pano ve etkinlik verileri {#other-dashboard-and-activity-data}

Bazel indekslenmiş profil adımları, bir eylemle güvenle ilişkilendirilebildiğinde boş bırakılabilen eylem başına uzak kuyruk, giriş-getirme, yürütme ve çıktı-yükleme zamanlamalarını içerir. Bunlar, önbelleğe alınmış yapıtlardan ve faturalandırma kayıtlarından bağımsız olarak profilin 90 günlük saklama süresini paylaşır.

| Veri | Saklama |
| --- | --- |
| Gradle derleme kayıtları, görev kayıtları ve başarısız görevler ile yapılandırma adımlarının hata mesajları, önbellek olayı kayıtları, Mix derleme kayıtları, derlenmiş dosya kayıtları, derleme adımı kayıtları ve tanılama bilgileri, Cargo derleme kayıtları (toplu derleme-önbelleği ölçümleri dahil) ve derleyici gözlemleri, Bazel çağrıları, Bazel izleme profilleri, indekslenmiş profil adımları ve eylem tanılama bilgileri, bekleyen Bazel profil ve test alım kayıtları, Bazel çağrı günlükleri, Bazel uzak eylem-önbelleği gözlemleri ve uzaktan yürütülen eylemlerin kayıtları (komut, ortam, platform, çıkış kodu ve çıktılarının başlangıcı) | 90 gün |
| Bazel çağrılarının başlangıçları; bunlar tamamlanana kadar çalışıyor olarak listelenir | 2 gün |
| Kalıcı modül ayrıntı sayfalarında Xcode modül derlemesi ve önbellek geçmişi | 30 gün |
| Kalıcı ayrıntı sayfalarında görev, bildirilen Struo eylemi, Bazel BEP eylemi, derlenmiş dosya ve modül gözlemleri | 90 gün, yukarıdaki Xcode modülleri hariç |
| Kalıcı görev/eylem/modül/dosya kimlik meta verileri | Gözlem olmadan 365 gün |
| Runner iş günlükleri, arşivlenmiş runner günlükleri ve runner iş makine ölçümleri | 90 gün |
| Kod kapsamı satır ayrıntısı (her test çalıştırmasının satır başına ve fonksiyon başına kapsamı, bir dosyanın kapsam sayfasında gösterilir) | 31 gün |
| Her test çalıştırmasının kod kapsamı toplamları | 365 gün |
| Bir commit'in kod kapsamı (toplamları, hedefleri ve dosya başına değerleri) | 3 yıl; yalnızca bir pull request tarafından eklenen commit'ler için 90 gün |
| Webhook teslim geçmişi | Sabit silme programı yok |

Kalıcı ayrıntı URL'leri belirli bir derlemenin kullanılabilir kalmasına bağlı değildir. Kimlik meta verileri bireysel gözlemlerden daha uzun yaşayabilir, bu nedenle bir ayrıntı sayfasında seçilen dönemde geçmiş olmayabilir. Yeni geçmiş, özellik dağıtıldıktan sonra alınan raporlardan indekslenir; mevcut çalıştırma düzeyindeki geçmiş geriye dönük olarak kopyalanmaz.

ClickHouse'un dahili `system.*` operasyonel günlük tabloları, Tuist'in ürün veri saklama politikası yerine ClickHouse katmanında yapılandırılır. Varsayılan olarak sınırsızdırlar; birlikte sunulan kendi kendine barındırılan Docker Compose ve gömülü Helm ClickHouse yapılandırmaları bunları sınırlandırabilir; bu konu <.localized_link href="/guides/server/self-host/server#capping-operational-log-retention">operasyonel günlük saklamasının sınırlandırılması</.localized_link> bölümünde açıklanmıştır.
