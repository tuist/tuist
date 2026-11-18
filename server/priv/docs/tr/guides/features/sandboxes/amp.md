---
{
  "title": "Amp",
  "titleTemplate": ":title · Sandboxes · Özellikler · Kılavuzlar · Tuist",
  "description": "Amp çalışma alanınızın orb'larını Linux veya macOS üzerinde Tuist Sandboxes'ta çalıştırın."
}
---
# Amp {#amp}

> [!IMPORTANT]
> **Davet usulü erişim**
>
> Tuist Sandbox’ları, hem Linux hem de macOS için şu anda davet usulü erişime açıktır. Hesabınız için erişim talep etmek üzere [iletişime geçin](mailto:contact@tuist.dev) veya [topluluk Slack](https://slack.tuist.dev) kanalında bize ulaşın.

[Amp](https://ampcode.com), her iş parçacığının araçlarını bir [orb](https://ampcode.com/docs/orbs) içinde çalıştırır; bu, iş parçacığının deposunun klonlandığı bir makinedir. Tuist, Amp çalışma alanınızın [kendi sunucunuzda barındırdığınız orb sağlayıcısı](https://ampcode.com/docs/orbs/self-hosted) olabilir: Bu sağlayıcıyı seçen her iş parçacığı, Linux veya macOS üzerinde kendi Tuist <.localized_link href="/guides/features/sandboxes">sandbox</.localized_link>’ında çalışır. Kendi başınıza herhangi bir şey çalıştırmaz veya barındırmazsınız.

## Amp’ı Bağla {#connect}

Hem Amp çalışma alanının hem de Tuist hesabının yöneticisi olmanız gerekir.

1. Amp’ta çalışma alanınızın **Ayarlar → Orbs** bölümünü açın, **Orb Sağlayıcı Ekle** düğmesine tıklayın ve buna örneğin `tuist` adını verin. Üyeler sağlayıcıyı bu ada göre seçer. `aop_live_…` token’ını kopyalayın; Amp bunu yalnızca bir kez gösterir.
2. Amp’taki sağlayıcının **Düzenle** iletişim kutusunda şu **Orb türlerini** ekleyin ve varsayılanı seçin:

   | Tür | Platform | Kaynak |
   | --- | --- | --- |
   | `linux` | Linux | 2 vCPU, 4 GiB RAM, 10 GB çalışma alanı |
   | `macos` | Xcode ile macOS | 8 vCPU, 8 GiB RAM, 10 GB çalışma alanı |

3. Tuist’te hesabınızın kontrol panelinde **Sandboxes** bölümünü açın, Amp kartındaki **Bağla** düğmesine tıklayın ve token’ı yapıştırın.

Tuist sağlayıcıya hizmet vermeye başladığında kart **Bağlı** durumunu gösterir. Bir Tuist hesabı tek bir sağlayıcıya hizmet verir. Amp’ta sağlayıcıyı kullanabilen herkes, orb’ları bağlı Tuist hesabı üzerinden çalıştırır ve ücretlendirilir. Durdurmak için karttaki **Bağlantıyı Kes** düğmesine tıklayın veya Amp’ta sağlayıcıyı kapatın.

## Bir iş parçacığı başlat {#start-a-thread}

Amp’ın yeni iş parçacığı oluşturucusunda **Orb** öğesine tıklayın, **Kendi Sunucunuzda Barındırılan** altındaki Tuist sağlayıcısını seçin ve `linux` veya `macos` seçeneklerinden birini belirleyin. Amp CLI’dan:

```bash
amp -ox "Fix the failing snapshot tests" --orb-provider tuist --orb-size macos
```

Bir iş parçacığı, orb türünü ömrü boyunca korur. Tür belirtilmezse sağlayıcının varsayılanı atanır. Her yeni iş parçacığı için tek bir platform kullanmak üzere Amp’ın **Ayarlar → Orbs** bölümündeki **Varsayılan Orb** altında sağlayıcıyı ve türünü seçin.

Amp depoyu klonlar, her orb için yaptığı gibi `.agents/setup` betiğini çalıştırır ve Git kimlik bilgilerini ayarlar. Her orb ayrıca hesabınızın Tuist <.localized_link href="/guides/features/cache">önbelleğine</.localized_link> de erişebilir.

## Duraklatma ve saklama {#retention}

Bir iş parçacığı boşta kaldığında Amp orb’unu duraklatır. Sonraki mesaj, dosyaları bozulmadan kalarak işlemi devam ettirir.

- **Linux:** Çalışan işlemler duraklatmadan sonra hayatta kalır. Uzun süre duraklatılmış bir orb arşiv depolamaya taşınır ve sonraki mesajda işlemleri olmadan geri yüklenir. Linux orb’ları, Amp iş parçacığının orb’unu silene kadar dosyalarını korur.
- **macOS:** 7 gün boyunca duraklatılan veya hata durumunda kalan bir orb silinir. İş parçacığının sonraki mesajı yeni bir orb başlatır ve Amp `.agents/setup` betiğini yeniden çalıştırır. Bir makinedeki ilk macOS orb’u Amp CLI’yı yükler, bu nedenle başlatılması iki dakikaya kadar sürebilir.

Amp tarafından duraklatılmadan boşta kalan bir orb, örneğin duraklatma komutu hiç gelmediyse, neredeyse hiç CPU kullanımı olmadan on dakika sonra duraklatılır.
