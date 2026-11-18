---
{
  "title": "Bazel önbelleği",
  "titleTemplate": ":title · Önbellek · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist ile Bazel uzak önbellek girdilerini ekibiniz ve CI arasında paylaşın."
}
---
# Bazel önbelleği {#bazel-cache}

Tuist, Bazel'in uzak önbellek olarak bağlandığı bir [Remote Execution API](https://github.com/bazelbuild/remote-apis) önbelleği sunar. Bir eylemin çıktıları zaten önbellekteyse, Bazel eylemi atlar ve sonucu Tuist önbelliğinden çeker; bu sayede ekibiniz ve CI ortamlarınızda derleme süresinden tasarruf edilir.

## Kurulum {#setup}

Bazel çalışma alanının kök dizininden şunu çalıştırın:

```bash
tuist bazel setup
```

Bu işlem, en yakın Tuist önbellek bölgesine yönlendirilmiş ve çalışma alanı başına kimlik bilgisi yardımcısı ile kimlik doğrulaması yapan bir `.bazelrc.tuist` dosyasını `.bazelrc` dosyanızın yanına yazar. Ayrıca depo içindeki `.bazelrc` dosyasına bir `try-import` satırı ekler:

```text
try-import %workspace%/.bazelrc.tuist
```

İçe aktarmayı kendiniz yönetmek istiyorsanız `--no-add-bazelrc-import` parametresini kullanın.

`.bazelrc.tuist` dosyasını `.gitignore` dosyanıza ekleyin ve depoya göndermek yerine kurulumu her makinede çalıştırın. Oluşturulan dosya, geçerli kullanıcının Tuist yapılandırma dizini altındaki mutlak bir kimlik bilgisi yardımcısı yoluna ve onu oluşturan makineye en yakın önbellek bölgesine işaret eder; bu nedenle bu değerlerin hiçbiri bir ekip arkadaşına veya sürekli entegrasyon çalıştırıcısına taşınmaz. Her makinede aynı olan `.bazelrc` içindeki `try-import` satırını depoya gönderin.

Kurulum, bir Bazel çalışma alanı işaretçisi bulamadığında, dosya sembolik bir bağlantı olduğunda veya zaten bir uzak önbellek ya da Build Event Service yapılandırdığında mevcut `.bazelrc` dosyasına dokunmaz. Bu sayede tekrar çalıştırmak idempotent olur.

Entegrasyonu doğrulamak için normal bir Bazel komutu çalıştırın:

```bash
bazel build //...
```

Önbellek etkinliği daha sonra Tuist kontrol panelindeki projenin **Bazel Cache** sayfasında görünür; bu sayfa önbellek aktarımını, indirme ve yüklemeleri, okuma ve yazma gecikmesini, throughput'u ve eylem önbelleği isabet oranını gösterir. Proje **Overview** sayfası, derleme süresinin yanında aynı eylem önbelleği isabet oranının bir özetini içerir.

Bir komutun önbelleği nasıl kullandığını görmek için **Invocations** bölümünden açın. Çağrı sayfası, eylem önbelleği aramalarını içerik nesnesi isteklerinden ayırır; böylece soğuk bir eylem önbelleğini yavaş bir yapıt indirmesinden ayırt edebilirsiniz.

## Derleme içgörüler {#build-insights}

Varsayılan olarak `tuist bazel setup`, tamamlanan komutların **Invocations** kontrol panelinde görünmesi için Bazel'in Build Event Service'ini de yapılandırır. Kontrol panelinin neler gösterdiğini ve özel meta verilerin nasıl ekleneceğini öğrenmek için bkz. <.localized_link href="/guides/features/build-insights/bazel">Bazel build insights</.localized_link>.

Yalnızca uzak önbelleği istiyor ve derleme olayı akışını göndermek istemiyorsanız, şu şekilde devre dışı bırakın:

```bash
tuist bazel setup --no-build-insights
```

## Sürekli entegrasyon {#continuous-integration}

CI'yı <.localized_link href="/guides/server/authentication#continuous-integration">Authentication guide</.localized_link> bölümündeki yöntemlerden biriyle kimlik doğrulayın, ardından `.bazelrc.tuist` dosyasının çalıştırıcı için doğru bölgeyi yansıtması amacıyla kontrol adımı kapsamında `tuist bazel setup` komutunu bir kez çalıştırın. Sağlayıcıya özel örnekler için bkz. <.localized_link href="/guides/integrations/continuous-integration">Continuous Integration guide</.localized_link>.

## Veri saklama {#data-retention}

Tuist, uzak önbellek gözlemlerini 90 gün boyunca saklar. Tam politika için bkz. <.localized_link href="/guides/server/data-retention">data retention</.localized_link>.
