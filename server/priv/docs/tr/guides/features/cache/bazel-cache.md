---
{
  "title": "Bazel önbelleği",
  "titleTemplate": ":title · Önbellek · Özellikler · Kılavuzlar · Tuist",
  "description": "Bazel uzak önbellek girdilerini Tuist ile ekibiniz ve CI arasında paylaşın."
}
---
# Bazel önbelleği {#bazel-cache}

Tuist, Bazel'in uzak önbellek olarak bağlandığı bir [Remote Execution API](https://github.com/bazelbuild/remote-apis) önbelleği sunar. Bir eylemin çıktıları zaten önbellekte bulunduğunda, Bazel eylemi atlar ve sonucu Tuist'in önbelleğinden çeker; bu sayede ekibiniz ve CI ortamlarınızda derleme süresinden tasarruf edersiniz. GitHub Actions kurulumu için bkz. [Bazel on GitHub Actions](https://tuist.dev/solutions/bazel-github-actions). Uzak önbellekleme işleyişi ve kendi sunucunuzda barındırılan ile yönetilen önbelleklerin karşılaştırması hakkında bilgi için bkz. [Bazel remote cache](https://tuist.dev/solutions/bazel-remote-cache).

## Kurulum {#setup}

Bazel çalışma alanının kök dizininden şunu çalıştırın:

```bash
tuist bazel setup
```

Bu işlem, en yakın Tuist önbellek bölgesine bağlı ve çalışma alanı başına kimlik bilgisi yardımcısı aracılığıyla kimlik doğrulaması yapan bir `.bazelrc.tuist` dosyasını `.bazelrc` dosyanızın yanına yazar. Ayrıca deponuzun `.bazelrc` dosyasına bir `try-import` satırı ekler:

```text
try-import %workspace%/.bazelrc.tuist
```

İçe aktarmayı kendiniz yönetmek istiyorsanız `--no-add-bazelrc-import` seçeneğini kullanın.

`.bazelrc.tuist` öğesini `.gitignore` dosyanıza ekleyin ve dosyayı commit etmek yerine her makinede kurulumu çalıştırın. Oluşturulan dosya, geçerli kullanıcının Tuist yapılandırma dizini altındaki mutlak bir kimlik bilgisi yardımcısı yoluna ve onu oluşturan makineye en yakın önbellek bölgesine işaret eder; bu nedenle hiçbir değer bir ekip arkadaşına veya sürekli entegrasyon çalıştırıcısına aktarılmaz. Her makinede aynı olan `.bazelrc` içindeki `try-import` satırını commit edin.

Kurulum, bir Bazel çalışma alanı işaretçisi bulamadığında, dosya sembolik bir bağlantı olduğunda veya zaten bir uzak önbellek ya da Build Event Service yapılandırdığında mevcut `.bazelrc` dosyasına dokunmaz. Bu şekilde, tekrar çalıştırmak idempotent olur.

Entegrasyonu doğrulamak için normal bir Bazel komutu çalıştırın:

```bash
bazel build //...
```

Önbellek etkinliği daha sonra Tuist panosundaki projenin **Bazel Cache** sayfasında görünür; bu sayfa önbellek transferini, indirme ve yüklemeleri, okuma ve yazma gecikmesini, throughput'u ve eylem önbelleği isabet oranını gösterir. Proje **Overview** sayfası, derleme süresinin yanında aynı eylem önbelleği isabet oranının bir özetini içerir.

Bir komutun önbelleği nasıl kullandığını görmek için **Invocations** bölümünden açın. Çağrı sayfası, eylem önbelleği aramalarını içerik nesnesi isteklerinden ayırır; böylece soğuk bir eylem önbelleğini yavaş bir yapıt indirmesinden ayırt edebilirsiniz.

## Uzak yürütme {#remote-execution}

Tuist, Bazel eylemlerinizi Linux yürütücülerinde de çalıştırabilir; bu sayede önbellek isabetsizlikleri yerel makine veya CI çalıştırıcısı yerine uzaktan çalışır. Uzak yürütme, etkinleştirilmiş hesaplar için kullanılabilir; hesabınızda etkinleştirmek için [bize e-posta gönderin](mailto:contact@tuist.dev) veya [bir görüşme planlayın](https://cal.tuist.dev/team/tuist/tuist). Ardından kuruluma `--remote-execution` seçeneğini iletin:

```bash
tuist bazel setup --remote-execution
```

Kurulum daha sonra Bazel'i, uzak önbelleğin yanındaki `.bazelrc.tuist` içindeki Tuist yürütücüsüne yönlendirir. Her çalıştığında geçerli yürütücüyü ve imajı sorgular; bu nedenle oluşturulan değerleri kopyalamak yerine kurulumu yeniden çalıştırın. Eylemler, makinenizde yüklü araçlar yerine yürütücünün Linux araç zinciriyle çalışır; bu nedenle eylemlerinizin ihtiyaç duyduğu araç zincirlerini çalışma alanında bildirin.

Kurulum ayrıca `--jobs` değerini, hesabınızın aynı anda çalıştırabileceği uzak eylem sayısının iki katına ayarlar; böylece her biri için sonraki eylem bekler. Bu olmadan, Bazel makinenin çekirdek sayısı kadar eylemi paralel çalıştırır ve 2 çekirdekli bir CI çalıştırıcısı yalnızca iki uzak eylemi havada tutar.

Farklı bir değer kullanmak için komut satırında `--jobs` seçeneğini iletin veya `.bazelrc` içinde `try-import` satırından sonra ayarlayın. Bazel okuduğu son değeri kullanır; bu nedenle o satırdan önce gelen bir `--jobs`, oluşturulan değerle değiştirilir.

### Yürütücü boyutları {#executor-sizes}

Eylemler varsayılan olarak 4 GB bellek ve 2 vCPU kullanır. Daha küçük veya daha büyük bir VM istemek için `tuist-memory-gb` yürütme özelliğini ayarlayın:

| `tuist-memory-gb` | Bellek | vCPU | Çalışma alanı diski |
| --- | --- | --- | --- |
| `2` | 2 GB | 1 | 30 GB |
| `4` (varsayılan) | 4 GB | 2 | 30 GB |
| `8` | 8 GB | 4 | 30 GB |
| `16` | 16 GB | 8 | 30 GB |

Örneğin, varsayılan olarak 8 GB istemek için `.bazelrc` içindeki `try-import` satırından **sonra** bunu ekleyin:

```text
build --remote_default_exec_properties=tuist-memory-gb=8
```

Tek bir hedef için bunun yerine Bazel kuralında `exec_properties = {"tuist-memory-gb": "8"}` kullanın. Yalnızca `2`, `4`, `8` ve `16` desteklenir. `2`, aynı sınırlar içinde iki kat daha fazla eylemi aynı anda çalıştırır ancak büyük derleyici ve bağlayıcı adımları bellek yetersizliğiyle karşılaşabilir; bu hedefleri tekrar `4` veya daha fazlasına ayarlayın. Daha büyük eylemler, hesabın ayrılan vCPU ve bellek sınırlarının orantılı olarak daha fazlasını tüketerek aynı anda çalışabilecek eylem sayısını azaltır. Bir şekil her iki sınıra da uymalıdır. Oluşturulan `--jobs`, varsayılan şekli kullanır; daha büyük şekiller isterken gerekirse bunu geçersiz kılın.

Yürütücüler şu anda Tuist'in Linux amd64 imajını kullanır. Keyfi konteyner imajları, diğer yürütme işletim sistemleri ve mimarileri, kalıcı eylem çalışanları ve kendi getirdiğiniz yürütücüler kurulum üzerinden yapılandırılamaz. Geçerli imajı ve uç noktayı elde etmek için kurulumu yeniden çalıştırın.

### Çalışan eylemler ve kullanım {#running-actions-and-usage}

Projenin **Remote execution** sayfası şu anda nelerin çalıştığını ve daha önce nelerin çalıştığını gösterir:

- **Invocations**, her beş saniyede bir yenilenen, her birinin ne kadar süredir çalıştığını ve kaç uzak eyleminin çalışmakta ve sırada olduğunu gösteren çalışan Bazel çağrılarını öncelikle listeler. Kura hedef desenlerine sahip olduğunda bir çağrı görünür ve tamamlanmış raporu gelene kadar kalır. Birini açmak, onun **Executions** bölümünü gösterir: önce bir VM'de yürütülen veya VM bekleyen uzak eylemleri, ardından sonuçlarıyla (Passed, Cached, Failed veya Error) en son tamamlanan 50 eylemi; her biri mnemonic, hedef, makine boyutu ve şu ana kadarki süresiyle birlikte. Az önce tamamlanan bir eylem, kaydı gelene kadar bir dakikaya kadar **Finishing** olarak görünür. Her satır eylemin sayfasını açar; eylem hâlâ çalışırken sayfa durumunu, makinesini ve digest'ini gösterir ve tamamlandığında tam kaydı yükler. Yürütme ağ geçidinin önceden hazırladığı bir VM üzerinde çalıştırdığı eylemler çalışırken listelenmez; tamamlananlar arasında görünürler. Listeyi ararken veya filtrelerken çalışan çağrılar gösterilmez.
- **Analytics**, seçilen dönem için **Executions** ve **Total execution time** ile başlar; önceki döneme göre değişiklikleri ve zaman içindeki grafiği içerir. Toplam yürütme süresi, her eylemin yürütücüsünün VM'sinde ne kadar çalıştığıdır; girdileri getirme ve çıktıları yükleme dahildir ancak kuyruğa alma veya VM hazırlama dahil değildir. **Usage** sayfasının faturalandırdığı süre budur. Önbellekten sunulan sonuçlar yürütme değildir.

Aynı verilere `GET /api/projects/{account_handle}/{project_handle}/remote-execution/activity` ve `GET /api/projects/{account_handle}/{project_handle}/remote-execution/usage` uç noktalarından (isteğe bağlı `from` ve `to`, varsayılan olarak son 30 gün ve en fazla 366 günü kapsar) ve `get_remote_execution_activity` ile `get_remote_execution_usage` MCP araçlarından erişilebilir.

### Uzak eylem zamanlamaları {#remote-action-timings}

**Analytics** bölümünün geri kalanı ve **Invocations** tablosu, kaydedilmiş uzak fazları olan eylemleri kapsar: önceki döneme göre değişikliklerle birlikte ortalama ve p50/p90/p99 kuyruk ve yürütme süreleri, trend grafikleri ve her çağrının faz zamanlamalarına bağlantılar. Tarihe göre filtreleyin (en fazla 90 gün). Çağrılar tablosu her çağrının ortalama, p50 ve p90 yürütme süresini gösterir. Komut, hedef veya çağrı kimliğine göre arayın; duruma, komuta, hedeflere veya uzak eylem sayısına göre filtreleyin ve Invocation dışındaki herhangi bir sütuna göre sıralayın. Arama ve tablo filtreleri yalnızca çağrılar tablosuna uygulanır, analitiklere değil.

Bir çağrının **Remote execution** sekmesini açarak onun **Executions** bölümüne erişin; burada uzak eylemler süreye (en uzun süreli önce) veya başlangıç zamanına göre sıralanır: profil相对于 ne zaman başladığını, süresini ve kuyruk, girdi-getirme, yürütme ve çıktı-yükleme sürelerine bölünmüş, sayfadaki en uzun eyleme ölçeklenmiş bir çubuk içeren her uzak eylem için bir satır. Her fazın süresi için çubuğun üzerine gelin. Tablo yüklenen Bazel profillerini kullanır ve sunucu fazlarını yalnızca aynı profil iş parçacığındaki belirsiz olmayan bir eylemle ilişkilendirir.

Eksik zamanlamalar **Not recorded** anlamına gelir, sıfır değil. Daha eski profiller, eksik eylem aralıkları ve Bazel tarafından atlanan kısa fazlar, uzak çalışma gerçekleşmiş olsa bile tabloyu boş bırakabilir. Kaydedilen yeniden denemeler her eylem içinde toplanır. Sunucu meta verileri önbelleğe alınmış bir sonucu tanımlayabilir, bu nedenle bu zamanlamalar neither taze yürütmenin kanıtı nor faturalandırılabilir kullanım değildir. İstemci girdi yüklemeleri ve yerel olarak yürütülen çıktıların yüklemeleri çıktı-yükleme süresinden hariçtir.

Aynı verilere `remote_execution=true` ile yapı adımı REST uç noktasından ve `list_bazel_build_steps` / `get_bazel_build_step` MCP araçlarından erişilebilir. Zamanlamalar, profil adımlarıyla birlikte 90 gün boyunca saklanır.

### Uzak bir eylemi inceleyin {#inspect-a-remote-action}

Tuist'in yürütücüsü bir eylemi kaydettiğinde, çağrının **Remote execution** sekmesindeki satırı eylemin sayfasına bağlar. **Overview**, durumu ve çıkış kodunu, kuyruk, girdi-getirme, yürütme ve çıktı-yükleme sürelerini, eylemin planlanıp planlanmadığını veya çağrı için kiralanmış bir işçi üzerinde çalıştırılıp çalıştırılmadığını, işçiyi, belleği, zaman aşımını ve eylem digest'ini gösterir. Başarısız bir eylem ayrıca bir **Errors** kartı alır: standart hatasında tanınan derleyici hataları (Clang, GCC, Swift, javac, Go ve rustc formatları) dosyaya göre gruplandırılmış veya hiçbiri tanınmadığında çıkış kodu ve standart hatasının sonu. **Logs**, satır numaralarıyla tek bir günlükte standart çıktıyı ve ardından standart hatayı gösterir, hata satırlarını vurgular. Bir CI iş günlüğü gibi sonunda açılır ve **Load earlier lines** geriye doğru sayfalandırır. Bir kayıt her akışın ilk 16 KiB'sini tutar; yürütücü ayrıca daha uzun bir akışı çalıştırma artefaktı olarak tamamen saklar, böylece günlük ve **Errors** kartı çıktının tamamını kapsar. 16 MiB üzeri bir akış yalnızca ilk 16 KiB'sini ve son 16 MiB'sini tutar. Günlükteki bir işaretçi baytların nerede eksik olduğunu ve nedenini gösterir: çok uzun bir akıştan atlanmış veya depolanmamış, örneğin kopya süresi dolduğunda. **Overview** üzerindeki **Command** kartı, **Copy** ile kopyalanan komut satırını, çalışma dizinini ve çıktı yollarını ve daraltılmış bölümlerde ortam ve platform özelliklerini gösterir.

Adlarında `TOKEN`, `SECRET`, `PASSWORD` veya `KEY` geçen ortam değişkenleri ve bu şekilde adlandırılan bayrakların değerleri `****` olarak gösterilir. Kayıtlar en iyi çabayla sunulur: bağlantısı olmayan bir satır, çıktısıyla belirsiz bir şekilde eşleşen hiçbir kayıt olmadığı anlamına gelir, eylemin yerel olarak çalıştığı anlamına gelmez. Kayıtlar 90 gün boyunca saklanır. `GET /api/projects/{account_handle}/{project_handle}/bazel/invocations/{invocation_id}/remote-actions` ve `.../remote-actions/{operation_id}` REST uç noktaları ile `list_bazel_remote_actions` / `get_bazel_remote_action` MCP araçları aynı kayıtları döndürür; `.../remote-actions/{operation_id}/logs/{stdout|stderr}` ve `get_bazel_remote_action_log` günlükleri bayt aralığına göre okur. Saklanan günlük kopyaları çalıştırma artefaktlarıdır ve planın çalıştırma-artefaktı penceresiyle birlikte süresi dolar.

## Derleme içgörileri {#build-insights}

Varsayılan olarak, `tuist bazel setup` ayrıca Bazel'in Build Event Service'ini yapılandırır, böylece tamamlanan komutlar **Invocations** kontrol panelinde görünür. Kontrol panelinin ne gösterdiği ve özel meta verilerin nasıl ekleneceği için <.localized_link href="/guides/features/build-insights/bazel">Bazel build insights</.localized_link> bölümüne bakın.

Yalnızca uzak önbelleği istiyorsanız ve derleme olayı akışını göndermek istemiyorsanız, şu şekilde devre dışı bırakın:

```bash
tuist bazel setup --no-build-insights
```

## Sürekli entegrasyon {#continuous-integration}

CI'yı <.localized_link href="/guides/server/authentication#continuous-integration">Authentication guide</.localized_link> içindeki yöntemlerden biriyle kimlik doğrulayın, ardından `.bazelrc.tuist` çalıştırıcısı için doğru bölgeyi yansıtması amacıyla checkout adımının bir parçası olarak `tuist bazel setup` komutunu bir kez çalıştırın. Sağlayıcıya özel örnekler için <.localized_link href="/guides/integrations/continuous-integration">Continuous Integration guide</.localized_link> bölümüne bakın.

## Veri saklama {#data-retention}

Tuist uzak önbellek gözlemlerini 90 gün boyunca saklar. Tam politika için <.localized_link href="/guides/server/data-retention">data retention</.localized_link> bölümüne bakın.
