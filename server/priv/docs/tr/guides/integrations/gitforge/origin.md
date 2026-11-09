---
{
  "title": "Origin",
  "titleTemplate": ":title | Git forjları | Entegrasyonlar | Kılavuzlar | Tuist",
  "description": "Yerel Cursor Origin depolarını Tuist çekme isteği raporlarına bağlayın."
}
---
# Origin entegrasyonu {#origin}

Tuist, yerel [Cursor Origin](https://cursor.com/docs/api/origin) depolarındaki çekme isteklerine derleme, test, önizleme ve paket raporları gönderebilir. Her yükleme için yeni bir yorum bırakmak yerine uygulamanın mevcut Tuist Çalıştırma Raporunu günceller.

Uygulamayı yüklemek derleme veya test çalıştırmaz. Mevcut iş akışlarınız sonuçları Tuist’e yüklemeye devam eder; entegrasyon bu sonuçları çekme isteklerinize taşır.

## Kurulum {#setup}

Tuist hesabının yöneticisi **Ayarlar → Entegrasyonlar** bölümünü açmalı, Origin kartında **Origin Uygulamasını Yükle** seçeneğini belirlemeli ve Cursor’da erişimi onaylamalıdır. Tuist’in erişmesi gereken Origin hesabını veya ad alanını ve depoları seçin, ardından Tuist’e dönün. Bağlantı bireysel bir projeye değil, Tuist hesabına aittir.

Uygulamayı doğrudan Origin üzerinden de yükleyebilirsiniz. Erişimi onayladıktan sonra gerekirse Tuist’e giriş yapın ve bağlanacak organizasyonu seçin. Yalnızca yönettiğiniz organizasyonlar ve kişisel hesabınız kullanılabilir. Tek bir hesap mevcutsa Tuist, seçim ekranını göstermeden otomatik olarak bağlanır. Tuist’ten başlarsanız organizasyon zaten seçilidir ve bu adım atlanır.

Depo seçim penceresini açmak için **Yeni proje bağlantısı ekle** seçeneğini belirleyin. Bağlı olmayan bir Tuist projesi ve bağlı Origin hesabından keşfedilen depolardan birini seçin, ardından **Bağlantı Oluştur** seçeneğini belirleyin. Birden fazla Origin hesabı bağlıysa önce hesabı seçin. Yalnızca yerel Origin depoları bağlantı için kullanılabilir. Tuist, projeyi bağlamadan önce çekme isteği erişimini yeniden doğrular ve deposunun varsayılan dalını benimser.

Cursor’un onay akışını yeni bir sekmede açmak, depo erişimini ayarlamak veya başka bir Origin hesabı bağlamak için **Entegrasyonu yönet** seçeneğini kullanın. Depo yükleme hataları **Yeniden Dene** seçeneğini gösterir; bu, başarılı ancak boş depo listesinden ayrıdır.

Sonuç yüklemelerini kimlik doğrulamak için bir <.localized_link href="/guides/server/authentication#account-tokens">hesap jetonu</.localized_link> kullanın.

## Raporlar ve izinler {#reports-and-permissions}

Uygulamayı onaylarken, depoları bağlamak ve raporları yayınlamak için gerekli izinleri verirsiniz:

| İzin | Kullanım amacı |
| --- | --- |
| Çekme istekleri: okuma | Bildirilen commit için açık çekme isteğini bulma. |
| Çekme isteği incelemeleri: okuma ve yazma | Tuist Çalıştırma Raporu yorumunu okuma, gönderme ve güncelleme. |
| Depo meta verileri: okuma | Depoları ve varsayılan dallarını keşfetme. Origin tarafından otomatik olarak dahil edilir. |

Tuist’in kaynak kodunuza erişmesine veya çekme isteklerini birleştirmek için izne ihtiyacı yoktur.

Sonuçları bir çekme isteğiyle ilişkilendirmek için yüklemeler, deponun Origin klon URL’sini, Git referansını ve tam commit SHA değerini içermelidir. Tuist raporu yalnızca bu bilgiler mevcut baş commitinde tek bir açık çekme isteğini tanımladığında gönderir. Geçersiz kılınan commitlere ait sonuçlar mevcut raporun üzerine yazılmaz.

Origin kartı proje-depo bağlantılarını listeler. Bir proje bağlantısında uygulamayı kaldırmadan raporlamayı durdurmak için **Yönet → Bağlantıyı kaldır** seçeneğini belirleyin. Erişimi iptal etmek için uygulamayı Cursor’dan kaldırın; Tuist, kurulum bildirimini işlediğinde kurulumu ve ilgili proje bağlantılarını kaldırır.

## Kendi sunucunuzda barındırılan sunucular {#server-configuration}

Kendi Tuist sunucunuzu barındırıyorsanız öncelikle dağıtımınız için bir Origin uygulaması kaydedip yapılandırın. <.localized_link href="/guides/server/self-host/server#platform-origin">Origin kendi kendine barındırma talimatlarını</.localized_link> izleyin, ardından hesapları ve projeleri bağlamak için yukarıdaki kurulum adımlarına dönün.
