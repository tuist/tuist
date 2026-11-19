---
{
  "title": "Origin",
  "titleTemplate": ":title | Git forges | Entegrasyonlar | Kılavuzlar | Tuist",
  "description": "Yerel Cursor Origin depolarını Tuist çekme isteği raporlarına bağlayın."
}
---
# Origin entegrasyonu {#origin}

Tuist, yerel [Cursor Origin](https://cursor.com/docs/api/origin) depolarındaki pull request’lere derleme, test, önizleme ve paket raporları gönderebilir. Her yükleme için yeni bir yorum bırakmak yerine uygulamanın mevcut Tuist Run Report’unu günceller.

Uygulamayı yüklemek derleme veya test çalıştırmaz. Mevcut iş akışlarınız sonuçları Tuist’e yüklemeye devam eder; entegrasyon bu sonuçları pull request’lerinize taşır.

## Kurulum {#setup}

Tuist hesabının bir yöneticisi **Ayarlar → Entegrasyonlar** bölümünü açmalı, Origin kartında **Install Origin App** seçeneğini seçmeli ve Cursor’da erişimi onaylamalıdır. Tuist’in erişmesi gereken Origin hesabını veya ad alanını ve depoları seçin, ardından Tuist’e dönün. Bağlantı bireysel bir projeye değil, Tuist hesabına aittir.

Uygulamayı doğrudan Origin üzerinden de yükleyebilirsiniz. Erişimi onayladıktan sonra gerekirse Tuist’e giriş yapın ve bağlanacak organizasyonu seçin. Yalnızca yönettiğiniz organizasyonlar ve kişisel hesabınız kullanılabilir. Kişisel hesabınız tek seçenek olsa bile Tuist her zaman sorar. Ekibinizin Tuist organizasyonu listede yoksa **Create an organization** seçeneğini belirleyin veya yöneticilerinden birinden sizi yönetici yapmasını isteyin. Sayfa açıkken liste güncellenir; Tuist’e döndükten sonraki on dakika içinde organizasyonu seçtiğiniz sürece yeniden başlamanıza gerek kalmadan görünür. Süreci Tuist’ten başlatırsanız organizasyon zaten seçili olur ve bu adım atlanır.

Depo seçim modalını açmak için **Add new project connection** seçeneğini belirleyin. Bağlı olmayan bir Tuist projesi ve bağlı Origin hesabından keşfedilen depolardan birini seçin, ardından **Create Connection** seçeneğini belirleyin. Birden fazla Origin hesabı bağlıysa önce hesabı seçin. Bağlantı için yalnızca yerel Origin depoları kullanılabilir. Tuist, projeyi bağlamadan önce pull request erişimini tekrar doğrular ve deposunun varsayılan dalını benimser.

Cursor’ın onay akışını yeni bir sekmede açmak, depo erişimini ayarlamak veya başka bir Origin hesabı bağlamak için **Manage integration** kullanın. Depo yükleme hataları, başarılı boş depo listesinden ayrı olarak **Retry** gösterir.

Sonuç yüklemelerini kimlik doğrulamak için bir <.localized_link href="/guides/server/authentication#account-tokens">account token</.localized_link> kullanın.

## Raporlar ve izinler {#reports-and-permissions}

Uygulamayı onaylarken, depoları bağlamak ve raporları yayınlamak için gereken izinleri verirsiniz:

| İzin | Kullanım amacı |
| --- | --- |
| Pull requests: read | Raporlanan commit için açık pull request’i bulur. |
| Pull request reviews: read and write | Tuist Run Report yorumunu okur, gönderir ve günceller. |
| Repository metadata: read | Depoları ve varsayılan dallarını keşfeder. Origin tarafından otomatik olarak dahil edilir. |

Tuist’in kaynak kodunuza erişmesine veya pull request’leri birleştirmek için izne ihtiyacı yoktur.

Sonuçları bir pull request ile ilişkilendirmek için yüklemeler, deponun Origin klon URL’sini, Git ref’ini ve tam commit SHA’sını içermelidir. Tuist raporu yalnızca bu bilgiler mevcut head commit’teki tek bir açık pull request’i tanımladığında gönderir. Geçerliliği yitmiş commit’lere ait sonuçlar mevcut raporun üzerine yazılmaz.

Origin kartı proje-depo bağlantılarını listeler. Uygulamayı kaldırmadan bir projenin raporlamasını durdurmak için proje bağlantısında **Manage → Remove connection** seçeneğini belirleyin. Erişimi iptal etmek için uygulamayı Cursor’dan kaldırın; Tuist, kurulum bildirimini işlediğinde kurulumu ve ilgili proje bağlantılarını kaldırır.

## Kendi sunucunuzda barındırma {#server-configuration}

Kendi Tuist sunucunuzu barındırıyorsanız, önce dağıtımınız için bir Origin uygulaması kaydedip yapılandırın. <.localized_link href="/guides/server/self-host/server#platform-origin">Origin self-hosting instructions</.localized_link> adımlarını izleyin, ardından hesapları ve projeleri bağlamak için yukarıdaki kurulum adımlarına dönün.
