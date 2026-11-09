---
{
  "title": "GitLab CI",
  "titleTemplate": ":title · CI sağlayıcıları · Çalıştırıcılar · Özellikler · Kılavuzlar · Tuist",
  "description": "Pipeline etiketleriyle makine seçimi yaparak GitLab CI işlerini Tuist Çalıştırıcılar üzerinde çalıştırın."
}
---
# GitLab CI {#gitlab-ci}

<!-- @snippet: ./_invite-only -->

Boru hatlarınız GitLab'da kalır. Tuist, her iş için izole bir Linux veya macOS makinesi sağlar ve günlüklerini ile sonucunu GitLab'e ve Tuist panosuna bildirir. GitLab 19.3 veya daha yenisi gereklidir. GitLab.com ve genel HTTPS üzerinden erişilebilen kendi kendine yönetilen örnekler desteklenir.

1. **GitLab çalıştırıcısı oluşturun.** Projenizin **Ayarlar → CI/CD → Çalıştırıcılar** bölümünde bir proje çalıştırıcısı oluşturun. Grup çalıştırıcısı da kullanabilirsiniz. Kullanmak istediğiniz tüm Tuist profil etiketlerini çalıştırıcı etiketleri olarak ekleyin, örneğin `tuist-linux` ve `tuist-macos`, ve **Etiketsiz işleri çalıştır** seçeneğini devre dışı bırakın. GitLab'in gösterdiği, `glrt-` ile başlayan kimlik doğrulama belirtecini saklayın. Kendi makinenize bir çalıştırıcı kurmanıza gerek yoktur.
2. **Tuist'te bir kez bağlanın.** **Ayarlar → Entegrasyonlar** bölümünde, GitLab CI kartındaki **Bağlan** seçeneğini belirleyin. GitLab URL'nizi ve çalıştırıcı kimlik doğrulama belirtecinizi girin. Bağlantı, farklı profiller kullanan işlere hizmet verebilir. Belirteçler şifrelenerek saklanır ve bir daha asla görüntülenmez. İsteğe bağlı olarak, birleştirme isteği boru hatlarının önbellek birimlerini kaydedebilmesi için bir API erişim belirteci ekleyin; bkz. [Birleştirme isteği boru hatları](#merge-request-pipelines).
3. **Her işte makineyi seçin.** İşin `tags` alanında tam olarak bir <.localized_link href="/guides/features/runners/profiles">Tuist profil etiketi</.localized_link> ayarlayın. Kayıtlı GitLab çalıştırıcısında da bulunmaları koşuluyla diğer etiketlere izin verilir:

   ```yaml
   # .gitlab-ci.yml
   linux-check:
     tags: [tuist-linux]
     script:
       - uname -a

   test:
     tags: [tuist-macos]
     script:
       - tuist test
     retry:
       max: 2
       when: runner_system_failure
   ```

4. **İt ve izle.** Tuist bir dakika içinde yoklamaya başlar. İşler, GitLab işine, günlüklere ve makine metriklerine geri bağlantıyla birlikte **Çalıştırıcılar** altında görünür. GitLab, iş çalışırken günlükleri alır; Tuist ise iş bittiğinde maskelenmiş günlüğü alır.

Tuist, her atamadan `CI_JOB_TAGS` değerini okur ve profili bağlı Tuist hesabı içinde çözümler. Makineyi `CI_RUNNER_TAGS` üzerinden çıkarmaz veya varsayılan bir profil kullanmaz. Eksik, bilinmeyen veya birden fazla Tuist profil etiketi, edinilen işi GitLab günlüğündeki bir açıklamayla başarısız kılar. Boru hattı değişkenlerinizde `CI_JOB_TAGS` değerini geçersiz kılmayın.

## Yürütme ortamı {#execution-environment}

İşler, izole bir makine içinde GitLab'in **kabuk yürütücüsünü** kullanır. Kod çekme, CI değişkenleri, `before_script`, `script`, `after_script`, yapıtlar ve iptal işlemleri GitLab Runner tarafından yönetilir. Boru hattının `image:` ve `services:` ayarları bu kabuk ortamını yapılandırmaz; <.localized_link href="/guides/features/runners/profiles">çalıştırıcı imajında</.localized_link> yüklü araçları kullanın veya bunları betiğinizde kurun.

Yeniden kullanılabilir çalıştırıcı kimlik doğrulama belirteci Tuist sunucusunda kalır. Makineler yalnızca atanmış işleri için kimlik bilgilerini alır. Önbellek imzalama yetkileri şu anda GitLab işleri için verilmiyor. Özel Linux önbellek birimleri, GitLab’in API’si aracılığıyla iş kimliğini doğrular ve kaydetme iznini sağlar; üzerine yazılabilen CI değişkenleri güven tesis etmez.

GitLab, Tuist bir işi edindiği anda işi çalışıyor olarak işaretler ve zaman aşımını başlatır. Tuist’in zaten edindiği işler hesabınızın eşzamanlılık sınırını tüketirken, sonraki işler GitLab’de beklemeye devam eder. Edinilen bir iş, en fazla 12 saat olmak üzere iş zaman aşımına kadar bir makine bekler. Bu sürede hiçbir makine mevcut olmazsa, Tuist atamayı `runner_system_failure` ile başarısız kılar ve yukarıdaki yeniden deneme ilkesi GitLab’in bunu yeniden denemesine olanak tanır. Aynı ilke kayıp bir çalıştırıcı makinesini de kapsar.

## Belirteçleri döndürme ve bağlantıyı kesme {#rotating-tokens-and-disconnecting}

Bağlantının belirteçlerini güncelleyin ve döndürmek için **Değişiklikleri kaydet** seçeneğini belirleyin. Bir belirteci boş bırakmak mevcut kimlik bilgisini korur.

**Bağlantıyı kes**, edinmeyi durdurur ve bekleyen atamaları başarısız kılar. Çalışan işler kendi kimlik bilgileriyle devam eder. GitLab’e ulaşılamazsa, Tuist bekleyen atamaların iptalini yeniden denerken devre dışı bırakılmış bağlantıyı saklar. Bu atamalar sonuçlandığında bağlantı kaldırılır.

## Önbellek birimleri {#cache-volumes}

Xcode, modül ve Gradle önbelleklerini ve diğer dizinleri işler arasında <.localized_link href="/guides/features/runners/cache-volumes">önbellek birimleri</.localized_link> ile koruyun. Bunları kod çekmeden sonra ve bunları kullanan komutlardan önce ekleyin.

### Birleştirme isteği boru hatları {#merge-request-pipelines}

Projenin itme, zamanlanmış ve web boru hatları değişikliklerini önbellek birimlerine kaydeder. Birleştirme isteği boru hatları önbelleği kullanır ve değişikliklerini yalnızca bağlantıda bir API erişim belirteci olduğunda kaydeder:

1. GitLab’de, **Raporcu** rolüne ve `read_api` kapsamına sahip bir proje veya grup erişim belirteci oluşturun. Bir grup belirteci, Tuist çalıştırıcılarında çalışan gruptaki her projeyi kapsar.
2. **Ayarlar → Entegrasyonlar** bölümünde, GitLab CI kartındaki **API erişim belirteci** alanına yapıştırın ve **Değişiklikleri kaydet** seçeneğini belirleyin.

Tuist ardından her birleştirme isteği boru hattının birleştirme isteğini okur. Projenin kendi dalından açılan birleştirme isteklerinin boru hatları değişikliklerini birleştirme isteğinin kaynak dalı altında kaydeder, böylece çalıştırıcı profilinin <.localized_link href="/guides/features/runners/cache-volumes#choose-which-branches-save">dal ayarları</.localized_link> o dala uygulanır. Çatallardan gelen birleştirme istekleri asla kaydetmez. Tuist birleştirme isteğini okuyamazsa iş yine de çalışır ve önbelleği kullanır, ancak değişiklikleri atılır.
