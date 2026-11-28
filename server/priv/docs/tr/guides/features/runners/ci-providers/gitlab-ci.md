---
{
  "title": "GitLab CI",
  "titleTemplate": ":title · CI sağlayıcıları · Çalıştırıcılar · Özellikler · Kılavuzlar · Tuist",
  "description": "Pipeline etiketleri üzerinden makine seçimiyle GitLab CI işlerini Tuist Çalıştırıcılarında çalıştırın."
}
---
# GitLab CI {#gitlab-ci}

Pipeline'larınız GitLab'da kalır. Tuist, her iş için izole bir Linux veya macOS makinesi sağlar ve günlüklerini ile sonucunu GitLab'a ve Tuist kontrol paneline bildirir. GitLab 19.3 veya daha yeni bir sürüm gereklidir. GitLab.com ve herkese açık HTTPS üzerinden erişilebilen kendi kendine barındırılan örnekler desteklenir.

1. **GitLab runner oluşturun.** Projenizin **Ayarlar → CI/CD → Runner'lar** bölümünde bir proje runner'ı oluşturun. Grup runner'ı da kullanabilirsiniz. Kullanmak istediğiniz tüm Tuist profil etiketlerini runner etiketi olarak ekleyin, örneğin `tuist-linux` ve `tuist-macos`, ardından **Etiketsiz işleri çalıştır** seçeneğini devre dışı bırakın. GitLab'in gösterdiği, `glrt-` ile başlayan kimlik doğrulama jetonunu saklayın. Kendi makinenize bir runner kurmanıza gerek yoktur.
2. **Tuist'te tek seferlik bağlantı kurun.** **Ayarlar → Entegrasyonlar** bölümünde GitLab CI kartındaki **Bağlan** seçeneğini belirleyin. GitLab URL'nizi ve runner kimlik doğrulama jetonunu girin. Bağlantı, farklı profiller kullanan işlere hizmet verebilir. Jetonlar şifrelenerek saklanır ve bir daha asla görüntülenmez. İsteğe bağlı olarak, birleştirme isteği pipeline'larının önbellek birimlerini kaydedebilmesi için bir API erişim jetonu ekleyin; bkz. [Birleştirme isteği pipeline'ları](#merge-request-pipelines).
3. **Her işte makineyi seçin.** İşin `tags` alanında tam olarak bir <.localized_link href="/guides/features/runners/profiles">Tuist profil etiketi</.localized_link> ayarlayın. Kayıtlı GitLab runner'ında da aynı etiketler bulunduğu sürece başka etiketlere izin verilir:

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

4. **Push yapın ve izleyin.** Tuist bir dakika içinde yoklamaya başlar. İşler, GitLab işine, günlüklere ve makine metriklerine geri dönüş bağlantısıyla birlikte **Runner'lar** altında görünür. GitLab, iş çalışırken günlükleri alır; Tuist ise iş tamamlandığında maskelenmiş günlüğü alır.

Tuist, her atamadan `CI_JOB_TAGS` değerini okur ve profili bağlı Tuist hesabı içinde çözümler. Makineyi `CI_RUNNER_TAGS` üzerinden çıkarmaz veya varsayılan bir profil kullanmaz. Eksik, bilinmeyen veya birden fazla Tuist profil etiketi, atanmış işi GitLab günlüğünde bir açıklama ile başarısız kılar. Pipeline değişkenlerinizde `CI_JOB_TAGS` değerini geçersiz kılmayın.

## Çalıştırma ortamı {#execution-environment}

İşler, izole bir makine içinde GitLab'in **kabuk yürütücüsünü** kullanır. Kod çekme, CI değişkenleri, `before_script`, `script`, `after_script`, yapıtlar ve iptal işlemleri GitLab Runner tarafından yönetilir. Pipeline'ın `image:` ve `services:` ayarları bu kabuk ortamını yapılandırmaz; <.localized_link href="/guides/features/runners/profiles">runner imajı</.localized_link> üzerinde kurulu araçları kullanın veya bunları betiğinizde kurun.

Yeniden kullanılabilir runner kimlik doğrulama jetonu Tuist sunucusunda kalır. Makineler yalnızca atanmış iş için gereken kimlik bilgilerini alır. Önbellek imzalama yetkileri şu anda GitLab işleri için verilmez. Özel Linux önbellek birimleri, GitLab API'si aracılığıyla iş kimliğini doğrular ve kaydetme iznini sağlar; üzerine yazılabilen CI değişkenleri güven tesis etmez.

GitLab, Tuist bir işi edindiğinde onu çalışıyor olarak işaretler ve zaman aşımını başlatır. Tuist'in zaten edindiği işler hesabınızın eşzamanlılık sınırını tüketirken, sonraki işler GitLab'da beklemeye devam eder. Edinilen bir iş, en fazla 12 saat olmak üzere iş zaman aşımına kadar bir makine için bekler. Bu süre sonunda hiçbir makine mevcut olmazsa, Tuist atamayı `runner_system_failure` ile başarısız kılar ve yukarıdaki yeniden deneme politikası GitLab'in bunu yeniden denemesine olanak tanır. Aynı politika kaybolan bir runner makinesini de kapsar.

## Jetonları döndürme ve bağlantıyı kesme {#rotating-tokens-and-disconnecting}

Bağlantının jetonlarını güncelleyin ve döndürmek için **Değişiklikleri kaydet** seçeneğini belirleyin. Bir jetonu boş bırakmak mevcut kimlik bilgisini korur.

**Bağlantıyı kes** edinmeyi durdurur ve bekleyen atamaları başarısız kılar. Çalışan işler kendi kimlik bilgileriyle devam eder. GitLab'e erişilemiyorsa, Tuist bekleyen atamaların iptalini yeniden denerken devre dışı bırakılmış bağlantıyı saklar. Bu atamalar sonuçlandığında bağlantı kaldırılır.

## Önbellek birimleri {#cache-volumes}

Xcode, modül ve Gradle önbelleklerini ve diğer dizinleri işler arasında <.localized_link href="/guides/features/runners/cache-volumes">önbellek birimleri</.localized_link> ile koruyun. Bunları kod çekme işleminden sonra ve bunları kullanan komutlardan önce ekleyin.

### Birleştirme isteği pipeline'ları {#merge-request-pipelines}

Projenin push, zamanlanmış ve web pipeline'ları değişikliklerini önbellek birimlerine kaydeder. Birleştirme isteği pipeline'ları önbelleği kullanır ve değişikliklerini yalnızca bağlantıda bir API erişim jetonu olduğunda kaydeder:

1. GitLab'da **Raporcu** rolüne ve `read_api` kapsamına sahip bir proje veya grup erişim jetonu oluşturun. Bir grup jetonu, Tuist runner'larında çalışan gruptaki her projeyi kapsar.
2. **Ayarlar → Entegrasyonlar** bölümünde, GitLab CI kartındaki **API erişim jetonu** alanına jetonu yapıştırın ve **Değişiklikleri kaydet** seçeneğini belirleyin.

Tuist daha sonra her birleştirme isteği pipeline'ının birleştirme isteğini okur. Projenin kendi dalından açılan birleştirme isteklerinin pipeline'ları değişikliklerini birleştirme isteğinin kaynak dalı altında kaydeder, bu nedenle runner profilinin <.localized_link href="/guides/features/runners/cache-volumes#choose-which-branches-save">dal ayarları</.localized_link> o dala uygulanır. Fork'lardan gelen birleştirme istekleri asla kaydetmez. Tuist birleştirme isteğini okuyamazsa, iş yine de çalışır ve önbelleği kullanır, ancak değişiklikleri atılır.
