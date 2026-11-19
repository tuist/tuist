---
{
  "title": "Kararsız Testleri Belirleme",
  "titleTemplate": ":title · Kararsız Testler · Test Analizleri · Özellikler · Kılavuzlar · Tuist",
  "description": "Raporlanan yeniden deneme girişimlerini ve CI geçmişini kullanarak kararsız testleri tespit edin ve inceleyin."
}
---
# Struo kararsız testleri {#struo-flaky-tests}

<a id="once-flaky-tests"></a>

> [!IMPORTANT]
> **Gereksinimler**
>
> - Yapılandırılmış bireysel test sonuçlarıyla <.localized_link href="/guides/features/test-insights/struo">Struo test içgörülerini</.localized_link> yapılandırın.

<!-- @snippet: ./_intro -->

## Kararsızlık algılamanın çalışma biçimi {#how-it-works}

### Test yeniden denemeleri {#test-retries}

Bir runner aynı test için birden fazla deneme bildirdiğinde Tuist bunları saklar. Başarısız olup ardından geçen bir test kararsız olarak raporlanır; sürekli başarısız olan bir test başarısız olarak kalır. Desteklenen durumlarda alttaki runner’da yeniden denemeleri etkinleştirin. Struo’yu Tuist’e bağlamak, her test hedefine otomatik olarak yeniden deneme eklemez.

### Çoklu çalıştırma algılama {#cross-run-detection}

Paylaşılan test geçmişi, Tuist’in CI’daki aynı test ve commit için geçen ve başarısız sonuçları karşılaştırmasına da olanak tanır. Bu karşılaştırma için Struo’nun commit ve CI bağlamını bildirmesi gerekir; yerel çalıştırmalar görünür kalır ancak otomatik çoklu çalıştırma kararsızlığı kanıtı oluşturmaz.

Senaryolar yerel hedef, suite ve senaryo adına göre tanımlanır. Geçmişlerini korumak için bu kimlikleri sabit tutun ve güvenilirliği hedefin genel sonucundan çıkarmak yerine eksiksiz senaryo bazlı raporlar kullanın.

## Kararsız testleri inceleme {#investigate-flaky-tests}

Denemelerini, başarısızlıklarını ve etkilenen CI commit’lerini karşılaştırmak için Tuist’te test senaryosunun geçmişini açın. Paylaşılan test sorguları ayrıca <.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocol araçları</.localized_link> aracılığıyla kullanılabilir, böylece bir kodlama ajanı aynı bildirilen sonuçları inceleyebilir.

## Kararsız testleri yönetme {#managing-flaky-tests}

Bir başarısızlığı incelerken ayrıntı sayfasından bir testi kararsız olarak işaretleyebilir veya işaretini kaldırabilirsiniz. Varsayılan kararsız test algılama otomasyonu, kurtarma penceresi sonunda (genellikle başka bir tetikleyici olmadan 14 gün) bayrağı temizler.

Struo projeleri şu anda bir **Otomasyonlar** ayarları sekmesini göstermiyor. Algılama ve saklanan test durumu mevcuttur, ancak karantina uygulaması olan derleme sistemleri için belgelenen ayar iş akışı henüz Struo için sunulmuyor.

## Karantina {#quarantining}

Tuist bildirilen senaryoları saklanan karantina durumlarına atayabilir, ancak yerel Struo istemcisi şu anda Tuist’in **Susturulmuş** veya **Atlanmış** politikalarını çekip uygulamıyor. Bu durumu Tuist’te değiştirmek, Struo’nun testi yürütmesini durdurmaz veya başarısızlığının CI’yı engellemesini önlemez.

Çalıştırma zamanında karantinaya ihtiyacınız olduğunda runner’ınızın kendi filtreleme veya başarısızlık politikasını kullanın. Komutun çıkış kodunu değiştirmek için yalnızca panodaki duruma güvenmeyin.

## Slack bildirimleri {#slack-notifications}

Struo projeleri şu anda kararsız test Slack uyarılarını yapılandırmak için proje ayarları iş akışını göstermiyor. Bildirilen kararsız durumunu kendi bildirimlerinizle entegre etmek için aşağıdaki paylaşılan test sorgularını kullanın.

<!-- @snippet: ./_querying -->
