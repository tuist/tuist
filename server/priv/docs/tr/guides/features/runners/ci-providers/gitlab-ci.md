---
{
  "title": "GitLab CI",
  "titleTemplate": ":title · CI sağlayıcıları · Çalıştırıcılar · Özellikler · Kılavuzlar · Tuist",
  "description": "Pipeline etiketleri aracılığıyla makine seçimiyle GitLab CI işlerini Tuist Çalıştırıcılar üzerinde çalıştırın."
}
---
# GitLab CI {#gitlab-ci}

<!-- @snippet: ./_invite-only -->

Boru hatlarınız GitLab'da kalır. Tuist, her iş için izole bir Linux veya macOS makinesi sağlar ve günlüklerini ile sonucunu GitLab'a ve Tuist kontrol paneline bildirir. GitLab 19.3 veya daha yeni bir sürüm gereklidir. GitLab.com ve genel HTTPS üzerinden erişilebilen kendi kendine barındırılan örnekler desteklenir.

1. **GitLab runner oluşturun.** Projenizin **Ayarlar → CI/CD → Runner'lar** bölümünde bir proje runner'ı oluşturun. Grup runner'ı da kullanabilirsiniz. Kullanmak istediğiniz tüm Tuist profil etiketlerini runner etiketi olarak ekleyin, örneğin `tuist-linux` ve `tuist-macos`, ve **Etiketsiz işleri çalıştır** seçeneğini devre dışı bırakın. GitLab'ın gösterdiği, `glrt-` ile başlayan kimlik doğrulama jetonunu saklayın. Kendi makinenize bir runner kurmanıza gerek yoktur.
2. **Tuist'te bir kez bağlanın.** **Ayarlar → Entegrasyonlar** bölümünde, GitLab CI kartındaki **Bağlan** seçeneğini belirleyin. GitLab URL'nizi ve runner kimlik doğrulama jetonunu girin. Bağlantı, farklı profiller kullanan işlere hizmet verebilir. Jetonlar şifrelenmiş olarak saklanır ve bir daha asla görüntülenmez. İsteğe bağlı olarak, birleştirme isteği boru hatlarının önbellek birimlerini kaydedebilmesi için bir API erişim jetonu ekleyin; bkz. [Birleştirme isteği boru hatları](#merge-request-pipelines).
3. **Her işte makineyi seçin.** İşin `tags` alanında tam olarak bir <.localized_link href="/guides/features/runners/profiles">Tuist profil etiketi</.localized_link> ayarlayın. Kayıtlı GitLab runner'ında da bulunması koşuluyla diğer etiketlere izin verilir:

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

4. **İtme yapın ve izleyin.** Tuist bir dakika içinde yoklamaya başlar. İşler, GitLab işine, günlüklere ve makine metriklerine geri bağlantıyla birlikte **Runner'lar** altında görünür. GitLab, iş çalışırken günlükleri alır; Tuist ise iş bittiğinde maskelenmiş günlüğü alır.

Tuist, her atamadan `CI_JOB_TAGS` değerini okur ve profili bağlı Tuist hesabı içinde çözümler. Makineyi `CI_RUNNER_TAGS` üzerinden çıkarmaz veya varsayılan bir profil kullanmaz. Eksik, bilinmeyen veya birden fazla Tuist profil etiketi, atanmış işi GitLab günlüğünde bir açıklama ile başarısız kılar. Boru hattı değişkenlerinizde `CI_JOB_TAGS` değerini geçersiz kılmayın.

## Çalıştırma ortamı {#execution-environment}

İşler, izole bir makine içinde GitLab'ın **kabuk yürütücüsünü** kullanır. Kod çekme, CI değişkenleri, `before_script`, `script`, `after_script`, yapıtlar ve iptal işlemleri GitLab Runner tarafından yönetilir. Boru hattının `image:` ve `services:` ayarları bu kabuk ortamını yapılandırmaz; <.localized_link href="/guides/features/runners/profiles">runner imajı</.localized_link> üzerinde kurulu araçları kullanın veya bunları betiğinizde kurun.

Yeniden kullanılabilir runner kimlik doğrulama jetonu Tuist sunucusunda kalır. Makineler yalnızca atanmış işleri için kimlik bilgilerini alır. Önbellek imzalama yetkileri şu anda GitLab işleri için verilmiyor. Özel Linux önbellek birimleri, GitLab’ın API’si aracılığıyla iş kimliğini doğrular ve kaydetme izni verir; üzerine yazılabilen CI değişkenleri güven oluşturmaz.

GitLab, Tuist bir işi edindiği anda onu çalışıyor olarak işaretler ve zaman aşımını başlatır. Tuist'in zaten edindiği işler hesabınızın eşzamanlılık sınırını tüketirken, sonraki işler GitLab'da beklemeye devam eder. Edinilen bir iş, en fazla 12 saat olmak üzere iş zaman aşımına kadar bir makine için bekler. Bu süreye kadar hiçbir makine mevcut olmazsa, Tuist atamayı `runner_system_failure` ile başarısız kılar ve yukarıdaki yeniden deneme politikası GitLab'ın bunu yeniden denemesine olanak tanır. Aynı politika kayıp bir runner makinesini de kapsar.

## Jetonları döndürme ve bağlantıyı kesme {#rotating-tokens-and-disconnecting}

Bağlantının jetonlarını güncelleyin ve bunları döndürmek için **Değişiklikleri kaydet** seçeneğini belirleyin. Bir jetonu boş bırakmak mevcut kimlik bilgisini korur.

**Bağlantıyı kes** edinmeyi durdurur ve bekleyen atamaları başarısız kılar. Çalışan işler kendi kimlik bilgileriyle devam eder. GitLab'a ulaşılamazsa, Tuist bekleyen atamaların iptalini yeniden denerken devre dışı bırakılmış bağlantıyı saklar. Bu atamalar sonuçlandığında bağlantı kaldırılır.

## Önbellek birimleri {#cache-volumes}

Xcode, modül ve Gradle önbelleklerini ve diğer dizinleri işler arasında <.localized_link href="/guides/features/runners/cache-volumes">önbellek birimleri</.localized_link> ile koruyun. Bunları kod çekmeden sonra ve kullanan komutlardan önce ekleyin.

### Birleştirme isteği boru hatları {#merge-request-pipelines}

Projenin itme, zamanlama ve web boru hatları değişikliklerini önbellek birimlerine kaydeder. Birleştirme isteği boru hatları önbelleği kullanır ve değişikliklerini yalnızca bağlantıda bir API erişim jetonu olduğunda kaydeder:

1. GitLab'da, **Raporcu** rolüne ve `read_api` kapsamına sahip bir proje veya grup erişim jetonu oluşturun. Bir grup jetonu, Tuist runner'larında çalışan gruptaki her projeyi kapsar.
2. **Ayarlar → Entegrasyonlar** bölümünde, GitLab CI kartındaki **API erişim jetonu** alanına yapıştırın ve **Değişiklikleri kaydet** seçeneğini belirleyin.

Tuist ardından her birleştirme isteği boru hattının birleştirme isteğini okur. Projenin kendi dalından açılan birleştirme isteklerinin boru hatları değişikliklerini birleştirme isteğinin kaynak dalı altında kaydeder, böylece runner profilinin <.localized_link href="/guides/features/runners/cache-volumes#choose-which-branches-save">dal ayarları</.localized_link> o dala uygulanır. Fork'lardan gelen birleştirme istekleri asla kaydetmez. Tuist birleştirme isteğini okuyamazsa, iş yine de çalışır ve önbelleği kullanır, ancak değişiklikleri atılır.
