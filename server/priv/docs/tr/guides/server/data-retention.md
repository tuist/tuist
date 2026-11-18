---
{
  "title": "Veri saklama",
  "titleTemplate": ":title | Server | Kılavuzlar | Tuist",
  "description": "Tuist'in indirilebilir yapıtları ve pano etkinlik verilerini ne kadar süreyle sakladığını öğrenin."
}
---
# Veri saklama {#data-retention}

Tuist, yüklenen yapıt dosyaları ile panolar ve içgörüler için kullanılan kayıtlara ayrı saklama politikaları uygular. Süresi dolmuş bir yapıt dosyasının silinmesi, ona ilişkin içgörü kayıtlarını silmez.

Yapıt dosyaları için barındırılan Tuist sunucusu, 30 günle sınırlı plana dayalı zaman aralıkları kullanır. Kendi altyapınızda barındırılan örneklerde yapıt temizliği varsayılan olarak devre dışıdır; operatörler bu özelliği etkinleştirip desteklenen her yapıt türü için ayrı bir zaman aralığı yapılandırabilir.

## Yapıt dosyaları {#artifact-files}

### Barındırılan Tuist sunucusu {#hosted-artifact-files}

Bu zaman aralıkları, yapıt dosyalarının barındırılan Tuist sunucusunda ne kadar süreyle kullanılabilir durumda kalacağını belirler.

| Yapıt | Air ve Açık Kaynak | Pro | Enterprise |
| --- | --- | --- | --- |
| Önbellek yapıtları; Xcode önbelleği, modül önbelleği, Gradle önbelleği, Bazel uzak önbellek dosyaları ve Tuist Runners’dan gelen GitLab CI önbellek arşivleri dahil | 14 gün | 30 gün | 30 gün |
| Uygulama önizleme derlemeleri ve simgeler | 30 gün | 30 gün | 30 gün |
| Derleme arşivleri | 7 gün | 30 gün | 30 gün |
| Çalıştırma yapıtları; sonuç paketleri ve oturum arşivleri dahil | 7 gün | 30 gün | 30 gün |
| Test çalıştırması ekleri | 30 gün | 30 gün | 30 gün |
| Parça paketleri | 7 gün | 14 gün | 30 gün |

Etkin hesap planı, barındırılan saklama zaman aralığını belirler. Bir hesabın etkin aboneliği yoksa Tuist Air saklama zaman aralığını kullanır. Bazı yapıt türleri yeniden oluşturulmaları beklendiği için daha kısa zaman aralıkları kullanır.

Tuist bir test çalıştırması tanımlayıcısını kaydetmeden önce oluşturulan test ekleri otomatik silme kapsamı dışındadır. Dosyaları, Tuist saklama temizliği sırasında sınırsız tarihsel sahiplik sorgusundan kaçınırken kullanılmaya devam eder.

### Kendi altyapınızda barındırılan örnekler {#self-hosted-artifact-files}

Kendi altyapınızda barındırılan yapıt temizliği isteğe bağlıdır, her yapıt türü için ayrı yapılandırılabilir ve 30 günle sınırlı değildir. Desteklenen yapıt türleri ve dağıtım seçenekleri için <.localized_link href="/guides/server/self-host/server#artifact-retention">kendi altyapınızda barındırılan yapıt saklama yapılandırmasına</.localized_link> bakın.

## Pano ve etkinlik verileri {#dashboard-and-activity-data}

Pano ve etkinlik kayıtları, yapıt dosyası temizliğinden bağımsız saklama politikalarına sahiptir. Aşağıdaki zaman aralıkları, Enterprise dahil olmak üzere barındırılan plana göre değişmez.

### Xcode derleme ve test içgörüleri {#xcode-build-and-test-insights}

Temel Xcode derleme ve test kayıtlarının şu anda sabit bir zamana dayalı silme programı yoktur. Zaman çizelgesi adımları ve makine metrikleri gibi diğer rapor verileri ayrı olarak sona erer:

| Veri | Saklama |
| --- | --- |
| Derleme özetleri, dosya başına ve hedef başına derleme kayıtları ve derleme sorunları | Sabit zamana dayalı silme programı yok |
| Test çalıştırmaları, modül ve paket sonuçları ve bireysel test sonuçları | Sabit zamana dayalı silme programı yok |
| Derleme zaman çizelgesi adımları ve yakalanan günlükleri | 90 gün |
| Derleme makinesi metrikleri | 90 gün |
| Xcode proje grafiği kayıtları | 30 gün |

Bu kayıtlar, [yapıt dosyası saklama zaman aralıkları](#hosted-artifact-files) kapsamında ele alınan indirilebilir derleme arşivlerinden, sonuç paketlerinden ve test eklerinden bağımsızdır. Enterprise planında bu dosyalar 30 gün saklanır; ilgili derleme ve test kayıtları dosyaların süresi dolduktan sonra da kullanılmaya devam eder. Sabit bir zamana dayalı silme programına sahip olmaması, bir kaydın kalıcı olarak kullanılabilir olacağının garantisi değildir.

### Diğer pano ve etkinlik verileri {#other-dashboard-and-activity-data}

| Veri | Saklama |
| --- | --- |
| Gradle derleme kayıtları, görev kayıtları, önbellek olayı kayıtları, Mix derleme kayıtları, derlenmiş dosya kayıtları, derleme adımı kayıtları ve tanılama bilgileri, Cargo derleme kayıtları (toplu derleme önbelleği ölçümleri dahil) ve derleyici gözlemleri, Bazel çağrıları, Bazel izleme profilleri, indekslenmiş profil adımları ve eylem tanılama bilgileri, bekleyen Bazel profili ve test alım kayıtları, Bazel çağrı günlükleri ve Bazel uzak eylem önbelleği gözlemleri | 90 gün |
| Kalıcı modül detay sayfalarında Xcode modül derleme ve önbellek geçmişi | 30 gün |
| Görev, bildirilmiş Once eylemi, Bazel BEP eylemi, derlenmiş dosya ve modül gözlemleri kalıcı detay sayfalarında | 90 gün, yukarıdaki Xcode modülleri hariç |
| Kalıcı görev/eylem/modül/dosya kimlik meta verileri | Gözlem olmadan 365 gün |
| Runner iş günlükleri, arşivlenmiş runner günlükleri ve runner iş makine metrikleri | 90 gün |
| Webhook teslim geçmişi | Sabit silme programı yok |

Kalıcı detay URL’leri belirli bir derlemenin kullanılabilir kalmasına bağlı değildir. Kimlik meta verileri bireysel gözlemlerden daha uzun süre yaşayabilir, bu nedenle bir detay sayfası seçilen dönemde geçmiş içermeyebilir. Yeni geçmiş, özellik dağıtıldıktan sonra alınan raporlardan indekslenir; mevcut çalıştırma düzeyindeki geçmiş geriye dönük olarak kopyalanmaz.

ClickHouse’un dahili `system.*` operasyonel günlük tabloları, Tuist’in ürün veri saklama politikası yerine ClickHouse katmanında yapılandırılır. Varsayılan olarak sınırsızdırlar; birlikte sunulan kendi altyapınızda barındırılan Docker Compose ve gömülü Helm ClickHouse yapılandırmaları bunları sınırlayabilir; ayrıntılar için <.localized_link href="/guides/server/self-host/server#capping-operational-log-retention">operasyonel günlük saklamasını sınırlama</.localized_link> bölümüne bakın.
