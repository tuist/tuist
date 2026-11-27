---
{
  "title": "GitLab CI",
  "titleTemplate": ":title · CI sağlayıcıları · Çalıştırıcılar · Özellikler · Kılavuzlar · Tuist",
  "description": "Boru hattı etiketleri aracılığıyla makine seçimiyle GitLab CI işlerini Tuist Çalıştırıcılarında çalıştırın."
}
---
# GitLab CI {#gitlab-ci}

Pipeline'larınız GitLab'da kalır. Tuist, her iş için izole bir Linux veya macOS makinesi sağlar ve günlüklerini ile sonucunu GitLab'a ve Tuist kontrol paneline bildirir. GitLab 19.3 veya daha yeni bir sürüm gereklidir. GitLab.com ve genel HTTPS üzerinden erişilebilen kendi kendine barındırılan örnekler desteklenir.

1. **GitLab runner oluşturun.** Projenizin **Ayarlar → CI/CD → Runner'lar** bölümünde bir proje runner'ı oluşturun. Grup runner'ı da kullanabilirsiniz. Kullanmak istediğiniz tüm Tuist profil etiketlerini runner etiketi olarak ekleyin, örneğin `tuist-linux` ve `tuist-macos`, ve **Etiketsiz işleri çalıştır** seçeneğini devre dışı bırakın. GitLab'in gösterdiği, `glrt-` ile başlayan kimlik doğrulama token'ını saklayın. Kendi makinenize bir runner kurmanıza gerek yoktur.
2. **Tuist'te bir kez bağlanın.** **Ayarlar → Entegrasyonlar** bölümünde, GitLab CI kartındaki **Bağlan** seçeneğini belirleyin. GitLab URL'nizi ve runner kimlik doğrulama token'ınızı girin. Bağlantı, farklı profiller kullanan işlere hizmet verebilir. Token'lar şifrelenmiş olarak saklanır ve bir daha asla görüntülenmez. İsteğe bağlı olarak, birleştirme isteği pipeline'larının önbellek birimlerini kaydedebilmesi için bir API erişim token'ı ekleyin; bkz. [Birleştirme isteği pipeline'ları](#merge-request-pipelines).
3. **Her işte makineyi seçin.** İşin `tags` alanına tam olarak bir <.localized_link href="/guides/features/runners/profiles">Tuist profil etiketi</.localized_link> ayarlayın. Kayıtlı GitLab runner'ında da bulunmaları koşuluyla diğer etiketlere izin verilir:

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

4. **İtme ve izleme.** Tuist bir dakika içinde yoklamaya başlar. İşler, GitLab işine, günlüklere ve makine metriklerine geri bağlantıyla birlikte **Runner'lar** altında görünür. GitLab, iş çalışırken günlükleri alır; Tuist ise iş bittiğinde maskelenmiş günlüğü alır.

Tuist, her atamadan `CI_JOB_TAGS` değerini okur ve profili bağlı Tuist hesabı içinde çözümler. Makineyi `CI_RUNNER_TAGS` üzerinden çıkarmaz veya varsayılan bir profil kullanmaz. Eksik, bilinmeyen veya birden fazla Tuist profil etiketi, atanmış işi GitLab günlüğündeki bir açıklama ile başarısız kılar. Pipeline değişkenlerinizde `CI_JOB_TAGS` değerini geçersiz kılmayın.

## Çalıştırma ortamı {#execution-environment}

İşler, izole bir makine içinde GitLab'in **kabuk yürütücüsünü** kullanır. Checkout, CI değişkenleri, `before_script`, `script`, `after_script`, yapıtlar ve iptal işlemleri GitLab Runner tarafından yönetilir. Pipeline'ın `image:` ve `services:` ayarları bu kabuk ortamını yapılandırmaz; <.localized_link href="/guides/features/runners/profiles">runner imajında</.localized_link> yüklü araçları kullanın veya bunları betiğinizde yükleyin.

Yeniden kullanılabilir runner kimlik doğrulama token'ı Tuist sunucusunda kalır. Makineler yalnızca atanmış oldukları iş için kimlik bilgilerini alır. Önbellek imzalama yetkileri şu anda GitLab işleri için verilmez. Özel Linux önbellek birimleri, GitLab’in API’si aracılığıyla iş kimliğini doğrular ve yazma iznini kaydeder; üzerine yazılabilen CI değişkenleri güven tesis etmez.

GitLab, Tuist bir işi aldığında onu çalışıyor olarak işaretler ve zaman aşımını başlatır. Tuist'in zaten aldığı işler hesabınızın eşzamanlılık sınırını tüketirken, sonraki işler GitLab'da beklemeye devam eder. Atanmış bir iş, en fazla 12 saat olmak üzere iş zaman aşımına kadar bir makine için bekler. Bu sürede hiçbir makine mevcut olmazsa, Tuist atamayı `runner_system_failure` ile başarısız kılar ve yukarıdaki yeniden deneme politikası GitLab'in bunu yeniden denemesine olanak tanır. Aynı politika kayıp bir runner makinesini de kapsar.

## Token'ları döndürme ve bağlantıyı kesme {#rotating-tokens-and-disconnecting}

Bağlantının token'larını güncelleyin ve bunları döndürmek için **Değişiklikleri kaydet** seçeneğini belirleyin. Bir token'ı boş bırakmak mevcut kimlik bilgisini korur.

**Bağlantıyı kes** işlemi alımı durdurur ve bekleyen atamaları başarısız kılar. Çalışan işler kendi kimlik bilgileriyle devam eder. GitLab'e ulaşılamazsa, Tuist bekleyen atamaların iptalini yeniden denerken devre dışı bırakılmış bağlantıyı saklar. Bu atamalar sonuçlandığında bağlantı kaldırılır.

## Önbellek birimleri {#cache-volumes}

Xcode, modül ve Gradle önbelleklerini ve diğer dizinleri işler arasında <.localized_link href="/guides/features/runners/cache-volumes">önbellek birimleri</.localized_link> ile koruyun. Bunları checkout sonrası ve bunları kullanan komutlardan önce ekleyin.

### Birleştirme isteği pipeline'ları {#merge-request-pipelines}

Projenin push, zamanlanmış ve web pipeline'ları değişikliklerini önbellek birimlerine kaydeder. Birleştirme isteği pipeline'ları önbelleği kullanır ve değişikliklerini yalnızca bağlantıda bir API erişim token'ı olduğunda kaydeder:

1. GitLab'da, **Raporcu** rolüne ve `read_api` kapsamına sahip bir proje veya grup erişim token'ı oluşturun. Bir grup token'ı, Tuist runner'larında çalışan gruptaki her projeyi kapsar.
2. **Ayarlar → Entegrasyonlar** bölümünde, bunu GitLab CI kartındaki **API erişim token'ı** alanına yapıştırın ve **Değişiklikleri kaydet** seçeneğini belirleyin.

Tuist ardından her birleştirme isteği pipeline'ının birleştirme isteğini okur. Projenin kendi dalından açılan birleştirme isteklerinin pipeline'ları değişikliklerini birleştirme isteğinin kaynak dalı altında kaydeder, böylece runner profilinin <.localized_link href="/guides/features/runners/cache-volumes#choose-which-branches-save">dal ayarları</.localized_link> o dala uygulanır. Fork'lardan gelen birleştirme istekleri asla kaydetmez. Tuist birleştirme isteğini okuyamazsa, iş yine de çalışır ve önbelleği kullanır, ancak değişiklikleri atılır.
