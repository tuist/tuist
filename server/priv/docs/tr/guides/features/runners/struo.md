---
{
  "title": "Struo uzak yürütme",
  "titleTemplate": ":title · Çalıştırıcılar · Özellikler · Kılavuzlar · Tuist",
  "description": "Uygun Struo grafik komutu eylemlerini Tuist'in Linux tabanlı uzak yürütme işçilerinde çalıştırın."
}
---
# Struo uzak yürütme {#struo-remote-execution}

<a id="once-remote-execution"></a>

Paylaşımlı önbellek, başka bir makinenin zaten tamamladığı işlerin tekrarlanmasını önler. Uzak yürütme ayrıca uygun önbellek isabetlerini bilgisayarınızdan taşır: Struo, graf komut eylemlerini Tuist’in tek kullanımlık Linux çalışanlarında planlar ve çıktıları aynı proje önbelleği üzerinden alır.

> [!NOTE]
> Uzak yürütme şu anda yalnızca davetle kullanılabilir. Hesabınız için erişim istemek üzere [bize ulaşın](mailto:contact@tuist.dev).

> [!IMPORTANT]
> **Gereksinimler**
>
> - Uzak yürütmenin etkin olduğu ve yeterli yürütme kapasitesine sahip bir Tuist hesabı.
> - Tuist uzak yürütme desteğine sahip bir Struo sürümü.
> - Çalışan imajını, önbellek uç noktasını, eşzamanlılığı ve mutlak bir yürütme dizinini ilan eden uyumlu bir sunucu. Dizini atlayan sunucular mevcut Struo istemcisiyle uyumlu değildir; Struo işi yüklemeden önce durur.
> - İlan edilen çalışan imajı içinde `linux/amd64` üzerinde çalışabilen komutlar ve araç zincirleri.

Bu işlem graf eylemlerini çalıştırır, tüm bir CI işini değil. Struo’yu yapılandırmak GitHub veya GitLab iş akışı düzenlemesini kurmaz.

## Kurulum {#setup}

<.localized_link href="/guides/get-started/struo-project">Struo ile başlayın</.localized_link> kılavuzunu tamamlayın. Önbellekleme ve yürütme için aynı Tuist sağlayıcısını seçin ve hizmet tarafından ilan edilen çalışan imajını sabitleyin:

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
struo build --remote MyTarget
```

Hedefi ve imaj etiketini kendi değerlerinizle değiştirin. Struo, işi yüklemeden önce ilan edilen imajı, yürütme dizinini, önbellek hedefini ve hesap kapasitesini kontrol eder. Önbellek ve yürütme aynı projeyi işaret etmelidir.

## Çalışanlar için eylemleri hazırlama {#prepare-actions-for-workers}

- Girişleri ve çıkışları bildirin. Çıkışlar, eylemin çalışma dizini altında kalmalıdır.
- Araçları başlatan bilgisayardaki mutlak yollarda değil, çalışan imajı içinde çözümleyin.
- Tekrarlanması güvenli olan eylemler kullanın: bir çalışan arızası veya hizmet yeniden başlatması başka bir yürütmeye neden olabilir.
- Zaman aşımlarını hizmetin on dakikalık eylem sınırı içinde tutun. Desteklenmeyen gereksinimler, ağ engellemesi dahil olmak üzere, sessizce yerel olarak çalışmak yerine başarısız olur.

Struo, hesabın ilan ettiği eylem eşzamanlılığına saygı gösterir ve hizmet kuyruğu dolu olduğunda geri çekilir. İmajı değiştirmek derleme yapılandırmasını ve önbelleğe alınmış sonuçları ayırarak uyumsuz çalışan imajları arasında yeniden kullanımı engeller.

## Uzak yürütmeyi inceleme {#inspect-remote-execution}

Proje kenar çubuğunda bir **Uzak yürütme** sayfası bulunur. **Analitika** kartı, seçilen dönemin yürütmelerini ve toplam yürütme süresini <.localized_link href="/guides/features/cache/bazel-cache#running-actions-and-usage">Eylemleri çalıştırma ve kullanım</.localized_link> bölümünde açıklandığı gibi gösterir. Struo çalışma telemetrisi henüz uzak yürütmeyi yerel eylemlerden ayırt etmediği için sayfada çalışma başına uzak zamanlamalar veya devam eden çalışmalar yer almaz. Bu boşluğu açıklar ve kaydedilmiş eylem ayrıntıları için **Derleme Çalışmaları** bağlantısını sunar. Şu anda çalışan ve kuyrukta bekleyen uzak eylemler `get_remote_execution_activity` MCP aracı ve onun REST uç noktasından erişilebilir. Her ikisi de çalışan kanallarından değil, yürütme hizmetinden gelir.

Kuyruğa alma, kimlik doğrulama yenileme ve önbellek uç noktası geçersiz kılmaları için [Struo’nun uzak yürütme kılavuzuna](https://struo.run/docs/guide/infrastructure/tuist#run-actions-on-tuist-workers) bakın. Ortaya çıkan çalışmaları incelemek için <.localized_link href="/guides/features/build-insights/struo">Struo derleme içgörüleri</.localized_link> kılavuzunu takip edin.
