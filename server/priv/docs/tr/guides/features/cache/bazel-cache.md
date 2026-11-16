---
{
  "title": "Bazel önbelleği",
  "titleTemplate": ":title · Önbellek · Özellikler · Kılavuzlar · Tuist",
  "description": "Bazel uzak önbellek girdilerini ekibiniz ve CI ile Tuist üzerinden paylaşın."
}
---
# Bazel önbelleği {#bazel-cache}

Tuist, Bazel'in uzak önbellek olarak bağlandığı bir [Remote Execution API](https://github.com/bazelbuild/remote-apis) önbelleği sunar. Bir eylemin çıktıları zaten önbellekteyse, Bazel eylemi atlar ve sonucu Tuist önbelleğinden çeker; bu sayede ekibiniz ve CI ortamlarınızda derleme süresinden tasarruf edersiniz. GitHub Actions kurulumu için bkz. [Bazel on GitHub Actions](https://tuist.dev/solutions/bazel-github-actions). Uzak önbellekleme mekanizması ve kendi kendine barındırılan ile yönetilen önbelleklerin karşılaştırılması hakkında bilgi için bkz. [Bazel remote cache](https://tuist.dev/solutions/bazel-remote-cache).

## Kurulum {#setup}

Bazel çalışma alanının kök dizininden şunu çalıştırın:

```bash
tuist bazel setup
```

Bu işlem, en yakın Tuist önbellek bölgesine bağlı ve çalışma alanı başına kimlik doğrulama yardımcısı üzerinden kimliği doğrulanmış olan `.bazelrc.tuist` dosyasını `.bazelrc` dosyanızın yanına yazar. Ayrıca depounuzun `.bazelrc` dosyasına bir `try-import` satırı ekler:

```text
try-import %workspace%/.bazelrc.tuist
```

İçe aktarmayı kendiniz yönetmek istiyorsanız `--no-add-bazelrc-import` parametresini iletin.

`.bazelrc.tuist` öğesini `.gitignore` dosyanıza ekleyin ve dosyayı commitlemek yerine her makinede kurulumu çalıştırın. Oluşturulan dosya, geçerli kullanıcının Tuist yapılandırma dizini altındaki mutlak bir kimlik doğrulama yardımcısı yoluna ve dosyayı oluşturan makineye en yakın önbellek bölgesine işaret eder; bu nedenle hiçbir değer bir ekip arkadaşına veya sürekli entegrasyon çalıştırıcısına taşınmaz. Her makinede aynı olan `.bazelrc` içindeki `try-import` satırını commit edin.

Kurulum, bir Bazel çalışma alanı işaretçisi bulamadığında, dosya sembolik bir bağlantı olduğunda veya zaten bir uzak önbellek ya da Build Event Service yapılandırdığında mevcut `.bazelrc` dosyasına dokunmaz. Bu sayede tekrar çalıştırmak idempotent olur.

Entegrasyonu doğrulamak için normal bir Bazel komutu çalıştırın:

```bash
bazel build //...
```

Önbellek etkinliği daha sonra Tuist panosundaki projenin **Bazel Cache** sayfasında görünür; bu sayfa önbellek transferini, indirme ve yüklemeleri, okuma ve yazma gecikmesini, throughput'u ve eylem önbelleği isabet oranını gösterir. Proje **Overview** sayfası, derleme süresinin yanında aynı eylem önbelleği isabet oranının bir özetini içerir.

Bir komutun önbelleği nasıl kullandığını görmek için **Invocations** bölümünden açın. Çağrı sayfası, eylem önbelleği aramalarını içerik nesnesi isteklerinden ayırır; böylece soğuk bir eylem önbelleğini yavaş bir yapıt indirmesinden ayırt edebilirsiniz.

## Uzak yürütme {#remote-execution}

Tuist, Bazel eylemlerinizi Linux yürütücülerinde de çalıştırabilir; böylece önbellek isabetleri yerel makine veya CI çalıştırıcısı yerine uzaktan çalışır. Uzak yürütme, hesap başına talep üzerine etkinleştirilir: Etkinleştirmek için [bize ulaşın](mailto:contact@tuist.dev). Etkinleştirildikten sonra, kurulum için `--remote-execution` parametresini iletin:

```bash
tuist bazel setup --remote-execution
```

Kurulum daha sonra Bazel'i, uzak önbelleğin yanındaki `.bazelrc.tuist` içindeki Tuist yürütücüsüne yönlendirir. Her çalıştığında geçerli yürütücüyü ve imajı sorgular; bu nedenle oluşturulan değerleri kopyalamak yerine kurulumu yeniden çalıştırın. Eylemler, makinenizde yüklü araçlar yerine yürütücünün Linux araç zinciriyle çalışır; bu nedenle eylemlerinizin ihtiyaç duyduğu araç zincirlerini çalışma alanında bildirin.

Kurulum ayrıca `--jobs` değerini, hesabınızın aynı anda çalıştırabileceği uzak eylem sayısının iki katına ayarlar; böylece her biri için sonraki eylem bekler. Bu olmadan, Bazel makinenin çekirdek sayısı kadar eylemi paralel çalıştırır ve 2 çekirdekli bir CI çalıştırıcısı yalnızca iki uzak eylemi uçuşta tutar.

Farklı bir değer kullanmak için komut satırında `--jobs` parametresini iletin veya `try-import` satırından sonra `.bazelrc` içinde ayarlayın. Bazel okuduğu son değeri kullanır; bu nedenle o satırdan önce gelen bir `--jobs` değeri, oluşturulan değerle değiştirilir.

## Derleme içgörileri {#build-insights}

Varsayılan olarak `tuist bazel setup`, tamamlanan komutların **Invocations** panosunda görünmesi için Bazel'in Build Event Service'ini de yapılandırır. Panonun neler gösterdiği ve özel meta verilerin nasıl ekleneceği hakkında bilgi için bkz. <.localized_link href="/guides/features/build-insights/bazel">Bazel build insights</.localized_link>.

Yalnızca uzak önbelleği istiyor ve derleme olayı akışını göndermek istemiyorsanız, şu şekilde devre dışı bırakın:

```bash
tuist bazel setup --no-build-insights
```

## Sürekli entegrasyon {#continuous-integration}

CI'yı <.localized_link href="/guides/server/authentication#continuous-integration">Authentication guide</.localized_link> içindeki yöntemlerden biriyle kimlik doğrulayın, ardından `.bazelrc.tuist` çalıştırıcısı için doğru bölgeyi yansıtması amacıyla kontrol adımı kapsamında bir kez `tuist bazel setup` çalıştırın. Sağlayıcıya özel örnekler için bkz. <.localized_link href="/guides/integrations/continuous-integration">Continuous Integration guide</.localized_link>.

## Veri saklama {#data-retention}

Tuist, uzak önbellek gözlemlerini 90 gün boyunca saklar. Tam politika için bkz. <.localized_link href="/guides/server/data-retention">data retention</.localized_link>.
