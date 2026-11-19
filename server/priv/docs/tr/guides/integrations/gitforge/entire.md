---
{
  "title": "Entire",
  "titleTemplate": ":title | Git forges | Entegrasyonlar | Kılavuzlar | Tuist",
  "description": "Tuist derleme, test, paket ve önizleme içgörülerini Entire Trails üzerinde yayınlayın."
}
---
# Entire entegrasyonu {#entire}

Tuist, [Entire](https://entire.com) depolarındaki açık ve taslak [Trails](https://docs.entire.com/guides/trails/overview) üzerinde derleme, test, önizleme ve paket içgörülerini yayınlayabilir. Her Trail, çalıştırma raporu, başarısız ve kararsız testler için tüm değişiklik bulguları ve yeni içgörüler geldikçe Tuist’in her yükleme için yeni bir tane yayınlamak yerine güncellediği bir özet yorum içeren bir Tuist kapısı alır.

Eklentiyi yüklemek derlemeleri veya testleri çalıştırmaz. Mevcut iş akışlarınız sonuçları Tuist’e yüklemeye devam eder ve entegrasyon bu sonuçları Trails’lerinize getirir.

## Kurulum {#setup}

Tuist hesabının bir yöneticisi eklentiyi yükler, ardından <.localized_link href="/guides/integrations/gitforge/github">GitHub</.localized_link> ve <.localized_link href="/guides/integrations/gitforge/origin">Origin</.localized_link> entegrasyonlarında olduğu gibi depoları Tuist projelerine bağlar.

1. Hesabınızın **Ayarlar → Entegrasyonlar** bölümünü açın.
2. Entire kartında **Entire eklentisini yükle** seçeneğini belirleyin. Tuist ile paylaşmak istediğiniz Entire projesini ve depolarını seçin.

   ![Hesap entegrasyonlarından Entire eklentisini yükleyin](/images/guides/integrations/gitforge/entire/integrations.png)

3. Tuist’e dönün ve **Yeni proje bağlantısı ekle** seçeneğini belirleyin. **Bağlanacak depoyu seçin** alanında Tuist projenizi ve Entire deponuzu seçin, ardından **Bağlantı Oluştur** seçeneğini belirleyin. Yalnızca bir Tuist projesi varsa otomatik olarak seçilir.

   ![Bir Tuist projesini bir Entire deposuna bağlayın](/images/guides/integrations/gitforge/entire/add-project-connection.png)

4. Mevcut kimliği doğrulanmış Tuist komutlarınızı kullanarak CI’dan sonuç yüklemeye devam edin; örneğin bir <.localized_link href="/guides/server/authentication#account-tokens">hesap jetonu</.localized_link> kullanabilirsiniz. Tuist, sonuçları her Trail’in mevcut head commit’iyle eşleştirir, bu nedenle Entire’a özel bayraklara gerek yoktur.

Bir Tuist projesi, GitHub bağlantısını korurken Entire’a da yayın yapabilir; bu, Entire deposu bir GitHub deposunun yansıması olduğunda kullanışlıdır. Entegrasyon, Tuist’in CI yürütücüsünü gerektirmez veya CI sağlayıcınızı değiştirmez.

## Raporlar ve izinler {#reports-and-permissions}

Eklentiyi yüklerken, Trails’leri bulmak ve raporları yayınlamak için ihtiyaç duyduğu izinleri verirsiniz:

| İzin | Kullanım amacı |
| --- | --- |
| Depo içeriği: okuma | Trail olaylarını almak ve head commit’leriyle birlikte açık ve taslak Trails’leri bulmak. |
| Kontroller: yazma | Trail’in head commit’inde Tuist kapısını yayınlamak. |
| Bulgular: yazma | Başarısız ve kararsız testleri bulgu olarak yayınlamak ve daha yeni bir raporun yerine geçtiği bulguları çözmek. |
| Tartışmalar: yazma | Özet yorumu göndermek ve güncellemek. Bu olmadan bile Tuist kapıyı ve bulguları yayınlamaya devam eder. |

Tuist’in kaynak kodunuza yazma erişimine veya Trails’leri birleştirmek için izne ihtiyacı yoktur.

Tuist, her Trail üzerinde üç şey yayınlar:

- **Kapı:** Tuist kontrolü, çalıştırma raporu ve Tuist’teki projeye bir bağlantıyla birlikte **Kapılar** altında görünür. GitHub yansımasının **Kontroller** kapısından ayrı olarak Tuist eklentisi altında listelenir. Yüklenen sonuçlar, beklenen her CI işinin tamamlanıp tamamlanmadığını Tuist’e bildirmediği için `neutral` sonucuyla tamamlanır; Entire bunu başarılı olarak gösterir. Bulgular olsa bile birleştirmeyi engellemez, bu nedenle pass/fail zorlaması için CI sağlayıcınızın gerekli kontrollerini koruyun.
- **Bulgular:** Başarısız testler ve kararsız testler, Tuist’teki test senaryolarına bağlantı veren tüm değişiklik bulguları olarak görünür. Bulgular, Entire’ın Agent inceleme kapısına katkıda bulunmaz.
- **Özet yorum:** GitHub ve Origin’deki pull request yorumu gibi, her proje Trail başına bir Tuist Çalıştırma Raporu yorumu tutar. Silerseniz, sonraki rapor onu tekrar gönderir.

Yeni sonuçlar geldikçe Tuist, Trail’in mevcut head commit’i için güncellenmiş bir rapor yayınlar ve yerine geçen bulguları çözer. Yeniden denemeler, Entire’ın bir yayına verdiği yanıt kaybolduğunda bile yinelenen incelemeler, bulgular veya yorumlar oluşturmaz. Bir Trail’i açmak veya yeniden açmak, head commit’i için zaten yüklenmiş sonuçları alır. Mevcut head commit için hiçbir sonuç yoksa Tuist yeni bir şey yayınlamaz, bu nedenle eski bir commit’in kapısı yeni head için gereksinimleri karşılayamaz. Kapatılmış ve birleştirilmiş Trails güncellenmez.

Entire kartı proje-depo bağlantılarını listeler. Eklentiyi kaldırmadan raporlamayı durdurmak için bir proje bağlantısında **Yönet → Bağlantıyı kaldır** seçeneğini belirleyin. Zaten yayınlanmış raporlar Entire’da kalır ve yeniden bağlanmak yeni raporlar başlatır. Eklentinin depo erişimini değiştirmek veya kaldırmak için Entire’daki projenin **Eklentiler** ayarlarını kullanın.

## Kendi sunucularınızı barındırma {#server-configuration}

Kendi Tuist sunucunuzu barındırıyorsanız, önce dağıtımınız için bir Entire eklentisi kaydedip yapılandırın. <.localized_link href="/guides/server/self-host/server#platform-entire">Entire kendi kendine barındırma talimatlarını</.localized_link> izleyin, ardından hesapları ve projeleri bağlamak için yukarıdaki kurulum adımlarına dönün.
