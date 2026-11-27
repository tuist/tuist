---
{
  "title": "Origin",
  "titleTemplate": ":title | Git forges | Entegrasyonlar | Kılavuzlar | Tuist",
  "description": "Yerel Cursor Origin depolarını Tuist çekme isteği raporlarına bağlayın."
}
---
# Origin entegrasyonu {#origin}

Tuist, yerel [Cursor Origin](https://cursor.com/docs/api/origin) depolarındaki pull request’lere derleme, test, önizleme ve paket raporları gönderebilir. Her yükleme için yeni bir yorum eklemek yerine uygulamanın mevcut Tuist Çalıştırma Raporunu günceller.

Uygulamayı yüklemek derleme veya test çalıştırmaz. Mevcut iş akışlarınız sonuçları Tuist’e yüklemeye devam eder ve entegrasyon bu sonuçları pull request’lerinize taşır.

## Kurulum {#setup}

Tuist hesabının yöneticisi **Ayarlar → Entegrasyonlar** bölümünü açmalı, Origin kartında **Origin Uygulamasını Yükle** seçeneğini belirlemeli ve Cursor’da erişimi onaylamalıdır. Tuist’in erişmesi gereken Origin hesabını veya ad alanını ve depoları seçin, ardından Tuist’e dönün. Bağlantı bireysel bir projeye değil, Tuist hesabına aittir.

Uygulamayı doğrudan Origin üzerinden de yükleyebilirsiniz. Erişimi onayladıktan sonra gerekirse Tuist’te oturum açın ve bağlanacak organizasyonu seçin. Yalnızca yönettiğiniz organizasyonlar ve kişisel hesabınız kullanılabilir. Kişisel hesabınız tek seçenek olsa bile Tuist her zaman sorar. Ekibinizin Tuist organizasyonu listede yoksa **Bir organizasyon oluştur** seçeneğini belirleyin veya yöneticilerinden birinden sizi yönetici yapmasını isteyin. Sayfa açıkken liste güncellenir; Tuist’e döndükten sonraki on dakika içinde organizasyonu seçmeniz koşuluyla baştan başlamadan organizasyon görünür. Tuist’ten başlarsanız organizasyon zaten seçili olur ve bu adım atlanır.

Depo seçim penceresini açmak için **Yeni proje bağlantısı ekle** seçeneğini belirleyin. Bağlı olmayan bir Tuist projesi ve bağlı Origin hesabından keşfedilen depolardan birini seçin, ardından **Bağlantı Oluştur** seçeneğini belirleyin. Birden fazla Origin hesabı bağlıysa önce hesabı seçin. Bağlantı için yalnızca yerel Origin depoları kullanılabilir. Tuist, projeyi bağlamadan önce pull request erişimini tekrar doğrular ve deponun varsayılan dalını benimser.

Cursor’un izin akışını yeni bir sekmede açmak, depo erişimini ayarlamak veya başka bir Origin hesabı bağlamak için **Entegrasyonu yönet** seçeneğini kullanın. Depo yükleme hataları, başarılı boş depo listesinden ayrı olarak **Yeniden Dene** gösterir.

Sonuç yüklemelerini kimlik doğrulamak için bir <.localized_link href="/guides/server/authentication#account-tokens">hesap jetonu</.localized_link> kullanın.

## Raporlar ve izinler {#reports-and-permissions}

Uygulamayı onayladığınızda, depoları bağlamak ve raporları yayınlamak için gereken izinleri verirsiniz:

| İzin | Kullanım amacı |
| --- | --- |
| Pull request’ler: okuma | Raporlanan commit için açık pull request’i bulur. |
| Pull request incelemeleri: okuma ve yazma | Tuist Çalıştırma Raporu yorumunu okur, gönderir ve günceller. |
| Depo meta verileri: okuma | Depoları ve varsayılan dallarını keşfeder. Origin tarafından otomatik olarak dahil edilir. |

Tuist’in kaynak kodunuza erişmesine veya pull request’leri birleştirmek için izne ihtiyacı yoktur.

Sonuçları bir pull request ile ilişkilendirmek için yüklemeler deponun Origin klon URL’sini, Git referansını ve tam commit SHA’sını içermelidir. Tuist raporu yalnızca bunlar mevcut head commit’inde tek bir açık pull request’i tanımladığında gönderir. Geçerliliği yitmiş commit’lere ait sonuçlar mevcut raporun üzerine yazılmaz.

Origin kartı proje-depo bağlantılarını listeler. Uygulamayı kaldırmadan bir proje bağlantısının raporlamasını durdurmak için proje bağlantısında **Yönet → Bağlantıyı kaldır** seçeneğini belirleyin. Erişimi iptal etmek için uygulamayı Cursor’dan kaldırın; Tuist, kurulum bildirimini işlediğinde kurulumu ve proje bağlantılarını kaldırır.

## Kendi sunucunuzda barındırılan sunucular {#server-configuration}

Kendi Tuist sunucunuzu barındırıyorsanız önce dağıtımınız için bir Origin uygulaması kaydedip yapılandırın. <.localized_link href="/guides/server/self-host/server#platform-origin">Origin kendi kendine barındırma talimatlarını</.localized_link> izleyin, ardından hesapları ve projeleri bağlamak için yukarıdaki kurulum adımlarına dönün.
