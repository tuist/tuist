---
{
  "title": "Struo uzak yürütme",
  "titleTemplate": ":title · Çalıştırıcılar · Özellikler · Kılavuzlar · Tuist",
  "description": "Uygun Struo grafik komutu eylemlerini Tuist'in Linux tabanlı uzak yürütme işçilerinde çalıştırın."
}
---
# Struo uzaktan yürütme {#struo-remote-execution}

<a id="once-remote-execution"></a>

Paylaşımlı önbellek, başka bir makinenin zaten tamamladığı işlerin tekrarlanmasını önler. Uzaktan yürütme ayrıca uygun önbellek isabet etmeme durumlarını bilgisayarınızdan taşır: Struo, grafik komut eylemlerini Tuist'in tek kullanımlık Linux çalışanlarında planlar ve çıktılarını aynı proje önbelleği üzerinden alır.

> [!NOTE]
> Uzaktan yürütme şu anda yalnızca davetle kullanılabilir. Hesabınız için erişim istemek üzere [bize ulaşın](mailto:contact@tuist.dev).

> [!IMPORTANT]
> **Gereksinimler**
>
> - Uzaktan yürütme özelliği etkinleştirilmiş ve yeterli yürütme kapasitesine sahip bir Tuist hesabı.
> - Tuist uzaktan yürütme desteğine sahip bir Struo sürümü.
> - Çalışan imajını, önbellek uç noktasını, eşzamanlılığı ve mutlak bir yürütme dizinini duyuran uyumlu bir sunucu. Dizini belirtmeyen sunucular mevcut Struo istemcisiyle uyumlu değildir; Struo işi yüklemeye başlamadan önce durur.
> - Duyurulan çalışan imajı içinde `linux/amd64` üzerinde çalışabilen komutlar ve araç zincirleri.

Bu işlem tüm bir CI işini değil, yalnızca grafik eylemlerini çalıştırır. Struo'yu yapılandırmak GitHub veya GitLab iş akışı düzenlemesini yüklemez.

## Kurulum {#setup}

<.localized_link href="/guides/get-started/struo-project">Struo ile başlayın</.localized_link> kılavuzunu tamamlayın. Önbellekleme ve yürütme için aynı Tuist sağlayıcısını seçin ve hizmet tarafından duyurulan çalışan imajını sabitleyin:

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

Projenin önbelleğini okuyup yazabilen kimlik bilgileriyle kimlik doğrulaması yapın, ardından uzaktan yürütmeyi talep edin:

```bash
struo build --remote MyTarget
```

Hedefi ve imaj etiketini kendi değerlerinizle değiştirin. Struo, işi yüklemeden önce duyurulan imajı, yürütme dizinini, önbellek hedefini ve hesap kapasitesini kontrol eder. Önbellek ve yürütme aynı projeyi işaret etmelidir.

## Çalışanlar için eylemleri hazırlama {#prepare-actions-for-workers}

- Girişleri ve çıkışları tanımlayın. Çıkışlar, eylemin çalışma dizini altında kalmalıdır.
- Araçları başlatan bilgisayardaki mutlak yollar yerine çalışan imajı içinde çözün.
- Tekrarlanması güvenli olan eylemleri kullanın: bir çalışan hatası veya hizmet yeniden başlatması başka bir yürütmeye neden olabilir.
- Zaman aşımlarını hizmetin on dakikalık eylem sınırı içinde tutun. Ağ engelleme gibi desteklenmeyen gereksinimler, sessizce yerel olarak çalışmak yerine başarısız olur.

Struo, hesabın duyurduğu eylem eşzamanlılığına saygı gösterir ve hizmet kuyruğu dolu olduğunda geri çekilir. İmajı değiştirmek derleme yapılandırmasını ve önbelleğe alınmış sonuçları ayırarak uyumsuz çalışan imajları arasında yeniden kullanımı engeller.

## Uzaktan yürütmeyi inceleme {#inspect-remote-execution}

Proje kenar çubuğunda bir **Uzaktan yürütme** sayfası bulunur. **Analitikler** kartı, seçilen dönemin yürütmelerini ve toplam yürütme süresini <.localized_link href="/guides/features/cache/bazel-cache#running-actions-and-usage">Eylemleri çalıştırma ve kullanım</.localized_link> bölümünde açıklandığı gibi gösterir. Struo çalışma telemetrisi henüz uzaktan yürütmeyi yerel eylemlerden ayırt etmediği için sayfada yürütme başına uzaktan zamanlamalar veya çalışan yürütmeler bulunmaz. Bu boşluğu açıklar ve kaydedilen eylem ayrıntıları için **Derleme Çalıştırmaları** bağlantısını sunar. Şu anda çalışan ve kuyrukta bekleyen uzaktan eylemler `get_remote_execution_activity` MCP aracı ve REST uç noktasından erişilebilir. Her ikisi de çalışan kanallarından değil, yürütme hizmetinden gelir.

Kuyruğa alma, kimlik doğrulama yenileme ve önbellek uç noktası geçersiz kılmaları için [Struo'nun uzaktan yürütme kılavuzuna](https://struo.run/docs/guide/infrastructure/tuist#run-actions-on-tuist-workers) bakın. Ortaya çıkan çalıştırmaları incelemek için <.localized_link href="/guides/features/build-insights/struo">Struo derleme içgörülerini</.localized_link> takip edin.
