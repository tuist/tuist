---
{
  "title": "Entire",
  "titleTemplate": ":title | Git forges | Entegrasyonlar | Kılavuzlar | Tuist",
  "description": "Tuist derleme, test, paket ve önizleme içgörülerini Entire Trails üzerinde yayınlayın."
}
---
# Entire entegrasyonu {#entire}

Tuist, bağlı her deposunun açık veya taslak [Trail](https://docs.entire.com/guides/trails/overview)leri için bir özet tartışma tutar. Özet; mevcut derleme sonuçlarını, test hatalarını ve kararsız testleri, paket boyutlarını ve uygulama önizlemelerini içerir ve Tuist üzerindeki tam raporlara bağlantılar sunar.

> [!IMPORTANT]
> **Erken erişim**
>
> Entire eklentileri ortak kaydı gerektirir; Trail tartışmaları ve webhook sözleşmeleri deneyseldir. Tuist yöneticiniz entegrasyonu tüm hesaplar veya seçili hesaplar için etkinleştirebilir. Entire projenizin de kayıtlı eklentiyi yüklemesine izin verilmesi gerekir.

## Kurulum {#setup}

Yükleme akışı GitHub entegrasyonuyla aynıdır: önce hesabınız için eklentiyi yükleyin, ardından depoları Tuist projelerine bağlayın. Barındırılan Tuist'te yöneticiniz eklenti kaydını ve sunucu yapılandırmasını yönetir; yalnızca aşağıdaki adımları uygulamanız yeterlidir.

1. Hesabınızın **Ayarlar → Entegrasyonlar** bölümünü açın.
2. **Entire** altında **Entire eklentisini yükle** seçeneğini belirleyin. Tuist ile paylaşmak istediğiniz Entire projesini ve depoları seçin.

   ![Hesap entegrasyonlarından Entire eklentisini yükleyin](/images/guides/integrations/gitforge/entire/integrations.png)

3. Tuist'e dönün ve **Yeni proje bağlantısı ekle** seçeneğini belirleyin. **Bağlanacak depoyu seçin** alanında Tuist projenizi ve Entire deponuzu seçin, ardından **Bağlantı Oluştur** düğmesine tıklayın. Yalnızca bir Tuist projesi mevcutsa otomatik olarak seçilir.

   ![Bir Tuist projesini bir Entire deposuna bağlayın](/images/guides/integrations/gitforge/entire/add-project-connection.png)

4. Mevcut kimlik doğrulamalı Tuist komutlarınızı kullanarak içgörülerinizi CI'dan yüklemeye devam edin. Tuist bu verileri her Trail'in geçerli commit SHA'siyle eşleştirir; Entire'a özel CLI bayraklarına gerek yoktur.

Bir Tuist projesi GitHub bağlantısını korurken özetleri Entire'a da yayınlayabilir. Bu durum GitHub yansımaları için kullanışlıdır. Trail özetleri Tuist'in CI yürütücüsünü gerektirmez ve mevcut CI sağlayıcınızı değiştirmez.

İçgörüler geldikçe Tuist aynı tartışmayı günceller. Bir Trail'i açmak veya yeniden açmak, baş commit'i için daha önce yüklenmiş içgörülerin de alınmasını sağlar. Kapatılmış ve birleştirilmiş Trail'ler güncellenmez. Eski commit'lerden gelen sonuçlar asla geçerli baş için sonuç olarak sunulmaz. Geçerli commit için içgörü yoksa Tuist mevcut özeti değiştirmeden bırakır; her sonuç kendi commit hash'ini içerir.

Proje bağlantısını kaldırmak için **Yönet** menüsünü açın ve GitHub'daki gibi **Bağlantıyı kaldır** seçeneğini belirleyin. Bu işlem gelecekteki güncellemeleri durdurur ve Tuist'in yerel tartışma işaretçilerini siler. Zaten yayınlanmış yorumlar Entire üzerinde kalır. Yeniden bağlanıldığında, özet hâlâ erişilebilirse mevcut özet geri yüklenir. Eklentinin depo erişimini değiştirmek veya kaldırmak için Entire'daki projenin **Eklentiler** ayarlarını kullanın.

## Sunucu yapılandırması {#server-configuration}

Bu bölüm Tuist sunucusu operatörleri içindir. Eklentiyi Entire ile [eklenti kayıt kılavuzu](https://docs.entire.com/guides/api/plugins/register)nu kullanarak kaydedin. `contents:read` ve `discussions:write` izinlerini isteyin. Okuma izni Trail etkinlikleri ve tartışma keşfi için gereklidir; depo yazma erişimi gerekli değildir.

Aşağıdaki sunucu ortam değişkenlerini yapılandırın:

| Değişken | Amaç |
| --- | --- |
| `TUIST_ENTIRE_PLUGIN_SLUG` | Entire tarafından onaylanan slug |
| `TUIST_ENTIRE_PLUGIN_PRIVATE_KEY` | PEM formatında Ed25519 özel anahtarı; gizli anahtar deposunuz üzerinden sağlanır |
| `TUIST_ENTIRE_PLUGIN_KEY_ID` | JWKS tabanlı anahtar kaydı kullanılıyorsa Anahtar Kimliği; aksi durumda isteğe bağlı |
| `TUIST_ENTIRE_CORE_URL` | Kurulum istekleri için kullanılan Entire Core; varsayılan değer `https://eu.auth.entire.io` |
| `TUIST_ENTIRE_DELIVERY_JWKS_URL` | Kayıt sırasında Entire tarafından sağlanan webhook imzalama anahtarı URL'si |

Yönetilen Helm dağıtımları için özel PEM'i ortamın 1Password kasasında `ENTIRE_PLUGIN/private_key` olarak saklayın, ardından `server.config.entirePluginKey.enabled` seçeneğini `server.config.managedSecrets` ile birlikte etkinleştirin. External Secrets, çok satırlı PEM'i kesmeden mevcut sunucu-yapılandırma Secret'ı aracılığıyla `TUIST_ENTIRE_PLUGIN_PRIVATE_KEY` değerini sağlar. Öğe ve alan adları `server.config.entirePluginKey.item` ve `.field` üzerinden yapılandırılabilir. Bu eşleme varsayılan olarak kapalıdır ve slug veya webhook imzalama anahtarı URL'sini yapılandırmaz; bunları kayıt sonrası ayrı olarak sağlayın. Her ortam kendi imzalama anahtarını kullanmalıdır. Entire ile yalnızca genel PEM'i paylaşın, özel anahtarı asla paylaşmayın.

Kurulum sonrası URL olarak `https://<your-tuist-host>/integrations/entire/callback` ve webhook URL'si olarak `https://<your-tuist-host>/webhooks/entire` adreslerini kaydedin. Sunucu migrasyonlarını uyguladıktan sonra entegrasyonu tüm hesaplara sunmak için `entire_trails` özellik bayrağını küresel olarak etkinleştirin veya yalnızca seçili hesaplar için etkinleştirin. Genel yayına geçiş için Entire temsilcinizden eklentiyi sahiplenen proje dışında kuruluma izin vermesini isteyin; Tuist özellik bayrağını etkinleştirmek Entire'ın kurulum politikasını değiştirmez. Entire Trail özetleri, Tuist'in CI yürütme yapılandırmasından ve özellik bayrağından bağımsızdır.

Tuist kurulum makbuzlarını ve webhook imzalarını doğrular, kısa ömürlü ve depo kapsamlı jetonlar oluşturur ve yayınlamadan önce her deponun geçerli işleme bölgesini keşfeder. Jetonlar hiçbir zaman rapor bağlantılarına gömülmez.
