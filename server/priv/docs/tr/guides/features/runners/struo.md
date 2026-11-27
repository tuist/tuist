---
{
  "title": "Struo uzaktan yürütme",
  "titleTemplate": ":title · Çalıştırıcılar · Özellikler · Kılavuzlar · Tuist",
  "description": "Uygun Struo graf komut eylemlerini Tuist'in Linux uzaktan yürütme işçilerinde çalıştırın."
}
---
# Struo uzaktan yürütme {#struo-remote-execution}

<a id="once-remote-execution"></a>

Paylaşılan önbellekleme, başka bir makinenin zaten tamamladığı işlerin tekrarlanmasını önler. Uzaktan yürütme ayrıca uygun önbellek isabetlerini bilgisayarınızdan uzaklaştırır: Struo, grafik komut eylemlerini Tuist'in tek kullanımlık Linux çalışanlarında zamanlar ve çıktıları aynı proje önbelleği üzerinden alır.

> [!NOTE]
> Uzaktan yürütme şu anda yalnızca davetle kullanılabilir. Hesabınız için erişim talep etmek üzere [bize ulaşın](mailto:contact@tuist.dev).

> [!IMPORTANT]
> **Gereksinimler**
>
> - Uzaktan yürütmenin etkin olduğu ve yürütme kapasitesinin bulunduğu bir Tuist hesabı.
> - Tuist uzaktan yürütme desteğine sahip bir Struo sürümü.
> - Çalışan imajını, önbellek uç noktasını, eşzamanlılığı ve mutlak bir yürütme dizinini duyuran uyumlu bir sunucu. Dizini atlayan sunucular mevcut Struo istemcisiyle uyumlu değildir; Struo işi yüklemeden önce durur.
> - Duyurulan çalışan imajı içinde `linux/amd64` üzerinde çalışabilen komutlar ve araç zincirleri.

Bu, tüm bir CI işini değil, grafik eylemlerini çalıştırır. Struo'yu yapılandırmak GitHub veya GitLab iş akışı orkestrasyonunu kurmaz.

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

Projenin önbelleğini okuyup yazabilen kimlik bilgileriyle kimlik doğrulaması yapın, ardından uzaktan yürütmeyi isteyin:

```bash
struo build --remote MyTarget
```

Hedefi ve imaj etiketini kendi değerlerinizle değiştirin. Struo, işi yüklemeden önce duyurulan imajı, yürütme dizinini, önbellek hedefini ve hesap kapasitesini kontrol eder. Önbellek ve yürütme aynı projeyi işaret etmelidir.

## Çalışanlar için eylemleri hazırlama {#prepare-actions-for-workers}

- Girişleri ve çıkışları bildirin. Çıkışlar, eylemin çalışma dizini altında kalmalıdır.
- Araçları başlatan bilgisayardaki mutlak yollarda değil, çalışan imajı içinde çözümleyin.
- Tekrarlanması güvenli olan eylemler kullanın: bir çalışan arızası veya hizmet yeniden başlatması başka bir yürütmeye neden olabilir.
- Zaman aşımlarını hizmetin on dakikalık eylem sınırı içinde tutun. Desteklenmeyen gereksinimler, ağ engellemesi dahil olmak üzere, sessizce yerel olarak çalışmak yerine başarısız olur.

Struo, hesabın duyurduğu eylem eşzamanlılığına saygı duyar ve hizmet kuyruğu dolu olduğunda geri çekilir. İmajı değiştirmek derleme yapılandırmasını ve önbelleğe alınmış sonuçları ayırarak uyumsuz çalışan imajları arasında yeniden kullanımı engeller.

## Uzaktan yürütmeyi inceleme {#inspect-remote-execution}

Proje kenar çubuğunda bir **Uzaktan yürütme** sayfası bulunur. **Analitik** kartı, seçilen dönemin yürütmelerini ve toplam yürütme süresini gösterir; bu konu <.localized_link href="/guides/features/cache/bazel-cache#running-actions-and-usage">Eylemleri çalıştırma ve kullanım</.localized_link> bölümünde açıklanmıştır. 2.19.0 sonrası Struo sürümlerinde her uzaktan eylem ait olduğu Struo çalıştırmasını adlandırır, bu nedenle sayfa ayrıca kuyruk ve yürütme sürelerini grafikler ve çalıştırma durumlarını, sonuçlarını ve zamanlamalarını listeler; çalışan çalıştırmalar önce gelir. Bir çalıştırma, **Derleme Çalıştırmaları** bölümündeki sayfasını açar. Daha eski istemcilerden gelen çalıştırmalar ve uzaktan önbellekten yanıtlanan eylemler burada sayılmaz. Şu anda çalışan ve kuyruktaki uzaktan eylemler `get_remote_execution_activity` MCP aracından ve bunun REST uç noktasından edinilebilir. Her ikisi de çalışan şeritlerinden değil, yürütme hizmetinden gelir.

Kuyruğa alma, kimlik doğrulama yenileme ve önbellek uç noktası geçersiz kılmaları için [Struo'nun uzaktan yürütme kılavuzuna](https://struo.run/docs/guide/infrastructure/tuist#run-actions-on-tuist-workers) bakın. Ortaya çıkan çalıştırmaları incelemek için <.localized_link href="/guides/features/build-insights/struo">Struo derleme içgörülerini</.localized_link> takip edin.
