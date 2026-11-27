---
{
  "title": "Struo Kararsız Testler",
  "titleTemplate": ":title · Kararsız Testler · Test İçgörüleri · Özellikler · Kılavuzlar · Tuist",
  "description": "Raporlanan yeniden deneme girişimlerini ve CI geçmişini kullanarak Struo kararsız testlerini tespit edin ve inceleyin."
}
---
# Struo kararsız testleri {#struo-flaky-tests}

<a id="once-flaky-tests"></a>

> [!IMPORTANT]
> **Gereksinimler**
>
> - Yapılandırılmış bireysel test sonuçlarıyla <.localized_link href="/guides/features/test-insights/struo">Struo test içgörülerini</.localized_link> yapılandırın.

<!-- @snippet: ./_intro -->

## Kararsızlık algılamanın nasıl çalıştığı {#how-it-works}

### Test yeniden denemeleri {#test-retries}

Bir runner aynı test için birden fazla deneme bildirdiğinde Tuist bunları saklar. Başarısız olup ardından geçen bir test kararsız olarak raporlanır; sürekli başarısız olan testler başarısız olarak kalır. Desteklenen durumlarda alttaki runner’da yeniden denemeleri etkinleştirin. Struo’yu Tuist’e bağlamak, her test hedefine otomatik olarak yeniden deneme eklemez.

### Çalıştırmalar arası algılama {#cross-run-detection}

Paylaşılan test geçmişi, Tuist’in CI’daki aynı test ve commit için geçen ve başarısız sonuçları karşılaştırmasına da olanak tanır. Bu karşılaştırma için Struo’nun commit ve CI bağlamını bildirmesi gerekir; yerel çalıştırmalar görünür kalır ancak otomatik olarak çalıştırmalar arası kararsızlık kanıtı oluşturmaz.

Senaryolar yerel hedef, suite ve senaryo adına göre tanımlanır. Geçmişlerini korumak için bu kimlikleri sabit tutun ve güvenilirliği hedefin genel sonucundan çıkarmak yerine senaryo bazında eksiksiz raporlar kullanın.

## Kararsız testleri inceleme {#investigate-flaky-tests}

Denemelerini, hatalarını ve etkilenen CI commit’lerini karşılaştırmak için Tuist’te test senaryosunun geçmişini açın. Paylaşılan test sorguları ayrıca <.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocol araçları</.localized_link> üzerinden kullanılabilir, böylece bir kodlama ajanı aynı raporlanan sonuçları inceleyebilir.

## Kararsız testleri yönetme {#managing-flaky-tests}

Bir hatayı incelerken ayrıntı sayfasından bir testi kararsız olarak işaretleyebilir veya işareti kaldırabilirsiniz. Varsayılan kararsız-test algılama otomasyonu, kurtarma penceresi sonunda (genellikle başka bir tetikleyici olmadan 14 gün) bayrağı temizler.

Struo projeleri şu anda bir **Otomasyonlar** ayarları sekmesi sunmuyor. Algılama ve saklanan test durumu mevcuttur, ancak karantina uygulaması olan derleme sistemleri için belgelenen ayar iş akışı henüz Struo için sunulmamaktadır.

## Karantina {#quarantining}

Tuist bildirilen senaryoları saklanan karantina durumlarına atayabilir, ancak yerel Struo istemcisi şu anda Tuist’in **Susturulmuş** veya **Atlanmış** ilkelerini çekip uygulamıyor. Bu durumu Tuist’te değiştirmek, Struo’nun testi yürütmesini engellemez veya başarısızlığının CI’yı engellemesini durdurmaz.

Çalıştırma zamanında karantinaya ihtiyaç duyduğunuzda runner’ınızın kendi filtreleme veya hata politikasını kullanın. Komutun çıkış kodunu değiştirmek için yalnızca pano durumuna güvenmeyin.

## Slack bildirimleri {#slack-notifications}

Struo projeleri şu anda kararsız-test Slack uyarılarını yapılandırmak için proje ayarları iş akışını sunmuyor. Raporlanan kararsız durumunu kendi bildirimlerinizle entegre etmek için aşağıdaki paylaşılan test sorgularını kullanın.

<!-- @snippet: ./_querying -->
