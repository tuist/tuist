---
{
  "title": "Bazel önbelleği",
  "titleTemplate": ":title · Önbellek · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist ile Bazel uzak önbellek girdilerini ekibiniz ve CI arasında paylaşın."
}
---
# Bazel önbelleği {#bazel-cache}

Tuist, Bazel'in uzak önbellek olarak bağlandığı bir [Remote Execution API](https://github.com/bazelbuild/remote-apis) önbelleği sunar. Bir eylemin çıktıları zaten önbellekte bulunduğunda, Bazel eylemi atlar ve sonucu Tuist'in önbelliğinden çeker; bu sayede ekibiniz ve CI ortamlarınızda derleme süresinden tasarruf edersiniz. GitHub Actions kurulumu için bkz. [Bazel on GitHub Actions](https://tuist.dev/solutions/bazel-github-actions). Uzak önbellekleme işleyişi ve kendi kendine barındırılan ile yönetilen önbelleklerin karşılaştırması için bkz. [Bazel remote cache](https://tuist.dev/solutions/bazel-remote-cache).

## Kurulum {#setup}

Bazel çalışma alanının kök dizininden şunu çalıştırın:

```bash
tuist bazel setup
```

Bu işlem, en yakın Tuist önbellek bölgesine bağlı ve çalışma alanı başına kimlik bilgisi yardımcısı üzerinden kimlik doğrulaması yapan bir `.bazelrc.tuist` dosyasını `.bazelrc` dosyanızın yanına yazar. Ayrıca depounuzun `.bazelrc` dosyasına bir `try-import` satırı ekler:

```text
try-import %workspace%/.bazelrc.tuist
```

İçe aktarmayı kendiniz yönetmek istiyorsanız `--no-add-bazelrc-import` parametresini kullanın.

`.bazelrc.tuist` öğesini `.gitignore` dosyanıza ekleyin ve dosyayı depolamak yerine her makinede kurulumu çalıştırın. Oluşturulan dosya, geçerli kullanıcının Tuist yapılandırma dizini altındaki mutlak bir kimlik bilgisi yardımcısı yoluna ve dosyayı oluşturan makineye en yakın önbellek bölgesine işaret eder; bu nedenle hiçbir değer bir ekip arkadaşına veya sürekli entegrasyon çalıştırıcısına taşınmaz. Her makinede aynı olan `.bazelrc` içindeki `try-import` satırını depolayın.

Kurulum, bir Bazel çalışma alanı işaretçisi bulamadığında, dosya sembolik bir bağlantı olduğunda veya zaten bir uzak önbellek ya da Build Event Service yapılandırdığında mevcut `.bazelrc` dosyasına dokunmaz. Bu sayede tekrar çalıştırmak idempotent olur.

Entegrasyonu doğrulamak için normal bir Bazel komutu çalıştırın:

```bash
bazel build //...
```

Önbellek etkinliği daha sonra Tuist panosundaki projenin **Bazel Cache** sayfasında görünür; bu sayfa önbellek transferini, indirme ve yüklemeleri, okuma ve yazma gecikmesini, throughput'u ve eylem önbelleği isabet oranını gösterir. Proje **Overview** sayfası, derleme süresinin yanında aynı eylem önbelleği isabet oranının bir özetini içerir.

Bir komutun önbelleği nasıl kullandığını görmek için **Invocations** bölümünden açın. Çağrı sayfası, eylem önbelleği aramalarını içerik nesnesi isteklerinden ayırır; böylece soğuk bir eylem önbelleğini yavaş bir yapıt indirmesinden ayırt edebilirsiniz.

## Uzak yürütme {#remote-execution}

Tuist, Bazel eylemlerinizi Linux yürütücülerinde de çalıştırabilir; bu sayede önbellek isabetleri yerel makine veya CI çalıştırıcısı yerine uzaktan çalışır. Uzak yürütme, etkinleştirilmiş hesaplar için kullanılabilir; hesabınızda etkinleştirmek için [bize e-posta gönderin](mailto:contact@tuist.dev) veya [bir görüşme planlayın](https://cal.tuist.dev/team/tuist/tuist). Ardından kuruluma `--remote-execution` parametresini iletin:

```bash
tuist bazel setup --remote-execution
```

Kurulum daha sonra Bazel'i, uzak önbelleğin yanındaki `.bazelrc.tuist` içindeki Tuist yürütücüsüne yönlendirir. Her çalıştırmada geçerli yürütücüyü ve imajı sorgular; bu nedenle oluşturulan değerleri kopyalamak yerine kurulumu yeniden çalıştırın. Eylemler, makinenizde yüklü araçlar yerine yürütücünün Linux araç zinciriyle çalışır; bu nedenle eylemlerinizin ihtiyaç duyduğu araç zincirlerini çalışma alanında bildirin.

Kurulum ayrıca `--jobs` değerini, hesabınızın aynı anda çalıştırabileceği uzak eylem sayısının iki katına ayarlar; böylece her biri için sonraki eylem bekler. Bu olmadan, Bazel makinenin çekirdek sayısı kadar eylemi paralel çalıştırır ve 2 çekirdekli bir CI çalıştırıcısı yalnızca iki uzak eylemi havada tutar.

Farklı bir değer kullanmak için komut satırında `--jobs` parametresini iletin veya `.bazelrc` içinde `try-import` satırından sonra ayarlayın. Bazel okuduğu son değeri kullanır; bu nedenle o satırdan önce gelen bir `--jobs` değeri, oluşturulan değerle değiştirilir.

### Yürütücü boyutları {#executor-sizes}

Eylemler varsayılan olarak 4 GB bellek ve 2 vCPU kullanır. Daha büyük bir VM istemek için `tuist-memory-gb` yürütme özelliğini ayarlayın:

| `tuist-memory-gb` | Bellek | vCPU'lar | Çalışma alanı diski |
| --- | --- | --- | --- |
| `4` (varsayılan) | 4 GB | 2 | 30 GB |
| `8` | 8 GB | 4 | 30 GB |
| `16` | 16 GB | 8 | 30 GB |

Örneğin, varsayılan olarak 8 GB istemek için `.bazelrc` içindeki `try-import` satırından **sonra** şunu ekleyin:

```text
build --remote_default_exec_properties=tuist-memory-gb=8
```

Tek bir hedef için bunun yerine Bazel kuralında `exec_properties = {"tuist-memory-gb": "8"}` kullanın. Yalnızca `4`, `8` ve `16` desteklenir. Daha büyük eylemler, hesabın ayrılan vCPU ve bellek limitlerinin orantılı olarak daha fazlasını tüketir ve eşzamanlı çalıştırılabilecek eylem sayısını azaltır. Bir şekil her iki limite de uymalıdır. Oluşturulan `--jobs` varsayılan şekli kullanır; daha büyük şekiller isterken gerekirse bunu geçersiz kılın.

Yürütücüler şu anda Tuist'in Linux amd64 imajını kullanır. Keyfi konteyner imajları, diğer yürütme işletim sistemleri ve mimarileri, kalıcı eylem çalışanları ve kendi getirdiğiniz yürütücüler kurulum üzerinden yapılandırılamaz. Geçerli imajı ve uç noktayı elde etmek için kurulumu yeniden çalıştırın.

### Çalışan eylemler ve kullanım {#running-actions-and-usage}

Projenin **Remote execution** sayfası şu anda nelerin çalıştığını ve daha önce nelerin çalıştığını gösterir:

- **Invocations** öncelikle çalışan Bazel çağrılarını listeler; beş saniyede bir yenilenir ve her birinin ne kadar süredir çalıştığını ve kaç uzak eyleminin çalışmakta ve sıraya alındığını gösterir. Bir çağrı, Kura hedef desenlerine sahip olduğunda görünür ve tamamlanmış raporu gelene kadar kalır. Birini açtığınızda **Executions** bölümünü görürsünüz: bir VM'de yürütülen veya VM bekleyen uzak eylemler; her eylemin mnemonic'i, hedefi, makine boyutu ve mevcut durumundaki süresi. Yürütme ağ geçidinin önceden hazırladığı bir VM üzerinde çalıştırdığı eylemler çalışırken listelenmez; zamanlamaları çağrı tamamlandığında görünür. Listeyi ararken veya filtrelerken çalışan çağrılar gösterilmez.
- **Analytics**, seçilen dönem için **Executions** ve **Total execution time** ile başlar; önceki döneme göre değişiklikleri ve zaman içindeki grafiği gösterir. Toplam yürütme süresi, her eylemin yürütücüsünün VM'sinde ne kadar çalıştığını ifade eder; girdileri getirme ve çıktıları yükleme dahildir ancak sıraya alma veya VM hazırlama dahil değildir. **Usage** sayfasının faturalandırdığı süre budur. Önbellekten sunulan sonuçlar yürütme değildir.

Aynı verilere `GET /api/projects/{account_handle}/{project_handle}/remote-execution/activity` ve `GET /api/projects/{account_handle}/{project_handle}/remote-execution/usage` uç noktalarından (isteğe bağlı `from` ve `to`, varsayılan olarak son 30 gün ve en fazla 366 günü kapsar) ve `get_remote_execution_activity` ile `get_remote_execution_usage` MCP araçlarından erişilebilir.

### Uzak eylem zamanlamaları {#remote-action-timings}

**Analytics** bölümünün geri kalanı ve **Invocations** tablosu, kaydedilmiş uzak aşamalara sahip eylemleri kapsar: önceki döneme göre değişikliklerle birlikte ortalama ve p50/p90/p99 sıra ve yürütme süreleri, trend grafikleri ve her çağrının aşama zamanlamalarına bağlantılar. Tarihe göre filtreleyin (en fazla 90 gün). Çağrılar tablosu her çağrının ortalama, p50 ve p90 yürütme süresini gösterir. Komut, hedef veya çağrı kimliğine göre arama yapın; duruma, komuta, hedeflere veya uzak eylem sayısına göre filtreleyin ve Invocation dışındaki herhangi bir sütuna göre sıralayın. Arama ve tablo filtreleri yalnızca çağrılar tablosuna uygulanır, analitiklere değil.

Bir çağrının **Executions** bölümünü görmek için **Remote execution** sekmesini açın; burada uzak eylemler süreye (en uzun süreli ilk) veya başlangıç zamanına göre sıralanır: her uzak eylem için profildeki göreceli başlangıç zamanı, süresi ve sıra, girdi-getirme, yürütme ve çıktı-yükleme sürelerine bölünmüş, sayfada en uzun eyleme ölçeklenmiş bir çubuk bulunur. Her aşamanın süresini görmek için çubuğun üzerine gelin. Tablo yüklenen Bazel profillerini kullanır ve sunucu aşamalarını yalnızca aynı profil iş parçacığındaki belirsizliği olmayan bir eylemle ilişkilendirir.

Eksik zamanlamalar **Not recorded** anlamına gelir, sıfır değil. Eski profiller, eksik eylem aralıkları ve Bazel tarafından atlanan kısa aşamalar, uzak iş gerçekleşmiş olsa bile tabloyu boş bırakabilir. Kaydedilen yeniden denemeler her eylem içinde toplanır. Sunucu meta verileri önbelleğe alınmış bir sonucu tanımlayabilir, bu nedenle bu zamanlamalar ne yeni bir yürütmenin kanıtıdır ne de faturalandırılabilir kullanım. İstemci girdi yüklemeleri ve yerel olarak yürütülen çıktıların yüklemeleri çıktı-yükleme süresinden hariçtir.

Aynı verilere `remote_execution=true` parametresiyle build-step REST uç noktasından ve `list_bazel_build_steps` / `get_bazel_build_step` MCP araçlarından erişilebilir. Zamanlamalar, profil adımlarıyla birlikte 90 gün boyunca saklanır.

## Build insights {#build-insights}

Varsayılan olarak `tuist bazel setup`, tamamlanan komutların **Invocations** panosunda görünmesi için Bazel'in Build Event Service'ini de yapılandırır. Panonun neler gösterdiğini ve özel meta verilerin nasıl ekleneceğini öğrenmek için <.localized_link href="/guides/features/build-insights/bazel">Bazel build insights</.localized_link> bölümüne bakın.

Yalnızca uzak önbelleği istiyorsanız ve build-event akışını göndermek istemiyorsanız, şu şekilde devre dışı bırakın:

```bash
tuist bazel setup --no-build-insights
```

## Continuous integration {#continuous-integration}

CI'yı <.localized_link href="/guides/server/authentication#continuous-integration">Authentication guide</.localized_link> bölümündeki yöntemlerden biriyle kimlik doğrulayın, ardından `.bazelrc.tuist` çalışanın doğru bölgesini yansıtması için checkout adımının bir parçası olarak `tuist bazel setup` komutunu bir kez çalıştırın. Sağlayıcıya özel örnekler için <.localized_link href="/guides/integrations/continuous-integration">Continuous Integration guide</.localized_link> bölümüne bakın.

## Data retention {#data-retention}

Tuist, uzak önbellek gözlemlerini 90 gün boyunca saklar. Tam politika için <.localized_link href="/guides/server/data-retention">data retention</.localized_link> bölümüne bakın.
