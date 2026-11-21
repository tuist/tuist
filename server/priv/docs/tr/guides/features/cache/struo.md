---
{
  "title": "Struo önbelleği",
  "titleTemplate": ":title · Önbellek · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist'in uzak önbelleği ile Struo eylem sonuçlarını geliştirici makineleri ve CI arasında paylaşın."
}
---
# Struo önbelleği {#struo-cache}

<a id="once-cache"></a>

Struo sonuçları yerel olarak yeniden kullanabilir, ancak bir geliştiricinin yerel önbelleği ekip arkadaşlarına veya yeni bir CI çalışanına ulaşmaz. Tuist, eşleşen işlerin yalnızca bir makinede çalıştırılmasını sağlayan paylaşımlı bir uzak önbellek sunar.

## Kurulum {#setup}

<.localized_link href="/guides/get-started/struo-project#connect-the-project">Struo ile başlayın</.localized_link> kılavuzunu tamamlayın, ardından deponuzun `struo.toml` dosyasındaki önbellek bağlantısını kontrol edin:

```toml
[infrastructures.tuist]
kind = "tuist"
account = "acme"
project = "app"

[infrastructure.cache]
provider = "tuist"
```

`struo auth login --provider tuist` komutuyla kimlik doğrulaması yapın. Ek bir Tuist yürütülebilir dosyası veya önbellek eklentisi gerekmez. Aynı sağlayıcı [önbelleklenebilir betikleri](https://struo.run/docs/guide/scripted/caching) ve [grafik hedeflerini](https://struo.run/docs/guide/graph) destekler.

Yalnızca Struo tarafından önbelleklenebilir olarak bildirilen işler yeniden kullanılabilir. İşin bağımlı olduğu girdileri, çıktıları ve ortamı bildirin; uzak bir önbellek yapılandırmak, rastgele bir komutu tekrarlanabilir hale getirmez.

## Paylaşımlı yeniden kullanımı doğrulayın {#verify-shared-reuse}

Eşleşen girdiler ve yapılandırmaya sahip iki makinede aynı önbelleklenebilir betiği veya grafik hedefini çalıştırın:

```bash
struo build MyApplication
```

İlk makine paylaşımlı önbelleği doldurur. Yerel önbelleğinde bu sonucu görmemiş ikinci bir makinede, bir isabet ve geri yüklenen çıktılar uzak yeniden kullanımı onaylar. Komutun yalnızca ilk makinede tekrarlanması, Tuist'in sonucu sağladığını değil, yerel bir isabeti gösterir.

## Önbellek etkinliğini inceleyin {#inspect-cache-activity}

Eylem-önbelleği isabetlerini, aktarımları, gecikmeyi ve throughput'u incelemek için Tuist projenizde **Struo Önbelleği**'ni açın. Bir çalıştırmanın bildirilen eylem kararlarını ve içerik nesnesi etkinliğini incelemek için çalıştırmanın **Önbellek** görünümünü açın.

Eylem sonuçları ve içerik nesneleri farklı soruları yanıtlar: eksik bir eylem sonucu, Struo'nun işi yapması gerektiği anlamına gelir; bir içerik nesnesi isteği ise bir girdiyi veya çıktıyı aktarır. Bir blob indirmesini yürütülmüş bir eylem veya eylem-önbelleği isabeti olarak değerlendirmeyin.

Çalıştırmanın eylem grafiği ve yapılandırılmış hatalar için bkz. <.localized_link href="/guides/features/build-insights/struo">Struo derleme içgörüler</.localized_link>.

## Sürekli entegrasyon {#continuous-integration}

<.localized_link href="/guides/integrations/continuous-integration#struo">Sürekli entegrasyonda Struo</.localized_link> bölümünde açıklandığı gibi `TUIST_TOKEN` veya Struo'nun başsız OIDC girişini kullanın. Kimlik bilgilerini `struo.toml` dışında tutun.

Hesabın <.localized_link href="/guides/features/cache#restrict-uploads-to-ci">önbellek yükleme politikası</.localized_link>, sonuçların kimler tarafından yayınlanabileceğini belirler. Salt okunur bir geliştirici, önbellek yazarı olmadan CI tarafından üretilen girdileri tüketebilir.

Bağlantı yeniden denemeleri ve sorun giderme için bkz. [Struo'nun Tuist entegrasyonu](https://struo.run/docs/guide/infrastructure/tuist#connection-recovery). Yeniden denemeler, kesintiye uğramış yüklemelerin devam ettirilmesini sağlamaz.
