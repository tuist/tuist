---
{
  "title": "Entire",
  "titleTemplate": ":title | Git forges | Entegrasyonlar | Kılavuzlar | Tuist",
  "description": "Tuist derleme, test, paket ve önizleme içgörülerini Entire Trails üzerinde yayınlayın."
}
---
# Entire entegrasyonu {#entire}

Tuist, [Entire](https://entire.com) depolarındaki açık ve taslak [Trails](https://docs.entire.com/guides/trails/overview) üzerinde derleme, test, ön izleme ve paket içgörülerini yayınlayabilir. Her Trail, çalışma raporunu, başarısız ve kararsız testler için tüm değişiklik bulgularını ve Tuist'in her yükleme için yeni bir tane göndermek yerine yeni içgörüler geldikçe güncellediği bir özet yorumu içeren bir Tuist kapısına sahip olur.

Eklentiyi yüklemek derlemeleri veya testleri çalıştırmaz. Mevcut iş akışlarınız sonuçları Tuist'e yüklemeye devam eder ve entegrasyon bu sonuçları Traillerinize getirir.

## Kurulum {#setup}

Tuist hesabının yöneticisi eklentiyi yükler, ardından depoları <.localized_link href="/guides/integrations/gitforge/github">GitHub</.localized_link> ve <.localized_link href="/guides/integrations/gitforge/origin">Origin</.localized_link> entegrasyonlarında olduğu gibi Tuist projelerine bağlar.

1. Hesabınızın **Ayarlar → Entegrasyonlar** bölümünü açın.
2. Entire kartında **Entire eklentisini yükle** seçeneğini belirleyin. Tuist ile paylaşmak istediğiniz Entire projesini ve depolarını seçin.

   ![Hesap entegrasyonlarından Entire eklentisini yükleyin](/images/guides/integrations/gitforge/entire/integrations.png)

3. Tuist'e geri dönün ve **Yeni proje bağlantısı ekle** seçeneğini belirleyin. **Bağlanacak depoyu seçin** alanında Tuist projenizi ve Entire deponuzu seçin, ardından **Bağlantı Oluştur** seçeneğini belirleyin. Yalnızca bir Tuist projesi mevcutsa otomatik olarak seçilir.

   ![Bir Tuist projesini bir Entire deposuna bağlayın](/images/guides/integrations/gitforge/entire/add-project-connection.png)

4. Mevcut, kimliği doğrulanmış Tuist komutlarınızı kullanarak CI'dan sonuç yüklemeye devam edin; örneğin bir <.localized_link href="/guides/server/authentication#account-tokens">hesap jetonu</.localized_link> kullanabilirsiniz. Tuist, sonuçları her Trail'in mevcut baş commit'iyle eşleştirir, bu nedenle Entire'a özel bayraklara gerek yoktur.

Bir Tuist projesi, Entire repository'si bir GitHub repository'sinin yansıması olduğunda yararlı olan GitHub bağlantısını korurken aynı zamanda Entire'a da yayın yapabilir. Entegrasyon, Tuist'in CI yürütücüsünü gerektirmez veya CI sağlayıcınızı değiştirmez.

## Raporlar ve izinler {#reports-and-permissions}

Eklentiyi yüklerken, Trailleri bulmak ve raporları yayınlamak için ihtiyaç duyduğu izinleri verirsiniz:

| İzin | Kullanım amacı |
| --- | --- |
| Depo içeriği: okuma | Trail olaylarını almak ve baş commit'leriyle birlikte açık ve taslak Trailleri bulmak. |
| Kontroller: yazma | Trail'in baş commit'inde Tuist kapısını yayınlamak. |
| Bulgular: yazma | Başarısız ve kararsız testleri bulgu olarak yayınlamak ve daha yeni bir raporun değiştirdiği bulguları çözmek. |
| Tartışmalar: yazma | Özet yorumu göndermek ve güncellemek. Bu olmadan bile Tuist kapıyı ve bulguları yayınlamaya devam eder. |

Tuist'in kaynak kodunuza yazma erişimine veya Trailleri birleştirme iznine ihtiyacı yoktur.

Tuist her Trail üzerinde üç şey yayınlar:

- **Kapı:** Tuist kontrolü, çalışma raporu ve Tuist'teki projeye bir bağlantıyla birlikte **Kapılar** altında görünür. GitHub yansısının **Kontroller** kapısından ayrı olarak Tuist eklentisi altında listelenir. Yüklenen sonuçlar, beklenen her CI işinin tamamlanıp tamamlanmadığını Tuist'e bildirmediği için `neutral` sonucuyla tamamlanır ve Entire bunu geçmiş olarak gösterir. Bulgular olsa bile birleştirmeyi engellemez, bu nedenle pass/fail zorlaması için CI sağlayıcınızın gerekli kontrollerini koruyun.
- **Bulgular:** Başarısız testler ve kararsız testler, Tuist'teki test senaryolarına bağlantı veren tüm değişiklik bulguları olarak görünür. Bulgular, Entire'ın Agent inceleme kapısına katkıda bulunmaz.
- **Özet yorum:** GitHub ve Origin'deki pull request yorumu gibi, her proje Trail başına bir Tuist Çalışma Raporu yorumu tutar. Silerseniz, sonraki rapor onu tekrar gönderir.

Yeni sonuçlar geldiğinde, Tuist Trail'in mevcut baş commit'i için güncellenmiş bir rapor yayınlar ve değiştirdiği bulguları çözer. Yeniden denemeler, Entire'ın bir yayına verdiği yanıt kaybolduğunda bile yinelenen incelemeler, bulgular veya yorumlar oluşturmaz. Bir Trail'i açmak veya yeniden açmak, baş commit'i için zaten yüklenmiş sonuçları alır. Mevcut baş commit için hiçbir sonuç yoksa, Tuist yeni bir şey yayınlamaz, bu nedenle daha eski bir commit'in kapısı yeni baş için gereksinimleri karşılayamaz. Kapatılan ve birleştirilen Trailler güncellenmez.

Entire kartı proje-depo bağlantılarını listeler. Eklentiyi kaldırmadan raporlamayı durdurmak için bir proje bağlantısında **Yönet → Bağlantıyı kaldır** seçeneğini belirleyin. Zaten yayınlanmış raporlar Entire'da kalır ve yeniden bağlanmak yeni raporlar başlatır. Eklentinin depo erişimini değiştirmek veya kaldırmak için Entire'daki projenin **Eklentiler** ayarlarını kullanın.

## Kendi barındırılan sunucular {#server-configuration}

Kendi Tuist sunucunuzu barındırıyorsanız, önce dağıtımınız için bir Entire eklentisi kaydedin ve yapılandırın. <.localized_link href="/guides/server/self-host/server#platform-entire">Entire kendi kendine barındırma talimatlarını</.localized_link> izleyin, ardından hesapları ve projeleri bağlamak için yukarıdaki kurulum adımlarına dönün.
