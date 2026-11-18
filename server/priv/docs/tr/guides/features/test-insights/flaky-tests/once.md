---
{
  "title": "Bir Kez Kararsız Testler",
  "titleTemplate": ":title · Kararsız Testler · Test İçgörüleri · Özellikler · Kılavuzlar · Tuist",
  "description": "Rapor edilen yeniden deneme girişimlerini ve CI geçmişini kullanarak bir kez kararsız testleri tespit edin ve inceleyin."
}
---
# Once kararsız testleri {#once-flaky-tests}

> [!IMPORTANT]
> **Gereksinimler**
>
> - Yapılandırılmış bireysel test sonuçlarıyla <.localized_link href="/guides/features/test-insights/once">Once test içgörülerini</.localized_link> yapılandırın.

<!-- @snippet: ./_intro -->

## Kararsızlık algılamanın çalışma biçimi {#how-it-works}

### Test yeniden denemeleri {#test-retries}

Bir runner aynı test için birden çok deneme bildirdiğinde Tuist bunları saklar. Başarısız olup ardından geçen bir test kararsız olarak raporlanır; sürekli başarısız olan bir test başarısız olarak kalır. Desteklenen durumlarda alttaki runner’da yeniden denemeleri etkinleştirin. Once’i Tuist’e bağlamak, her test hedefine otomatik olarak yeniden deneme eklemez.

### Çoklu çalıştırmalar arası algılama {#cross-run-detection}

Paylaşılan test geçmişi, Tuist’in CI’daki aynı test ve commit için geçen ve başarısız sonuçları karşılaştırmasını da sağlar. Bu karşılaştırma için Once commit ve CI bağlamını bildirmelidir; yerel çalıştırmalar görünür kalır ancak otomatik olarak çapraz çalıştırma kararsızlığı kanıtı oluşturmaz.

Senaryolar yerel hedef, test paketi ve senaryo adına göre tanımlanır. Geçmişlerini korumak için bu kimlikleri sabit tutun ve güvenilirliği hedefin genel sonucundan çıkarmak yerine eksiksiz senaryo bazlı raporlar kullanın.

## Kararsız testleri inceleme {#investigate-flaky-tests}

Denemelerini, hatalarını ve etkilenen CI commit’lerini karşılaştırmak için Tuist’te test senaryosunun geçmişini açın. Paylaşılan test sorguları ayrıca <.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocol araçları</.localized_link> üzerinden kullanılabilir; böylece bir kodlama ajanı bildirilen aynı sonuçları inceleyebilir.

## Kararsız testleri yönetme {#managing-flaky-tests}

Bir hatayı incelerken testin detay sayfasından onu kararsız olarak işaretleyebilir veya işareti kaldırabilirsiniz. Varsayılan kararsız-test algılama otomasyonu, kurtarma penceresi sonunda (genellikle başka bir tetikleyici olmadan 14 gün) bayrağı temizler.

Once projeleri şu anda bir **Otomasyonlar** ayarları sekmesi sunmuyor. Algılama ve kaydedilmiş test durumu mevcuttur, ancak karantina zorlamalı derleme sistemleri için belgelenen ayarlar akışı Once için henüz sunulmamaktadır.

## Karantina {#quarantining}

Tuist bildirilen senaryoları kaydedilmiş karantina durumlarına atayabilir, ancak yerel Once istemcisi şu anda Tuist’in **Susturulmuş** veya **Atlanan** politikalarını çekip uygulamaz. Bu durumu Tuist’te değiştirmek, Once’in testi yürütmesini durdurmaz veya başarısızlığının CI’yı engellemesini kaldırmaz.

Çalışma zamanında karantinaya ihtiyaç duyduğunuzda runner’ınızın kendi filtreleme veya hata politikasını kullanın. Komutun çıkış kodunu değiştirmek için yalnızca kontrol paneli durumuna güvenmeyin.

## Slack bildirimleri {#slack-notifications}

Once projeleri şu anda kararsız-test Slack uyarılarını yapılandırmak için proje ayarları akışını sunmuyor. Bildirilen kararsız durumunu kendi bildirimlerinizle entegre etmek için aşağıdaki paylaşılan test sorgularını kullanın.

<!-- @snippet: ./_querying -->
