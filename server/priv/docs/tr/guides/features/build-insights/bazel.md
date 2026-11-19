---
{
  "title": "Bazel Derleme Analizleri",
  "titleTemplate": ":title · Derleme Analizleri · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist kontrol panelinde Bazel komut sürelerini, önbellek toplamlarını ve kritik yol tanılarını izleyin."
}
---
# Bazel derleme içgörüleri {#bazel-build-insights}

Tamamlanan her `build`, `test` ve diğer Bazel komutu projenin **Çağrılar** panosunda görünür: komut türü, çıkış durumu, başlangıç ve bitiş zamanı, süre ve Bazel’in aynı çağrıya atfettiği önbellek isabetleri, ıskalamaları, indirmeler ve yüklemeler.

Çağrı verileri Bazel’in [Build Event Protocol](https://bazel.build/remote/bep) üzerinden iletilir. `tuist bazel setup` çalıştırdığınızda kurulum bunu sizin için otomatik olarak yapılandırır; çağrıları görmeye başlamak için ek bayraklara gerek yoktur.

## Panonun gösterdiği bilgiler {#what-the-dashboard-shows}

Her çağrı şunları kaydeder:

- Bazel’in çalıştırdığı komut, çıkış kodu, başlangıç ve bitiş zamanı ile toplam süre.
- Eylem, hedef ve paket sayıları.
- Sınırlı bir derleme zaman çizelgesi ve kritik yol özeti.
- Çağrıya atfedilen önbellek isabetleri, ıskalamalar, indirmeler ve yüklemeler.
- Çalışma sırasında yakalanan ilerleme günlük satırları, yürütme sırasına göre.
- Bazel sürümü, Bazel raporladığında git dalı ve commit bilgisi ve çalışmanın CI üzerinde gerçekleşip gerçekleşmediği.

Bazel’in tamamlanmış bir çağrıya atfedemediği önbellek etkinliği, örneğin bir komut çalışma ortasında kesildiğinde, projenin **Genel Bakış** sayfasında ham uzak önbellek gözlemi olarak görünür. Bu veri, komut başarısı, süre veya test sonuçlarına dair kanıt olarak değerlendirilmez.

## Özel meta veriler {#custom-metadata}

Farklı ekiplerin, donanımların veya iş akışlarının çalışmalarını karşılaştırmak için çağrılara anahtar-değer verileri ekleyin. Değerler, her çağrının ayrıntı sayfasında ve uygulama programlama arayüzü ile Model Context Protocol araçları üzerinden görüntülenir.

Meta verileri Bazel’in yerleşik `--build_metadata` bayrağıyla ayarlayın:

```bash
bazel build --build_metadata=TICKET=TUIST-123 --build_metadata=RUNNER=macos-14 //...
```

Veya `.bazelrc` dosyanızda lane başına bir kez ayarlayın:

```text
build:ci --build_metadata=RUNNER=macos-14
```

Her çağrı en fazla 20 özel girdi taşıyabilir. Anahtarlar en fazla 50 karakter, değerler ise en fazla 500 karakter içerebilir. Bu sınırları aşan girdiler, çağrı depolanmadan önce atılır; böylece geçersiz bir girdi raporun geri kalanının kaydedilmesini engellemez.

Tuist’in derleme ortamından türettiği bağlam anahtarları, örneğin `CI`, `GIT_BRANCH` ve `GIT_COMMIT`, zaten çağrıda birinci sınıf alanları doldurdukları için özel değerler olarak saklanmaz.

Özel meta veriler, proje üyeleri tarafından panoda ve uygulama programlama arayüzü ile Model Context Protocol araçları üzerinden görülebilir. Kimlik bilgileri, erişim token’ları veya diğer hassas veriler için kullanmayın.

## Devre dışı bırakma {#opting-out}

Build Event Protocol akışı komut satırı bağımsız değişkenlerini, ortam değerlerini ve komut çıktısını taşır. Tuist yalnızca yukarıda listelenen tamamlanmış komut alanlarını saklar ve geri kalanını atar; ancak olay akışını hiç göndermemeyi tercih ederseniz kurulumu şu şekilde yeniden çalıştırın:

```bash
tuist bazel setup --no-build-insights
```

Oluşturulan `.bazelrc.tuist` yalnızca uzak önbelleği yapılandırır. Çağrılar panoda görünmeyi durdurur ve önbellek gözlemleri **Genel Bakış** sayfasında kalmaya devam eder.

## Veri saklama {#data-retention}

Tuist, Bazel çağrılarını ve günlüklerini 90 gün boyunca saklar. Tam politika için <.localized_link href="/guides/server/data-retention">veri saklama</.localized_link> bölümüne bakın.
