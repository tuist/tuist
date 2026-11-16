---
{
  "title": "Bazel önbelleği",
  "titleTemplate": ":title · Önbellek · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist ile Bazel uzak önbellek girdilerini ekibiniz ve CI arasında paylaşın."
}
---
# Bazel önbelleği {#bazel-cache}

Tuist, Bazel'in uzak önbellek olarak bağlandığı bir [Remote Execution API](https://github.com/bazelbuild/remote-apis) önbelleği sunar. Bir eylemin çıktıları zaten önbellekte olduğunda, Bazel eylemi atlar ve sonucu Tuist'in önbelliğinden çeker; bu sayede ekibiniz ve CI ortamlarınızda derleme süresinden tasarruf edersiniz. GitHub Actions kurulumu için bkz. [Bazel on GitHub Actions](https://tuist.dev/solutions/bazel-github-actions). Uzak önbellekleme nasıl çalışır ve kendi sunucunuzda barındırılan ile yönetilen önbellekler nasıl karşılaştırılır hakkında bilgi için bkz. [Bazel remote cache](https://tuist.dev/solutions/bazel-remote-cache).

## Kurulum {#setup}

Bazel çalışma alanının kök dizininden şunu çalıştırın:

```bash
tuist bazel setup
```

Bu işlem, en yakın Tuist önbellek bölgesine bağlı ve çalışma alanı başına kimlik bilgisi yardımcısı üzerinden kimlik doğrulaması yapan bir `.bazelrc.tuist` dosyasını `.bazelrc` yanınıza yazar. Ayrıca deponuzun `.bazelrc` dosyasına bir `try-import` satırı ekler:

```text
try-import %workspace%/.bazelrc.tuist
```

İçe aktarmayı kendiniz yönetmek istiyorsanız `--no-add-bazelrc-import` seçeneğini kullanın.

`.bazelrc.tuist` dosyasını `.gitignore` dosyanıza ekleyin ve dosyayı commitlemek yerine her makinede kurulumu çalıştırın. Oluşturulan dosya, geçerli kullanıcının Tuist yapılandırma dizini altındaki mutlak bir kimlik bilgisi yardımcısı yoluna ve dosyayı oluşturan makineye en yakın önbellek bölgesine işaret eder; bu nedenle hiçbir değer bir ekip arkadaşına veya sürekli entegrasyon çalıştırıcısına aktarılmaz. Her makinede aynı olan `.bazelrc` içindeki `try-import` satırını commit edin.

Kurulum, bir Bazel çalışma alanı işaretçisi bulamadığında, dosya sembolik bir bağlantı olduğunda veya zaten bir uzak önbellek ya da Build Event Service yapılandırdığında mevcut `.bazelrc` dosyasına dokunmaz. Bu sayede tekrar çalıştırmak idempotent olur.

Entegrasyonu doğrulamak için normal bir Bazel komutu çalıştırın:

```bash
bazel build //...
```

Önbellek etkinliği daha sonra Tuist panosundaki projenin **Bazel Cache** sayfasında görünür; burada önbellek transferi, indirme ve yükleme işlemleri, okuma ve yazma gecikmesi, aktarım hızı ve eylem önbelleği isabet oranı gösterilir. Proje **Overview** sayfası, derleme süresinin yanında aynı eylem önbelleği isabet oranının bir özetini içerir.

Bir komutun önbelleği nasıl kullandığını görmek için **Invocations** bölümünden açın. Çağrı sayfası, eylem önbelleği aramalarını içerik nesnesi isteklerinden ayırır; böylece soğuk bir eylem önbelliğini yavaş bir yapıt indirmesinden ayırt edebilirsiniz.

## Uzak yürütme {#remote-execution}

Tuist, Bazel eylemlerinizi Linux yürütücülerinde de çalıştırabilir; böylece önbellek isabetleri yerel makine veya CI çalıştırıcısı yerine uzaktan çalışır. Uzak yürütme, etkinleştirilmiş hesaplar için kullanılabilir; hesabınızda etkinleştirmek için [bize e-posta gönderin](mailto:contact@tuist.dev) veya [bir görüşme planlayın](https://cal.tuist.dev/team/tuist/tuist). Ardından kuruluma `--remote-execution` seçeneğini iletin:

```bash
tuist bazel setup --remote-execution
```

Kurulum daha sonra Bazel'i, uzak önbelleğin yanındaki `.bazelrc.tuist` içindeki Tuist yürütücüsüne yönlendirir. Her çalıştırıldığında geçerli yürütücüyü ve imajı sorgular; bu nedenle oluşturulan değerleri kopyalamak yerine kurulumu yeniden çalıştırın. Eylemler, makinenizde yüklü araçlar değil, yürütücünün Linux araç zinciri ile çalışır; bu nedenle eylemlerinizin ihtiyaç duyduğu araç zincirlerini çalışma alanında bildirin.

Kurulum ayrıca `--jobs` değerini, hesabınızın aynı anda çalıştırabileceği uzak eylem sayısının iki katına ayarlar; böylece her bir eylem için sonraki eylem beklemiş olur. Bunun olmaması durumunda, Bazel makinedeki çekirdek sayısı kadar eylemi paralel çalıştırır ve 2 çekirdekli bir CI çalıştırıcısı yalnızca iki uzak eylemi aktif tutar.

Farklı bir değer kullanmak için komut satırında `--jobs` seçeneğini iletin veya `try-import` satırından sonra `.bazelrc` içinde ayarlayın. Bazel okuduğu son değeri kullanır; bu nedenle o satırdan önce gelen bir `--jobs`, oluşturulan değerle değiştirilir.

## Derleme içgörüleri {#build-insights}

Varsayılan olarak `tuist bazel setup`, tamamlanan komutların **Invocations** panosunda görünmesi için Bazel'in Build Event Service'ini de yapılandırır. Panonun ne gösterdiğini ve özel meta verilerin nasıl ekleneceğini öğrenmek için bkz. <.localized_link href="/guides/features/build-insights/bazel">Bazel build insights</.localized_link>.

Yalnızca uzak önbelleği istiyor ve derleme olay akışını göndermek istemiyorsanız, şu seçeneği kullanarak devre dışı bırakın:

```bash
tuist bazel setup --no-build-insights
```

## Sürekli entegrasyon {#continuous-integration}

CI'yı <.localized_link href="/guides/server/authentication#continuous-integration">Authentication guide</.localized_link> içindeki yöntemlerden biriyle kimlik doğrulayın, ardından `.bazelrc.tuist` dosyasının çalıştırıcı için doğru bölgeyi yansıtması amacıyla checkout adımı kapsamında `tuist bazel setup` komutunu bir kez çalıştırın. Sağlayıcıya özel örnekler için bkz. <.localized_link href="/guides/integrations/continuous-integration">Continuous Integration guide</.localized_link>.

## Veri saklama {#data-retention}

Tuist, uzak önbellek gözlemlerini 90 gün boyunca saklar. Tam politika için bkz. <.localized_link href="/guides/server/data-retention">data retention</.localized_link>.
