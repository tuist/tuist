---
{
  "title": "Once uzak yürütme",
  "titleTemplate": ":title · Runners · Özellikler · Kılavuzlar · Tuist",
  "description": "Uygun Once grafik komutu eylemlerini Tuist'in Linux uzak yürütme işçilerinde çalıştırın."
}
---
# Once uzak yürütme {#once-remote-execution}

Paylaşılan önbellek, başka bir makinenin zaten tamamladığı işlerin tekrarlanmasını önler. Uzak yürütme ayrıca uygun önbellek kaçırma durumlarını bilgisayarınızdan taşır: Once, grafik komut eylemlerini Tuist’in tek kullanımlık Linux çalışanlarında planlar ve çıktıları aynı proje önbelleği üzerinden alır.

> [!NOTE]
> Uzak yürütme şu anda yalnızca davetle kullanılabilir. Hesabınız için erişim talep etmek üzere [bize ulaşın](mailto:contact@tuist.dev).

> [!IMPORTANT]
> **Gereksinimler**
>
> - Uzak yürütmenin etkin olduğu ve yeterli yürütme kapasitesine sahip bir Tuist hesabı.
> - Tuist uzak yürütme desteğine sahip bir Once sürümü.
> - Çalışan imajını, önbellek uç noktasını, eşzamanlılığı ve mutlak bir yürütme dizinini duyuran uyumlu bir sunucu. Dizini belirtmeyen sunucular mevcut Once istemcisiyle uyumlu değildir; Once işi yüklemeye başlamadan önce durur.
> - Duyurulan çalışan imajı içinde `linux/amd64` üzerinde çalışabilen komutlar ve araç zincirleri.

Bu işlem grafik eylemlerini çalıştırır, tüm bir CI işini değil. Once’i yapılandırmak GitHub veya GitLab iş akışı orkestrasyonu kurmaz.

## Kurulum {#setup}

<.localized_link href="/guides/get-started/once-project">Once ile başlayın</.localized_link> kılavuzunu tamamlayın. Önbellekleme ve yürütme için aynı Tuist sağlayıcısını seçin ve hizmet tarafından duyurulan çalışan imajını sabitleyin:

```toml
[infrastructures.tuist]
kind = "tuist"
account = "acme"
project = "app"
execution_image = "sha-REPLACE_WITH_THE_IMAGE_TAG"

[infrastructure.cache]
provider = "tuist"

[infrastructure.execution]
provider = "tuist"
```

Projenin önbelleğini okuyup yazabilen kimlik bilgileriyle kimlik doğrulaması yapın, ardından uzak yürütmeyi talep edin:

```bash
once build --remote MyTarget
```

Hedefi ve imaj etiketini kendi değerlerinizle değiştirin. Once, işi yüklemeden önce duyurulan imajı, yürütme dizinini, önbellek hedefini ve hesap kapasitesini kontrol eder. Önbellek ve yürütme aynı projeyi işaret etmelidir.

## Çalışanlar için eylemleri hazırlama {#prepare-actions-for-workers}

- Girişleri ve çıktıları bildirin. Çıktılar, eylemin çalışma dizininin altında kalmalıdır.
- Araçları başlatan bilgisayardaki mutlak yollarda değil, çalışan imajı içinde çözün.
- Tekrarlanması güvenli olan eylemleri kullanın: bir çalışan arızası veya hizmet yeniden başlatması başka bir yürütmeye neden olabilir.
- Zaman aşımlarını hizmetin on dakikalık eylem sınırı içinde tutun. Desteklenmeyen gereksinimler, ağ erişiminin engellenmesi dahil olmak üzere, sessizce yerel olarak çalışmak yerine başarısız olur.

Once, hesabın duyurduğu eylem eşzamanlılığına saygı gösterir ve hizmet kuyruğu dolu olduğunda geri çekilir. İmajı değiştirmek, derleme yapılandırmasını ve önbelleğe alınmış sonuçları ayırarak uyumsuz çalışan imajları arasında yeniden kullanımı engeller.

## Uzak yürütmeyi inceleme {#inspect-remote-execution}

Proje kenar çubuğunda bir **Uzak yürütme** sayfası bulunur. **Analitik** kartı, seçilen dönemin yürütmelerini ve toplam yürütme süresini <.localized_link href="/guides/features/cache/bazel-cache#running-actions-and-usage">Eylemleri çalıştırma ve kullanım</.localized_link> bölümünde açıklandığı gibi gösterir. Once çalışma telemetrisi henüz uzak yürütmeyi yerel eylemlerden ayırt etmediği için sayfada yürütme başına uzak zamanlamalar veya çalışan yürütmeler yer almaz. Bu boşluğu açıklar ve kaydedilmiş eylem ayrıntıları için **Derleme Çalıştırmaları** bağlantısını sunar. Şu anda çalışan ve kuyrukta bekleyen uzak eylemler `get_remote_execution_activity` MCP aracı ve bunun REST uç noktasından erişilebilir. Her ikisi de çalışan kanallarından değil, yürütme hizmetinden gelir.

Kuyruğa alma, kimlik doğrulama yenileme ve önbellek uç noktası geçersiz kılmaları için [Once’un uzak yürütme kılavuzuna](https://buildonce.dev/docs/guide/infrastructure/tuist#run-actions-on-tuist-workers) bakın. Ortaya çıkan çalıştırmaları incelemek için <.localized_link href="/guides/features/build-insights/once">Once derleme içgörülerini</.localized_link> takip edin.
