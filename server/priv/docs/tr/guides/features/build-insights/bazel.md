---
{
  "title": "Bazel Derleme İçgörüleri",
  "titleTemplate": ":title · Derleme İçgörüleri · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist panosunda Bazel komut sürelerini, önbellek toplamlarını ve kritik yol tanılarını takip edin."
}
---
# Bazel derleme içgörüleri {#bazel-build-insights}

Tamamlanan her `build`, `test` ve diğer Bazel komutu, projenin **Çağrılar** panosunda görünür: komut türü, çıkış durumu, başlangıç ve bitiş zamanı, süre ve Bazel’in aynı çağırmaya atfettiği önbellek isabetleri, ıskalamalar, indirmeler ve yüklemeler.

Çağrı verileri Bazel’in [Build Event Protocol](https://bazel.build/remote/bep) üzerinden iletilir. Kurulum, `tuist bazel setup` çalıştırdığınızda bunu sizin için bağlar; çağrıları görmeye başlamak için ek bayraklara gerek yoktur.

## Panoda gösterilenler {#what-the-dashboard-shows}

Her çağrı şunları kaydeder:

- Bazel’in çalıştırdığı komut, çıkış kodu, başlangıç ve bitiş zamanı ile toplam süre.
- Eylem, hedef ve paket sayıları.
- Sınırlı bir derleme zaman çizelgesi ve kritik yol özeti.
- Çağrıya atfedilen önbellek isabetleri, ıskalamalar, indirmeler ve yüklemeler.
- Çalışma sırasında yürütme sırasına göre yakalanan ilerleme günlüğü satırları.
- Bazel sürümü, Bazel bunları raporladığında git dalı ve commit’i ve çalışmanın CI üzerinde gerçekleşip gerçekleşmediği.

Bazel’in tamamlanmış bir çağırmaya atfedemediği önbellek etkinliği, örneğin bir komut çalışma ortasında kesildiğinde, proje **Genel Bakış** sayfasında ham uzak önbellek gözlemi olarak görünmeye devam eder. Bu, komut başarısı, süresi veya test sonuçlarına dair kanıt olarak değerlendirilmez.

## Özel meta veriler {#custom-metadata}

Farklı ekiplerin, donanımların veya iş akışlarının çalışmalarını karşılaştırmak için çağrılara anahtar-değer verileri ekleyin. Değerler, her çağrının ayrıntı sayfasında ve uygulama programlama arayüzü ile Model Context Protocol araçları üzerinden görünür.

Meta verileri Bazel’in yerleşik `--build_metadata` bayrağıyla ayarlayın:

```bash
bazel build --build_metadata=TICKET=TUIST-123 --build_metadata=RUNNER=macos-14 //...
```

Veya bunları `.bazelrc` dosyanızda lane başına bir kez ayarlayın:

```text
build:ci --build_metadata=RUNNER=macos-14
```

Her çağrı en fazla 20 özel girdi taşıyabilir. Anahtarlar en fazla 50 karakter, değerler en fazla 500 karakter içerebilir. Bu sınırları aşan girdiler, çağrı depolanmadan önce düşürülür; bu nedenle geçersiz bir girdi, raporun geri kalanının kaydedilmesini engellemez.

Tuist’in derleme ortamından türettiği `CI`, `GIT_BRANCH` ve `GIT_COMMIT` gibi bağlam anahtarları, çağrıdaki birinci sınıf alanları zaten doldurdukları için özel değerler olarak saklanmaz.

Özel meta veriler, proje üyelerine panoda ve uygulama programlama arayüzü ile Model Context Protocol araçları üzerinden görünür. Bunları kimlik bilgileri, erişim belirteçleri veya diğer hassas veriler için kullanmayın.

## Devre dışı bırakma {#opting-out}

Build Event Protocol akışı, komut satırı bağımsız değişkenlerini, ortam değerlerini ve komut çıktısını taşır. Tuist yalnızca yukarıda listelenen tamamlanmış komut alanlarını tutar ve geri kalanını atar, ancak olay akışını hiç göndermemeyi tercih ediyorsanız kurulumu şu şekilde yeniden çalıştırın:

```bash
tuist bazel setup --no-build-insights
```

Oluşturulan `.bazelrc.tuist` yalnızca uzak önbelleği yapılandırır. Çağrılar panoda görünmeyi durdurur ve önbellek gözlemleri **Genel Bakış** sayfasında kalır.

## Veri saklama {#data-retention}

Tuist, Bazel çağrılarını ve günlüklerini 90 gün boyunca saklar. Tam politika için <.localized_link href="/guides/server/data-retention">veri saklama</.localized_link> bölümüne bakın.
