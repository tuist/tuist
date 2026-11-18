---
{
  "title": "Bazel önbelleği",
  "titleTemplate": ":title · Önbellek · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist ile Bazel uzak önbellek girdilerini ekibiniz ve CI arasında paylaşın."
}
---
# Bazel önbelleği {#bazel-cache}

Tuist, Bazel'in uzak önbellek olarak bağlandığı bir [Remote Execution API](https://github.com/bazelbuild/remote-apis) önbelleği sunar. Bir eylemin çıktıları zaten önbellekte olduğunda, Bazel eylemi atlar ve sonucu Tuist'in önbelleğinden çeker; bu da ekibiniz ve CI ortamlarınızda derleme süresini azaltır. GitHub Actions kurulumu için [Bazel on GitHub Actions](https://tuist.dev/solutions/bazel-github-actions) sayfasına bakın. Uzak önbellekleme mekanizması ve kendi sunucunuzda barındırılan ile yönetilen önbelleklerin karşılaştırması için [Bazel remote cache](https://tuist.dev/solutions/bazel-remote-cache) sayfasına bakın.

## Kurulum {#setup}

Bazel çalışma alanının kök dizininde şunu çalıştırın:

```bash
tuist bazel setup
```

Bu işlem, en yakın Tuist önbellek bölgesine yönlendirilmiş ve çalışma alanı başına kimlik bilgisi yardımcısı üzerinden kimlik doğrulaması yapan bir `.bazelrc.tuist` dosyasını `.bazelrc` dosyanızın yanına yazar. Ayrıca deponuzun `.bazelrc` dosyasına bir `try-import` satırı ekler:

```text
try-import %workspace%/.bazelrc.tuist
```

İçe aktarmayı kendiniz yönetmek istiyorsanız `--no-add-bazelrc-import` seçeneğini iletin.

`.bazelrc.tuist` dosyasını `.gitignore` dosyanıza ekleyin ve bunu depolamak yerine her makinede kurulumu çalıştırın. Oluşturulan dosya, geçerli kullanıcının Tuist yapılandırma dizini altındaki mutlak bir kimlik bilgisi yardımcısı yoluna ve dosyayı oluşturan makineye en yakın önbellek bölgesine işaret eder; bu nedenle hiçbir değer bir ekip arkadaşına veya sürekli entegrasyon çalıştırıcısına aktarılmaz. Her makinede aynı olan `.bazelrc` içindeki `try-import` satırını depolayın.

Kurulum, bir Bazel çalışma alanı işaretçisi bulamadığında, dosya sembolik bir bağlantı olduğunda veya zaten bir uzak önbellek ya da Build Event Service yapılandırdığında mevcut `.bazelrc` dosyasına dokunmaz. Bu sayede tekrar çalıştırmak idempotent olur.

Entegrasyonu doğrulamak için normal bir Bazel komutu çalıştırın:

```bash
bazel build //...
```

Önbellek etkinliği daha sonra Tuist panosundaki projenin **Bazel Cache** sayfasında görünür; bu sayfa önbellek transferini, indirme ve yüklemeleri, okuma ve yazma gecikmesini, verimliliği ve eylem önbelleği isabet oranını gösterir. Proje **Overview** sayfası, derleme süresinin yanında aynı eylem önbelleği isabet oranının bir özetini içerir.

Bir komutun önbelleği nasıl kullandığını görmek için **Invocations** bölümünden açın. Çağrı sayfası, eylem önbelleği aramalarını içerik nesnesi isteklerinden ayırır; böylece soğuk bir eylem önbelleğini yavaş bir yapıt indirmesinden ayırt edebilirsiniz.

## Uzak yürütme {#remote-execution}

Tuist, Bazel eylemlerinizi Linux çalıştırıcılarında da çalıştırabilir; böylece önbellek isabetsizlikleri yerel makine veya CI çalıştırıcısında değil, uzaktan çalışır. Uzak yürütme, etkinleştirilmiş hesaplar için kullanılabilir; hesabınızda etkinleştirmek için [bize e-posta gönderin](mailto:contact@tuist.dev) veya [bir görüşme planlayın](https://cal.tuist.dev/team/tuist/tuist). Ardından kuruluma `--remote-execution` seçeneğini iletin:

```bash
tuist bazel setup --remote-execution
```

Kurulum daha sonra Bazel'i, uzak önbelleğin yanındaki `.bazelrc.tuist` içindeki Tuist çalıştırıcısına yönlendirir. Her çalıştırıldığında geçerli çalıştırıcıyı ve imajı sorgular; bu nedenle oluşturulan değerleri kopyalamak yerine kurulumu yeniden çalıştırın. Eylemler, makinenizde yüklü araçlar yerine çalıştırıcının Linux araç zinciriyle çalışır; bu nedenle eylemlerinizin ihtiyaç duyduğu araç zincirlerini çalışma alanında tanımlayın.

Kurulum ayrıca `--jobs` değerini, hesabınızın aynı anda çalıştırabileceği uzak eylem sayısının iki katına ayarlar; böylece her biri için sonraki eylem bekler. Bunun olmaması durumunda, Bazel makinedeki çekirdek sayısı kadar eylemi paralel çalıştırır ve 2 çekirdekli bir CI çalıştırıcısı yalnızca iki uzak eylemi aktif tutar.

Farklı bir değer kullanmak için komut satırında `--jobs` seçeneğini iletin veya `try-import` satırından sonra `.bazelrc` içinde ayarlayın. Bazel okuduğu son değeri kullanır; bu nedenle o satırdan önce gelen bir `--jobs`, oluşturulan değerle değiştirilir.

### Çalıştırıcı boyutları {#executor-sizes}

Eylemler varsayılan olarak 4 GB bellek ve 2 vCPU kullanır. Daha büyük bir VM istemek için `tuist-memory-gb` yürütme özelliğini ayarlayın:

| `tuist-memory-gb` | Bellek | vCPU | Çalışma alanı diski |
| --- | --- | --- | --- |
| `4` (varsayılan) | 4 GB | 2 | 30 GB |
| `8` | 8 GB | 4 | 30 GB |
| `16` | 16 GB | 8 | 30 GB |

Örneğin, varsayılan olarak 8 GB istemek için `.bazelrc` içindeki `try-import` satırından **sonra** şunu ekleyin:

```text
build --remote_default_exec_properties=tuist-memory-gb=8
```

Tek bir hedef için bunun yerine Bazel kuralında `exec_properties = {"tuist-memory-gb": "8"}` kullanın. Yalnızca `4`, `8` ve `16` desteklenir. Daha büyük eylemler, hesabın ayrılan vCPU ve bellek sınırlarından orantılı olarak daha fazlasını tüketir ve eşzamanlı çalıştırılabilecek eylem sayısını azaltır. Bir şekil her iki sınıra da uymalıdır. Oluşturulan `--jobs` varsayılan şekli kullanır; daha büyük şekiller isterken gerekirse bunu geçersiz kılın.

Çalıştırıcılar şu anda Tuist'in Linux amd64 imajını kullanır. Keyfi konteyner imajları, diğer yürütme işletim sistemleri ve mimarileri, kalıcı eylem çalışanları ve kendi çalıştırıcınızı getirme seçenekleri kurulum aracılığıyla yapılandırılamaz. Geçerli imajı ve uç noktayı elde etmek için kurulumu yeniden çalıştırın.

### Uzak eylem zamanlamaları {#remote-action-timings}

Kaydedilmiş uzak aşamalara sahip çağrıları ve eylemleri, ortalama ve p50/p90/p99 kuyruk ve yürütme sürelerini önceki döneme göre değişikliklerle, trend grafiklerini ve her çağrının aşama zamanlamalarına bağlantıları görmek için proje kenar çubuğunda **Remote execution** bölümünü açın. Ortama (CI veya yerel) ve tarihe (90 güne kadar) göre filtreleyin. Çağrılar tablosu her çağrının ortalama, p50 ve p90 yürütme süresini gösterir. Komuta, hedefe veya çağrı kimliğine göre arama yapın; duruma, komuta, hedeflere veya uzak eylem sayısına göre filtreleyin ve Invocation dışındaki herhangi bir sütuna göre sıralayın. Arama ve tablo filtreleri yalnızca çağrılar tablosuna uygulanır, analitiklere değil.

Uzak eylemlerini görmek için bir çağrının **Remote execution** sekmesini açın; süre (en uzun ilk sırada) veya başlangıç zamanına göre sıralanır: profil göre ne zaman başladığı, süresi ve kuyruk, girdi-getirme, yürütme ve çıktı-yükleme sürelerine bölünmüş, sayfadaki en uzun eyleme ölçeklendirilmiş bir çubuk içeren her uzak eylem için bir satır. Her aşamanın süresini görmek için çubuğun üzerine gelin. Tablo, yüklenen Bazel profillerini kullanır ve sunucu aşamalarını yalnızca aynı profil iş parçacığındaki belirsiz olmayan bir eylemle ilişkilendirir.

Eksik zamanlamalar sıfır değil, **Not recorded** anlamına gelir. Daha eski profiller, eksik eylem aralıkları ve Bazel tarafından atlanan kısa aşamalar, uzak iş gerçekleşse bile tabloyu boş bırakabilir. Kaydedilen yeniden denemeler her eylem içinde toplanır. Sunucu meta verileri önbelleğe alınmış bir sonucu açıklayabilir; bu nedenle bu zamanlamalar yeni yürütmenin kanıtı değildir ve faturalandırılabilir kullanım değildir. İstemci girdi yüklemeleri ve yerel olarak yürütülen çıktıların yüklemeleri çıktı-yükleme süresinden hariçtir.

Aynı verilere `remote_execution=true` ile build-step REST uç noktasından ve `list_bazel_build_steps` / `get_bazel_build_step` MCP araçlarından erişilebilir. Zamanlamalar, profil adımlarıyla birlikte 90 gün boyunca saklanır.

## Derleme içgörüler {#build-insights}

Varsayılan olarak, `tuist bazel setup` Bazel'in Build Event Service'ini de yapılandırır; böylece tamamlanan komutlar **Invocations** panosunda görünür. Panonun neler gösterdiği ve özel meta verilerin nasıl ekleneceği için <.localized_link href="/guides/features/build-insights/bazel">Bazel build insights</.localized_link> bölümüne bakın.

Yalnızca uzak önbelleği kullanmak istiyor ve derleme olayı akışını göndermek istemiyorsanız, şu şekilde devre dışı bırakın:

```bash
tuist bazel setup --no-build-insights
```

## Sürekli entegrasyon {#continuous-integration}

CI'yi <.localized_link href="/guides/server/authentication#continuous-integration">Authentication guide</.localized_link> içindeki yöntemlerden biriyle kimlik doğrulayın, ardından `.bazelrc.tuist` çalışanın bulunduğu bölgeyi doğru yansıtması için checkout adımı kapsamında `tuist bazel setup` komutunu bir kez çalıştırın. Sağlayıcıya özel örnekler için <.localized_link href="/guides/integrations/continuous-integration">Continuous Integration guide</.localized_link> bölümüne bakın.

## Veri saklama {#data-retention}

Tuist, uzak önbellek gözlemlerini 90 gün boyunca saklar. Tam politika için <.localized_link href="/guides/server/data-retention">data retention</.localized_link> bölümüne bakın.
