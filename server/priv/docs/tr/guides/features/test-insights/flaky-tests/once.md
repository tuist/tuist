---
{
  "title": "Bir Zamanlar Kararsız Testler",
  "titleTemplate": ":title · Kararsız Testler · Test İçgörüler · Özellikler · Kılavuzlar · Tuist",
  "description": "Raporlanan yeniden deneme girişimlerini ve CI geçmişini kullanarak bir zamanlar kararsız olan testleri tespit edin ve inceleyin."
}
---
# Once kararsız testleri {#once-flaky-tests}

> [!IMPORTANT]
> **Gereksinimler**
>
> - Yapılandırılmış bireysel test sonuçlarıyla <.localized_link href="/guides/features/test-insights/once">Once test içgörülerini</.localized_link> yapılandırın.

<!-- @snippet: ./_intro -->

## Kararsızlık algılamanın nasıl çalıştığı {#how-it-works}

### Test yeniden denemeleri {#test-retries}

Bir runner aynı test için birden fazla deneme bildirdiğinde Tuist bunları saklar. Başarısız olup ardından geçen bir test kararsız olarak bildirilir; sürekli başarısız olanlar başarısızlık olarak kalır. Desteklenen durumlarda alttaki runner’da yeniden denemeleri etkinleştirin. Once’i Tuist’e bağlamak, her test hedefine otomatik olarak yeniden deneme eklemez.

### Çoklu çalıştırma algılama {#cross-run-detection}

Paylaşılan test geçmişi, Tuist’in CI’daki aynı test ve commit için geçen ve başarısız sonuçları karşılaştırmasını da sağlar. Bu karşılaştırma için Once commit ve CI bağlamını bildirmelidir; yerel çalıştırmalar görünür kalır ancak otomatik çoklu çalıştırma kararsızlığı kanıtı oluşturmaz.

Senaryolar yerel hedef, suite ve senaryo adına göre tanımlanır. Geçmişlerini korumak için bu kimlikleri sabit tutun ve güvenilirliği bir hedefin genel sonucundan çıkarmak yerine eksiksiz senaryo bazlı raporlar kullanın.

## Kararsız testleri inceleme {#investigate-flaky-tests}

Denemelerini, başarısızlıklarını ve etkilenen CI commit’lerini karşılaştırmak için Tuist’te test senaryosunun geçmişini açın. Paylaşılan test sorguları ayrıca <.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocol araçları</.localized_link> üzerinden kullanılabilir, böylece bir kodlama ajanı aynı bildirilen sonuçları inceleyebilir.

## Kararsız testleri yönetme {#managing-flaky-tests}

Bir başarısızlığı incelerken ayrıntı sayfasından bir testi kararsız olarak işaretleyebilir veya işareti kaldırabilirsiniz. Varsayılan kararsız-test algılama otomasyonu, kurtarma penceresi sonunda (genellikle başka bir tetikleme olmadan 14 gün) bayrağı temizler.

Once projeleri şu anda bir **Otomasyonlar** ayarları sekmesi sunmuyor. Algılama ve saklanan test durumu mevcut, ancak karantina zorlaması olan derleme sistemleri için belgelenen ayarlar iş akışı Once için henüz sunulmuyor.

## Karantina {#quarantining}

Tuist bildirilen senaryoları saklanan karantina durumlarına atayabilir, ancak yerel Once istemcisi şu anda Tuist’in **Sessize Alınmış** veya **Atlanmış** ilkelerini çekip uygulamıyor. Tuist’teki bu durumu değiştirmek, Once’in testi yürütmesini durdurmaz veya başarısızlığının CI’yı engellemesini sonlandırmaz.

Çalıştırma zamanında karantinaya ihtiyacınız olduğunda runner’ınızın kendi filtreleme veya başarısızlık ilkesini kullanın. Komutun çıkış kodunu değiştirmek için yalnızca pano durumuna güvenmeyin.

## Slack bildirimleri {#slack-notifications}

Once projeleri şu anda kararsız-test Slack uyarılarını yapılandırmak için proje ayarları iş akışını sunmuyor. Bildirilen kararsız durumunu kendi bildirimlerinizle entegre etmek için aşağıdaki paylaşılan test sorgularını kullanın.

<!-- @snippet: ./_querying -->
