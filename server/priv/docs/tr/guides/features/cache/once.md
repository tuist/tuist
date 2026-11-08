---
{
  "title": "Once önbelleği",
  "titleTemplate": ":title · Önbellek · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist'in uzak önbelleğiyle Once eylem sonuçlarını geliştirici makineleri ve CI arasında paylaşın."
}
---
# Once önbelleği {#once-cache}

Once sonuçları yerel olarak yeniden kullanabilir, ancak bir geliştiricinin yerel önbelleği ekip arkadaşlarına veya yeni bir CI işçisine ulaşmaz. Tuist, eşleşen işlerin yalnızca bir makinede çalışması gereken paylaşımlı bir uzak önbellek sağlar.

## Kurulum {#setup}

<.localized_link href="/guides/get-started/once-project#connect-the-project">Once ile başlayın</.localized_link> adımlarını tamamlayın, ardından deponuzdaki `once.toml` içindeki önbellek bağlamasını kontrol edin:

```toml
[infrastructures.tuist]
kind = "tuist"
account = "acme"
project = "app"

[infrastructure.cache]
provider = "tuist"
```

`once auth login --provider tuist` ile kimlik doğrulaması yapın. Tuist yürütülebilir dosyasına veya ek bir önbellek eklentisine gerek yoktur. Aynı sağlayıcı [önbelleğe alınabilen betikleri](https://buildonce.dev/docs/guide/scripted/caching) ve [grafik hedeflerini](https://buildonce.dev/docs/guide/graph) destekler.

Yalnızca Once tarafından önbelleğe alınabilir olarak bildirilen işler yeniden kullanılabilir. İşin bağımlı olduğu girdileri, çıktıları ve ortamı bildirin; uzak bir önbellek yapılandırmak rastgele bir komutu tekrarlanabilir hale getirmez.

## Paylaşımlı yeniden kullanımı doğrulayın {#verify-shared-reuse}

Eşleşen girdilere ve yapılandırmaya sahip iki makinede aynı önbelleğe alınabilen betiği veya grafik hedefini çalıştırın:

```bash
once build MyApplication
```

İlk makine paylaşımlı önbelleği doldurur. Yerel önbelleğinde bu sonucu görmemiş ikinci bir makinede, bir isabet ve geri yüklenen çıktılar uzaktan yeniden kullanımı onaylar. Komutu yalnızca ilk makinede tekrarlamak, Tuist'in sonucu sağladığını değil, yerel bir isabeti gösterir.

## Önbellek etkinliğini inceleyin {#inspect-cache-activity}

Eylem önbelleği isabetlerini, aktarımları, gecikmeyi ve verimi incelemek için Tuist projenizde **Once Önbelleği**'ni açın. Bir çalıştırmanın bildirilen eylem kararlarını ve içerik nesnesi etkinliğini incelemek için çalıştırmanın **Önbellek** görünümünü açın.

Eylem sonuçları ve içerik nesneleri farklı soruları yanıtlar: eksik bir eylem sonucu, Once'in işi yapması gerektiği anlamına gelir; bir içerik nesnesi isteği ise bir girdiyi veya çıktıyı aktarır. Bir blob indirmesini yürütülmüş bir eylem veya eylem önbelleği isabeti olarak değerlendirmeyin.

Çalıştırmanın eylem grafiği ve yapılandırılmış hataları için bkz. <.localized_link href="/guides/features/build-insights/once">Once derleme içgörüler</.localized_link>.

## Sürekli entegrasyon {#continuous-integration}

<.localized_link href="/guides/integrations/continuous-integration#once">Sürekli entegrasyonda Once</.localized_link> bölümünde açıklandığı gibi `TUIST_TOKEN` veya Once'in arayüzsüz OIDC oturum açma yöntemini kullanın. Kimlik bilgilerini `once.toml` dışında tutun.

Hesabın <.localized_link href="/guides/features/cache#restrict-uploads-to-ci">önbellek yükleme politikası</.localized_link>, sonuçların kimler tarafından yayınlanabileceğini belirler. Salt okunur bir geliştirici, önbellek yazarı olmadan CI tarafından üretilen girişleri tüketebilir.

Bağlantı yeniden denemeleri ve sorun giderme için bkz. [Once'in Tuist entegrasyonu](https://buildonce.dev/docs/guide/infrastructure/tuist#connection-recovery). Yeniden denemeler, kesintiye uğramış yüklemelerin devam ettirilmesini sağlamaz.
