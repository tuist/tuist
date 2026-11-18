---
{
  "title": "Bazel önbelleği",
  "titleTemplate": ":title · Önbellek · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist ile Bazel uzak önbellek girdilerini ekibiniz ve CI arasında paylaşın."
}
---
# Bazel önbelleği {#bazel-cache}

Tuist, Bazel'in uzak önbellek olarak bağlandığı bir [Remote Execution API](https://github.com/bazelbuild/remote-apis) önbelleği sunar. Bir eylemin çıktıları zaten önbellekteyse, Bazel eylemi atlar ve sonucu Tuist'in önbelleğinden çeker; bu da ekibiniz ve CI ortamlarınızda derleme süresini azaltır. GitHub Actions kurulumu için bkz. [Bazel on GitHub Actions](https://tuist.dev/solutions/bazel-github-actions). Uzak önbellekleme mekanizması ve kendi sunucunuzda barındırılan ile yönetilen önbelleklerin karşılaştırması için bkz. [Bazel remote cache](https://tuist.dev/solutions/bazel-remote-cache).

## Kurulum {#setup}

Bazel çalışma alanının kök dizininden şunu çalıştırın:

```bash
tuist bazel setup
```

Bu işlem, en yakın Tuist önbellek bölgesine bağlı ve çalışma alanı başına kimlik bilgisi yardımcısı üzerinden kimlik doğrulaması yapan bir `.bazelrc.tuist` dosyasını `.bazelrc` dosyanızın yanına yazar. Ayrıca deponuzun `.bazelrc` dosyasına bir `try-import` satırı ekler:

```text
try-import %workspace%/.bazelrc.tuist
```

İçe aktarmayı kendiniz yönetmek istiyorsanız `--no-add-bazelrc-import` parametresini kullanın.

`.bazelrc.tuist` dosyasını `.gitignore` dosyanıza ekleyin ve onu commitlemek yerine her makinede kurulumu çalıştırın. Oluşturulan dosya, mevcut kullanıcının Tuist yapılandırma dizini altındaki mutlak bir kimlik bilgisi yardımcısı yoluna ve onu oluşturan makineye en yakın önbellek bölgesine işaret eder; bu nedenle hiçbir değer bir ekip arkadaşına veya sürekli entegrasyon çalıştırıcısına aktarılmaz. Her makinede aynı olan `.bazelrc` içindeki `try-import` satırını commit edin.

Kurulum, bir Bazel çalışma alanı işaretçisi bulamadığında, dosya sembolik bir bağlantı olduğunda veya zaten bir uzak önbellek ya da Build Event Service yapılandırdığında mevcut `.bazelrc` dosyasına dokunmaz. Bu sayede tekrar çalıştırmak idempotent olur.

Entegrasyonu doğrulamak için normal bir Bazel komutu çalıştırın:

```bash
bazel build //...
```

Önbellek etkinliği daha sonra Tuist kontrol panelindeki projenin **Bazel Cache** sayfasında görünür; bu sayfa önbellek transferini, indirme ve yüklemeleri, okuma ve yazma gecikmesini, throughput'u ve eylem önbelleği isabet oranını gösterir. Proje **Overview** sayfası, derleme süresinin yanında aynı eylem önbelleği isabet oranının bir özetini içerir.

Bir komutun önbelleği nasıl kullandığını görmek için **Invocations** bölümünden açın. Çağrı sayfası, eylem önbelleği aramalarını içerik nesnesi isteklerinden ayırır; böylece soğuk bir eylem önbelleğini yavaş bir yapıt indirmesinden ayırt edebilirsiniz.

## Uzak yürütme {#remote-execution}

Tuist, Bazel eylemlerinizi Linux çalıştırıcılarında da çalıştırabilir; böylece önbellek isabetleri yerel makine veya CI çalıştırıcısı yerine uzaktan çalışır. Uzak yürütme, etkinleştirilmiş hesaplar için kullanılabilir; hesabınızda etkinleştirmek için [bize e-posta gönderin](mailto:contact@tuist.dev) veya [bir görüşme planlayın](https://cal.tuist.dev/team/tuist/tuist). Ardından kuruluma `--remote-execution` parametresini geçin:

```bash
tuist bazel setup --remote-execution
```

Kurulum, Bazel'i uzak önbelleğin yanındaki `.bazelrc.tuist` içindeki Tuist çalıştırıcısına yönlendirir. Her çalıştığında mevcut çalıştırıcıyı ve imajı sorgular; bu nedenle oluşturulan değerleri kopyalamak yerine kurulumu yeniden çalıştırın. Eylemler, makinenizde yüklü araçlar değil, çalıştırıcının Linux araç zinciri ile çalışır; bu nedenle eylemlerinizin ihtiyaç duyduğu araç zincirlerini çalışma alanında tanımlayın.

Kurulum ayrıca `--jobs` değerini, hesabınızın aynı anda çalıştırabileceği uzak eylem sayısının iki katına ayarlar; böylece her biri için sonraki eylem bekler. Bu olmadan, Bazel makinenin çekirdek sayısı kadar eylemi paralel çalıştırır ve 2 çekirdekli bir CI çalıştırıcısı yalnızca iki uzak eylemi aktif tutar.

Farklı bir değer kullanmak için komut satırında `--jobs` parametresini geçin veya `try-import` satırından sonra `.bazelrc` içinde ayarlayın. Bazel okuduğu son değeri kullanır; bu nedenle o satırdan önce gelen bir `--jobs`, oluşturulan değerle değiştirilir.

### Çalıştırıcı boyutları {#executor-sizes}

Eylemler varsayılan olarak 4 GB bellek ve 2 vCPU kullanır. Daha büyük bir VM istemek için `tuist-memory-gb` yürütme özelliğini ayarlayın:

| `tuist-memory-gb` | Bellek | vCPU | Çalışma alanı diski |
| --- | --- | --- | --- |
| `4` (varsayılan) | 4 GB | 2 | 30 GB |
| `8` | 8 GB | 4 | 30 GB |
| `16` | 16 GB | 8 | 30 GB |

Örneğin, varsayılan olarak 8 GB istemek için bunu `.bazelrc` içindeki `try-import` satırından **sonra** ekleyin:

```text
build --remote_default_exec_properties=tuist-memory-gb=8
```

Tek bir hedef için bunun yerine Bazel kuralında `exec_properties = {"tuist-memory-gb": "8"}` kullanın. Yalnızca `4`, `8` ve `16` desteklenir. Daha büyük eylemler, hesabın ayrılan vCPU ve bellek limitlerinin orantılı olarak daha fazlasını tüketir ve eşzamanlı çalıştırılabilecek sayıyı azaltır. Bir şekil her iki limite de uymalıdır. Oluşturulan `--jobs`, varsayılan şekli kullanır; daha büyük şekiller isterken gerekirse bunu geçersiz kılın.

Çalıştırıcılar şu anda Tuist'in Linux amd64 imajını kullanır. Keyfi konteyner imajları, diğer yürütme işletim sistemleri ve mimarileri, kalıcı eylem çalışanları ve kendi çalıştırıcınızı getirme seçeneği kurulum üzerinden yapılandırılamaz. Mevcut imajı ve uç noktayı elde etmek için kurulumu yeniden çalıştırın.

### Çalışan eylemler ve kullanım {#running-actions-and-usage}

Projenin **Remote execution** sayfası şu anda nelerin çalıştığını ve daha önce nelerin çalıştığını gösterir:

- **Invocations**, her beş saniyede bir yenilenen, her birinin ne kadar süredir çalıştığını ve kaç uzak eyleminin çalışmakta veya kuyrukta olduğunu gösteren çalışan Bazel çağrılarını öncelikle listeler. Kura hedef desenlerine sahip olduğunda bir çağrı görünür ve tamamlanmış raporu gelene kadar kalır. Birini açmak, onun **Executions** listesini gösterir: bir VM'de yürütülen veya biri için bekleyen uzak eylemler, her eylemin mnemoniği, hedefi, makine boyutu ve mevcut durumundaki süresi ile birlikte. Yürütme ağ geçidinin önceden hazırladığı bir VM üzerinde çalıştırdığı eylemler çalışırken listelenmez; zamanlamaları çağrı tamamlandığında görünür. Listeyi ararken veya filtrelerken çalışan çağrılar gösterilmez.
- **Analytics**, seçilen dönem için **Executions** ve **Total execution time** ile başlar; önceki döneme göre değişiklikler makine boyutuna göre grafiklendirilir. Toplam yürütme süresi, her eylemin çalıştırıcısının VM'sinde ne kadar çalıştığıdır; girdileri getirme ve çıktıları yükleme dahildir ancak kuyruğa alma veya VM hazırlama dahil değildir. Bu, **Usage** sayfasının faturalandırdığı süredir. Önbellekten sunulan sonuçlar yürütme değildir.

Aynı verilere `GET /api/projects/{account_handle}/{project_handle}/remote-execution/activity` ve `GET /api/projects/{account_handle}/{project_handle}/remote-execution/usage` üzerinden (isteğe bağlı `from` ve `to`, varsayılan olarak son 30 gün ve en fazla 366 günü kapsar) ve `get_remote_execution_activity` ile `get_remote_execution_usage` MCP araçlarından erişilebilir.

### Uzak eylem zamanlamaları {#remote-action-timings}

**Analytics** bölümünün geri kalanı ve **Invocations** tablosu, kaydedilmiş uzak aşamaları olan eylemleri kapsar: önceki döneme göre değişikliklerle birlikte ortalama ve p50/p90/p99 kuyruk ve yürütme süreleri, trend grafikleri ve her çağrının aşama zamanlamalarına bağlantılar. Tarihe göre filtreleyin (en fazla 90 gün). Çağrılar tablosu her çağrının ortalama, p50 ve p90 yürütme süresini gösterir. Komut, hedef veya çağrı kimliğine göre arama yapın; duruma, komuta, hedeflere veya uzak eylem sayısına göre filtreleyin ve Invocation dışındaki herhangi bir sütuna göre sıralayın. Arama ve tablo filtreleri yalnızca çağrılar tablosuna uygulanır, analitiklere değil.

Bir çağrının **Executions** listesini görmek için **Remote execution** sekmesini açın; uzak eylemler süreye (en uzun süreli önce) veya başlangıç zamanına göre sıralanır: her uzak eylem için bir satır, profile göre ne zaman başladığı, süresi ve kuyruk, girdi-getirme, yürütme ve çıktı-yükleme sürelerine bölünmüş, sayfada en uzun eyleme ölçeklenmiş bir çubuk bulunur. Her aşamanın süresini görmek için çubuğun üzerine gelin. Tablo yüklenen Bazel profillerini kullanır ve sunucu aşamalarını yalnızca aynı profil iş parçacığındaki belirsizliği olmayan bir eylemle ilişkilendirir.

Eksik zamanlamalar sıfır değil, **Not recorded** anlamına gelir. Daha eski profiller, eksik eylem aralıkları ve Bazel tarafından atlanan kısa aşamalar, uzak iş gerçekleşmiş olsa bile tabloyu boş bırakabilir. Kaydedilen yeniden denemeler her eylem içinde toplanır. Sunucu meta verileri önbelleğe alınmış bir sonucu tanımlayabilir, bu nedenle bu zamanlamalar yeni bir yürütmenin kanıtı değildir ve faturalandırılabilir kullanım değildir. İstemci girdi yüklemeleri ve yerel olarak yürütülen çıktıların yüklemeleri çıktı-yükleme süresinden hariçtir.

Aynı verilere `remote_execution=true` ile yapı adımı REST uç noktasından ve `list_bazel_build_steps` / `get_bazel_build_step` MCP araçlarından erişilebilir. Zamanlamalar, profil adımlarıyla birlikte 90 gün boyunca saklanır.

## Yapı içgörüleri {#build-insights}

Varsayılan olarak, `tuist bazel setup` ayrıca Bazel'in Build Event Service'ini yapılandırır, böylece tamamlanan komutlar **Invocations** panosunda görünür. Panonun neler gösterdiği ve özel meta verilerin nasıl ekleneceği için bkz. <.localized_link href="/guides/features/build-insights/bazel">Bazel build insights</.localized_link>.

Yalnızca uzak önbelleği istiyorsanız ve yapı olayı akışını göndermek istemiyorsanız, şu şekilde devre dışı bırakın:

```bash
tuist bazel setup --no-build-insights
```

## Sürekli entegrasyon {#continuous-integration}

CI'yi <.localized_link href="/guides/server/authentication#continuous-integration">Authentication guide</.localized_link> içindeki yöntemlerden biriyle kimlik doğrulayın, ardından `.bazelrc.tuist` çalıştırıcısı için doğru bölgeyi yansıtması amacıyla checkout adımının bir parçası olarak `tuist bazel setup` komutunu bir kez çalıştırın. Sağlayıcıya özel örnekler için bkz. <.localized_link href="/guides/integrations/continuous-integration">Continuous Integration guide</.localized_link>.

## Veri saklama {#data-retention}

Tuist, uzak önbellek gözlemlerini 90 gün boyunca saklar. Tam politika için bkz. <.localized_link href="/guides/server/data-retention">data retention</.localized_link>.
