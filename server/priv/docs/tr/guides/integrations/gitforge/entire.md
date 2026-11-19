---
{
  "title": "Entire",
  "titleTemplate": ":title | Git forges | Entegrasyonlar | Kılavuzlar | Tuist",
  "description": "Tuist derleme, test, paket ve önizleme içgörülerini Entire Trails üzerinde yayınlayın."
}
---
# Entire entegrasyonu {#entire}

Tuist, [Entire](https://entire.com) depolarındaki açık ve taslak [Trails](https://docs.entire.com/guides/trails/overview) üzerinde derleme, test, önizleme ve paket içgörülerini yayınlayabilir. Her Trail, çalıştırma raporu, başarısız ve kararsız testler için tüm değişiklik bulguları ve yeni içgörüler geldikçe Tuist tarafından güncellenen bir özet yorum içeren bir Tuist kapısı alır; bu sayede her yükleme için yeni bir yorum oluşturulmaz.

Eklentinin kurulması derlemeleri veya testleri çalıştırmaz. Mevcut iş akışlarınız sonuçları Tuist'e yüklemeye devam eder ve entegrasyon bu sonuçları Traillerinize taşır.

## Kurulum {#setup}

Tuist hesabının yöneticisi eklentiyi kurar, ardından depoları Tuist projelerine bağlar; tıpkı <.localized_link href="/guides/integrations/gitforge/github">GitHub</.localized_link> ve <.localized_link href="/guides/integrations/gitforge/origin">Origin</.localized_link> entegrasyonlarında olduğu gibi.

1. Hesabınızın **Ayarlar → Entegrasyonlar** bölümünü açın.
2. Entire kartında **Entire eklentisini kur** seçeneğini belirleyin. Tuist ile paylaşmak istediğiniz Entire projesini ve depolarını seçin.

   ![Hesap entegrasyonlarından Entire eklentisini kurun](/images/guides/integrations/gitforge/entire/integrations.png)

3. Tuist'e dönün ve **Yeni proje bağlantısı ekle** seçeneğini belirleyin. **Bağlanacak depoyu seçin** alanında Tuist projenizi ve Entire deponuzu seçin, ardından **Bağlantı Oluştur** seçeneğini belirleyin. Yalnızca bir Tuist projesi varsa otomatik olarak seçilir.

   ![Bir Tuist projesini bir Entire deposuna bağlayın](/images/guides/integrations/gitforge/entire/add-project-connection.png)

4. Mevcut, kimliği doğrulanmış Tuist komutlarınızı kullanarak CI'dan sonuç yüklemeye devam edin; örneğin bir <.localized_link href="/guides/server/authentication#account-tokens">hesap jetonu</.localized_link> kullanabilirsiniz. Tuist, sonuçları her Trail'in mevcut baş commit'iyle eşleştirir, bu nedenle Entire'a özel bayraklara gerek yoktur.

Bir Tuist projesi, GitHub bağlantısını korurken aynı zamanda Entire'a da yayın yapabilir; bu durum, Entire deposu bir GitHub deposunun yansıması olduğunda faydalıdır. Entegrasyon, Tuist'in CI yürütücüsünü gerektirmez veya CI sağlayıcınızı değiştirmez.

## Raporlar ve izinler {#reports-and-permissions}

Eklentiyi kurarken, Trailleri bulmak ve raporları yayınlamak için ihtiyaç duyduğu izinleri verirsiniz:

| İzin | Kullanım amacı |
| --- | --- |
| Depo içeriği: okuma | Trail olaylarını almak ve baş commit'leriyle birlikte açık ve taslak Trailleri bulmak. |
| Kontroller: yazma | Trail'in baş commit'inde Tuist kapısını yayınlamak. |
| Bulgular: yazma | Başarısız ve kararsız testleri bulgu olarak yayınlamak ve daha yeni bir raporun yerine geçtiği bulguları çözmek. |
| Tartışmalar: yazma | Özet yorumu göndermek ve güncellemek. Bu izin olmadan bile Tuist kapıyı ve bulguları yayınlamaya devam eder. |

Tuist'in kaynak kodunuza yazma erişimine veya Trailleri birleştirmek için izne ihtiyacı yoktur.

Tuist her Trail'de üç şey yayınlar:

- **Kapı:** Tuist kontrolü, çalıştırma raporu ve Tuist'teki projeye bir bağlantıyla birlikte **Kapılar** altında görünür. Tuist eklentisi altında listelenir ve bir GitHub yansımasının **Kontroller** kapısından ayrıdır. Yüklenen sonuçlar, beklenen her CI işinin tamamlanıp tamamlanmadığını Tuist'e bildirmediği için `neutral` sonucuyla tamamlanır; Entire bunu başarılı olarak gösterir. Bulgular olsa bile birleştirmeyi engellemez, bu nedenle geçiş/başarısızlık zorlaması için CI sağlayıcınızın gerekli kontrollerini koruyun.
- **Bulgular:** Başarısız testler ve kararsız testler, Tuist'teki test senaryolarına bağlantı veren tüm değişiklik bulguları olarak görünür. Bulgular, Entire'ın Agent inceleme kapısına katkıda bulunmaz.
- **Özet yorum:** GitHub ve Origin'deki pull request yorumuna benzer şekilde, her proje Trail başına bir Tuist Çalıştırma Raporu yorumu tutar. Silerseniz, sonraki rapor bunu yeniden gönderir.

Yeni sonuçlar geldikçe, Tuist Trail'in mevcut baş commit'i için güncellenmiş bir rapor yayınlar ve yerine geçen bulguları çözer. Yeniden denemeler, Entire'ın bir yayına verdiği yanıt kaybolduğunda bile yinelenen incelemeler, bulgular veya yorumlar oluşturmaz. Bir Trail'i açmak veya yeniden açmak, baş commit'i için zaten yüklenmiş sonuçları alır. Mevcut baş commit için hiçbir sonuç yoksa, Tuist yeni bir şey yayınlamaz; bu nedenle eski bir commit'in kapısı yeni baş için gereksinimleri karşılayamaz. Kapatılmış ve birleştirilmiş Trailler güncellenmez.

Entire kartı proje-depo bağlantılarını listeler. Eklentiyi kaldırmadan raporlamayı durdurmak için bir proje bağlantısında **Yönet → Bağlantıyı kaldır** seçeneğini belirleyin. Zaten yayınlanmış raporlar Entire'da kalır ve yeniden bağlanma yeni raporlar başlatır. Eklentinin depo erişimini değiştirmek veya kaldırmak için Entire'daki projenin **Eklentiler** ayarlarını kullanın.

## Kendi sunucunuzda barındırılan sunucular {#server-configuration}

Kendi Tuist sunucunuzu barındırıyorsanız, önce dağıtımınız için bir Entire eklentisi kaydedin ve yapılandırın. <.localized_link href="/guides/server/self-host/server#platform-entire">Entire kendi kendine barındırma talimatlarını</.localized_link> takip edin, ardından hesapları ve projeleri bağlamak için yukarıdaki kurulum adımlarına dönün.
