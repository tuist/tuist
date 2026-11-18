---
{
  "title": "Once uzak yürütme",
  "titleTemplate": ":title · Çalıştırıcılar · Özellikler · Kılavuzlar · Tuist",
  "description": "Uygun Once grafik komut eylemlerini Tuist'in Linux uzak yürütme işçilerinde çalıştırın."
}
---
# Once uzak yürütme {#once-remote-execution}

Paylaşımlı önbellek, başka bir makinenin zaten tamamladığı işlerin tekrarlanmasını önler. Uzak yürütme ayrıca uygun önbellek isabetlerini bilgisayarınızdan taşır: Once, graf komut eylemlerini Tuist’in tek kullanımlık Linux çalışanlarında planlar ve çıktılarını aynı proje önbelleği üzerinden alır.

> [!IMPORTANT]
> **Gereksinimler**
>
> - Uzak yürütmenin etkin olduğu ve kullanılabilir yürütme kapasitesine sahip bir Tuist hesabı.
> - Tuist uzak yürütme desteğine sahip bir Once sürümü.
> - Çalışan imajını, önbellek uç noktasını, eşzamanlılığı ve mutlak bir yürütme dizinini duyuran uyumlu bir sunucu. Dizini atlayan sunucular mevcut Once istemcisiyle uyumlu değildir; Once işi yüklemeye başlamadan önce durur.
> - Duyurulan çalışan imajı içinde `linux/amd64` üzerinde çalışabilen komutlar ve araç zincirleri.

Bu işlem graf eylemlerini çalıştırır, tüm bir CI işini değil. Once’i yapılandırmak GitHub veya GitLab iş akışı orkestrasyonu kurmaz.

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

Projenin önbelleğini okuyup yazabilen kimlik bilgileriyle kimlik doğrulaması yapın, ardından uzak yürütmeyi isteyin:

```bash
once build --remote MyTarget
```

Hedefi ve imaj etiketini kendi değerlerinizle değiştirin. Once, işi yüklemeden önce duyurulan imajı, yürütme dizinini, önbellek hedefini ve hesap kapasitesini kontrol eder. Önbellek ve yürütme aynı projeyi işaret etmelidir.

## Çalışanlar için eylemleri hazırlama {#prepare-actions-for-workers}

- Girişleri ve çıktıları bildirin. Çıktılar, eylemin çalışma dizini altında kalmalıdır.
- Araçları başlatan bilgisayardaki mutlak yollarda değil, çalışan imajı içinde çözümleyin.
- Tekrarlanması güvenli olan eylemler kullanın: bir çalışan arızası veya hizmet yeniden başlatması başka bir yürütmeye neden olabilir.
- Zaman aşımlarını hizmetin on dakikalık eylem sınırı içinde tutun. Ağ erişiminin engellenmesi dahil desteklenmeyen gereksinimler, sessizce yerel olarak çalışmak yerine başarısız olur.

Once, hesabın duyurduğu eylem eşzamanlılığına uyar ve hizmet kuyruğu dolu olduğunda geri çekilir. İmajı değiştirmek derleme yapılandırmasını ve önbelleğe alınmış sonuçları ayırarak uyumsuz çalışan imajları arasında yeniden kullanımı engeller.

Kuyruğa alma, kimlik doğrulama yenileme ve önbellek uç noktası geçersiz kılmaları için [Once’un uzak yürütme kılavuzu](https://buildonce.dev/docs/guide/infrastructure/tuist#run-actions-on-tuist-workers) sayfasına bakın. Ortaya çıkan çalıştırmaları incelemek için <.localized_link href="/guides/features/build-insights/once">Once derleme içgörülerini</.localized_link> takip edin.
