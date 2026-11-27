## Kimlik bilgisi gerektirmeyen raporlama: Özel ağ {#network-trusted-publishing}

Kendi sunucunuzda barındırılan bir dağıtım, geliştiricilerin oturum açmadan tamamlanan raporları yayınlamasına olanak tanır. Bir operatörün örnekte `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS=true` yapılandırması yapması ve bunu <.localized_link href="/guides/server/self-host/server#network-trusted-access">kendi kendine barındırma kılavuzunda</.localized_link> açıklandığı gibi yeniden başlatması gerekir. Bu, desteklenen her proje için geçerlidir; kontrol panelinde bir ayar bulunmaz. Şema sonrası eyleminizde veya terminalinizde kullanılan ortamda kendi kendine barındırılan URL'yi ve projeyi yapılandırın. Kimlik bilgileri olmadığında CLI, örnek ilkesini otomatik olarak keşfeder:

```sh
export TUIST_URL="https://tuist.internal.example"
tuist inspect build
# To publish local test results:
tuist inspect test
```

Kimlik bilgilerinin gerçekten mevcut olmaması durumunda, etkinlik günlükleri ve XCResult paketleri yerel olarak ayrıştırılır ve yapılandırılmış raporlar olarak gönderilir. Ham arşiv, ek, kapsam/geçmiş yükleme, uzak işleyici, parça referansı veya seçici yürütme kanıtı gönderilmez. Raporlar görünür durumda kalır ancak kimliği doğrulanmış test durumu güncellemelerini yapamaz veya karantina/başarısızlık otomasyonlarını tetikleyemez. Kontrol panelleri ve diğer ayrıcalıklı komutlar hâlâ oturum açmayı gerektirir. Örnek ağa güvenilen önbellek erişimini ayrı olarak etkinleştirmedikçe veya kimlik bilgileri sağlanmadıkça önbellek entegrasyonunu devre dışı bırakın.

Mevcut kimlik bilgileri kimliği doğrulanmış olarak kalır. Geçersiz, bozuk, boş veya yenilemesi reddedilmiş kimlik bilgileri güvenli bir şekilde başarısız olur ve diskte kalır; böylece sonraki komutlar sessizce imzasız hale gelmez. Bilinçli bir kurtarma eylemi olarak tekrar oturum açın veya açıkça oturumu kapatın. Kimlik bilgisi gerektirmeyen istemcileri yükseltmeden önce her sunucu çoğaltmasını keşif yeteneğine sahip bir sürüme yükseltin ve nihai sunucu URL'sini yeniden yönlendirmeler olmadan yapılandırın. Keşif özelliği olmayan eski sunucular, devre dışı bırakılmış örnekler ve keşif hataları hâlâ kimlik doğrulama gerektirir. İstemci tarafında herhangi bir onay gerekmez. Yapılandırılmış aktör talebini atlamak için `TUIST_ACTOR_ID=""` bağımsız olarak ayarlayın; doğrulanmış kimlik bilgisi kimliği bundan etkilenmez.
