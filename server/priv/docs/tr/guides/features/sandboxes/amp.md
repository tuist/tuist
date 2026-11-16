---
{
  "title": "Amp",
  "titleTemplate": ":title · Sandboxes · Özellikler · Kılavuzlar · Tuist",
  "description": "Amp çalışma alanınızın orb'larını Linux veya macOS üzerinde Tuist Sandboxes'ta çalıştırın ya da Tuist Mac eklentisiyle herhangi bir Amp iş parçacığına Xcode derlemeleri için bir Mac sağlayın."
}
---
# Amp {#amp}

> [!IMPORTANT]
> **Davet usulü**
>
> Tuist Sandbox’lar, hem Linux hem de macOS için şu anda davet usulüdür. Hesabınız için erişim istemek üzere [bize ulaşın](mailto:contact@tuist.dev) veya [topluluk Slack](https://slack.tuist.dev) kanalında bize mesaj atın.

[Amp](https://ampcode.com), her iş parçacığının araçlarını bir [orb](https://ampcode.com/docs/orbs) içinde çalıştırır; bu, iş parçacığının deposunun klonlandığı bir makinedir. Tuist, Amp çalışma alanınızın [kendi barındırdığınız orb sağlayıcısı](https://ampcode.com/docs/orbs/self-hosted) olabilir: onu seçen her iş parçacığı, Linux veya macOS üzerinde kendi Tuist <.localized_link href="/guides/features/sandboxes">sandbox</.localized_link>’ında çalışır. Kendiniz hiçbir şeyi çalıştırmaz veya barındırmazsınız.

İş parçacıklarınızı mevcut orb’larında tutmak ve yalnızca Apple platformu kodunu Mac üzerinde derlemek, test etmek ve çalıştırmak için bunun yerine [Tuist Mac eklentisini](#remote-mac) kullanın.

## Amp’i Bağla {#connect}

Hem Amp çalışma alanının hem de Tuist hesabının yöneticisi olmanız gerekir.

1. Amp’te çalışma alanınızın **Ayarlar → Orb’lar** bölümünü açın, **Orb Sağlayıcı Ekle** düğmesine tıklayın ve buna örneğin `tuist` adını verin. Üyeler sağlayıcıyı bu adla seçer. `aop_live_…` token’ını kopyalayın; Amp bunu yalnızca bir kez gösterir.
2. Amp’te sağlayıcının **Düzenle** iletişim kutusunda, sunmak istediğiniz **Orb türlerini** ekleyin ve varsayılanı seçin. Linux türleri [Amp’in kendi orb’larının](https://ampcode.com/docs/orbs/sizes-and-costs) boyutlarıyla eşleşir:

   | Tür | Platform | Boyut |
   | --- | --- | --- |
   | `linux` | Linux | 4 vCPU, 8 GiB RAM, 10 GB çalışma alanı |
   | `linux-tiny` | Linux | 1 vCPU, 2 GiB RAM, 10 GB çalışma alanı |
   | `linux-small` | Linux | 2 vCPU, 4 GiB RAM, 10 GB çalışma alanı |
   | `linux-medium` | Linux | 4 vCPU, 8 GiB RAM, 10 GB çalışma alanı (`linux` ile aynı) |
   | `linux-large` | Linux | 8 vCPU, 16 GiB RAM, 10 GB çalışma alanı |
   | `linux-xxlarge` | Linux | 16 vCPU, 32 GiB RAM, 10 GB çalışma alanı |
   | `linux-3xlarge` | Linux | 16 vCPU, 44 GiB RAM, 10 GB çalışma alanı |
   | `macos` | Xcode ile macOS | 8 vCPU, 8 GiB RAM, 10 GB çalışma alanı |

3. Tuist’te hesabınızın kontrol panelinde **Sandbox’lar** bölümünü açın, Amp kartındaki **Bağla** düğmesine tıklayın ve token’ı yapıştırın.

Tuist sağlayıcıyı hizmete sunduğunda kart **Bağlı** durumunu gösterir. Bir Tuist hesabı tek bir sağlayıcıya hizmet verir. Amp’te sağlayıcıyı kullanabilen herkes, orb’ları bağlı Tuist hesabı üzerinden çalıştırır ve ücretlendirilir. Durdurmak için karttaki **Bağlantıyı Kes** düğmesine tıklayın veya Amp’te sağlayıcıyı kapatın.

## Bir iş parçacığı başlat {#start-a-thread}

Amp'ın yeni konu oluşturma arayüzünde **Orb**'a tıklayın, **Kendi Sunucunuzda Barındırılan** altında Tuist sağlayıcısını seçin ve örneğin `linux` değerinden daha az kaynağa ihtiyaç duyan bir depo için `linux-small`, daha fazlasına ihtiyaç duyan bir depo için ise `linux-large` gibi bir tür seçin. Amp CLI üzerinden:

```bash
amp -ox "Fix the failing snapshot tests" --orb-provider tuist --orb-size macos
```

Bir iş parçacığı, ömrü boyunca orb türünü korur. Bir tür belirtilmezse sağlayıcının varsayılanı kullanılır. Her yeni iş parçacığı için aynı türü kullanmak üzere Amp’in **Ayarlar → Orb’lar** bölümündeki **Varsayılan Orb** altında sağlayıcıyı ve türünü seçin.

Amp depoyu klonlar, `.agents/setup` betiğinizi çalıştırır ve her orb için yaptığı gibi Git kimlik bilgilerini ayarlar. Her orb ayrıca hesabınızın Tuist <.localized_link href="/guides/features/cache">önbelleğini</.localized_link> okuyabilir.

## Duraklatma ve saklama {#retention}

Bir iş parçacığı boşta kaldığında Amp orb’unu duraklatır. Sonraki mesaj, dosyaları bozulmadan kalarak orb’u yeniden başlatır.

- **Linux:** Çalışan işlemler duraklamadan etkilenmez. Uzun süre duraklatılmış bir orb arşiv depolamaya taşınır ve sonraki mesajda işlemleri olmadan geri yüklenir. Linux orb’lar, Amp iş parçacığının orb’unu silene kadar dosyalarını korur.
- **macOS:** 7 gün boyunca duraklatılan veya hata durumunda olan bir orb silinir. İş parçacığının sonraki mesajı yeni bir orb başlatır ve Amp `.agents/setup` betiğini tekrar çalıştırır. Bir makinedeki ilk macOS orb’u Amp CLI’ını kurar, bu nedenle başlatılması iki dakikaya kadar sürebilir.

Amp tarafından duraklatılmadan boşta kalan bir orb, örneğin duraklatma komutu hiç gelmediyse, neredeyse hiç CPU kullanımı olmadan on dakika sonra duraklatılır.

## Herhangi bir Amp iş parçacığından Mac kullan {#remote-mac}

Tuist Mac eklentisi, Amp iş parçacığı kendi konumunda çalışmaya devam ederken (örneğin Amp’in kendi Linux orb’larından birinde) ona Xcode, iOS simülatörleri ve Homebrew içeren bir macOS sanal alanı sağlar. İşi Amp’a iletin; gerektiğinde bir Mac başlatır:

> Ayarlar ekranına karanlık mod geçişi ekleyin, uygulamayı iOS Simülatörü’nde çalıştırın ve bana bir ekran görüntüsü gösterin.

Amp kod düzenlemeyi çalıştığı yerde sürdürür. Mac üzerindeki her komuttan önce eklenti `tuist sandbox sync` çalıştırır; bu işlem Git tarafından yoksayılmayan dosyaları (işlenmiş olsun veya olmasın) kopyalar ve sonrasında yalnızca değişenleri kopyalar. Mac’in oluşturduğu derleme çıktıları ve diğer yoksayılan dosyalar orada kalır, böylece derlemeler artımlı olarak devam eder. Eklenti bu araçları ve Amp’a bunları ne zaman ve nasıl kullanacağını söyleyen bir `remote-mac` becerisini ekler:

| Araç | Ne yapar |
| --- | --- |
| `tuist_mac_start` | İş parçacığının Mac’ini oluşturur veya yeniden kullanır ve senkronize eder |
| `tuist_mac_shell` | Senkronize eder, ardından Mac üzerinde bir komut çalıştırır |
| `tuist_mac_screenshot` | Simülatörü veya ekranı iş parçacığında gösterir |
| `tuist_mac_download` | Bir dosyayı geri kopyalar, örneğin derlenmiş bir `.app` |
| `tuist_mac_stop` | İş parçacığının Mac’ini siler |

Mac’in kendi Tuist CLI’ı yoktur: ilk senkronizasyondan sonra Amp, projenin sabitlenmiş Tuist sürümünün kurulması için depo kökünde `mise install` çalıştırır ve `tuist_mac_shell` mise’nin shims’lerini `PATH` üzerine ekler. Mac üzerindeki her komut, Tuist 4.218.0 veya sonrası ile hesabınızın önbelleğine <.localized_link href="/guides/features/sandboxes#tuist-in-sandbox">ayrı ayrı oturum açar</.localized_link>; 4.215.0 ile 4.217.x arasında Amp önce `tuist auth login` çalıştırır.

Bir iş parçacığı tek bir Mac kullanır. Tuist boşta kaldığında onu duraklatır ve sonraki komutla yeniden başlatır. Amp görev tamamlandığında Mac’i siler; geride kalan bir Mac 14 gün duraklatıldıktan sonra silinir. Mac’ler diğer sanal alanlar gibi Tuist hesabınıza yansır.

### Kurulum {#remote-mac-setup}

1. **Eklentiyi yükleyin.** Tek bir dosyadır: [`tuist-mac.ts`](https://github.com/tuist/tuist/blob/main/.amp/plugins/tuist-mac.ts). Amp çalışma alanınızdaki herkesin kullanımına açmak için bir çalışma alanı yöneticisi bir iş parçacığında Amp’a şunu sorar:

   > https://raw.githubusercontent.com/tuist/tuist/main/.amp/plugins/tuist-mac.ts adresini çalışma alanı eklentilerimize ekle.

   Amp bunu çalışma alanının [eklenti deposuna](https://ampcode.com/docs/customize/global-plugins-and-skills) kaydeder ve göndermeden önce onay ister. Yalnızca kendiniz için yüklemek yerine "kişisel eklentilerim" isteyin veya yalnızca belirli bir depoda kullanmak üzere dosyayı `.amp/plugins/tuist-mac.ts` olarak kaydedin. Eklenti bir kopyadır; güncellemek için Amp’tan aynı URL’deki en son sürümle değiştirmesini isteyin.
2. **Tuist CLI’ını** Amp’ın çalıştığı yere yükleyin. Orb’larda bunu deponun [`.agents/setup`](https://ampcode.com/docs/orbs/customizing) betiğine ekleyin, örneğin `mise use -g tuist@latest` veya `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist`.
3. **CLI’ın hesabınızın sanal alanlarını kullanmasına izin verin.** Orb’larda Amp çalışma alanınızı Tuist hesabınıza <.localized_link href="/guides/server/authentication#amp-orbs">Amp orb’ları</.localized_link> bölümünde açıklandığı gibi bağlayın. Orb’lar ardından sanal alanlara erişimle birlikte kendi kendilerine oturum açar. Başka yerlerde, örneğin bir Linux makinedeki Amp CLI’ında, bir hesap üyesi olarak `tuist auth login` çalıştırın veya Mac’in önbelleği kullanabilmesi için `ci` ile birlikte `account:sandboxes:write` kapsamına sahip bir <.localized_link href="/guides/server/authentication#account-tokens">hesap jetonu</.localized_link> olarak `TUIST_MAC_TOKEN` ayarlayın. Eklenti `TUIST_TOKEN` yerine CLI’a `TUIST_MAC_TOKEN` iletir; bu nedenle orb’larınızda o kapsama sahip olmayan bir `TUIST_TOKEN` zaten varsa bunu da ayarlayın.
4. Depoda `project = "<account>/<project>"` içeren bir `tuist.toml` yoksa **kullanılacak hesabı belirtin**. Linux’ta CLI hesabı `Tuist.swift` üzerinden okuyamaz. Amp projenizin ortam değişkenlerinde `TUIST_MAC_ACCOUNT` değerini hesap tanıtıcınıza ayarlayın. Bu olmadan Amp, `Tuist.swift` içindeki `fullHandle` değerini `tuist_mac_start` aracılığıyla iletir.

CLI Mac’e yalnızca `tuist.dev` üzerinden erişir; bu nedenle ağ erişimini kısıtlayan bir ortam yalnızca bu etki alanına izin vermelidir. `PATH` üzerinde olmayan bir CLI kullanmak için `TUIST_MAC_CLI` değerini yoluna ayarlayın.

Claude Code veya Cursor gibi Amp eklentilerini desteklemeyen ajanlar, <.localized_link href="/guides/features/sandboxes#coding-agents">Kodlama ajanından Mac üzerinde derleme</.localized_link> bölümünde açıklandığı gibi Tuist MCP sunucusu ve CLI aracılığıyla aynı işlemi gerçekleştirebilir.

### Amp’ın macOS Uyduları yerine Tuist Mac’lerini kullan {#remote-mac-satellites}

Amp ayrıca bekleyen listeye katılan çalışma alanları için beta aşamasında olan kendi bulut Mac’lerine, [macOS Uyduları](https://ampcode.com/docs/orbs/mac)na sahiptir. Bir iş parçacığı her ikisini de başlatabildiğinde Amp’ın yerleşik talimatları macOS işlerini uydularına yönlendirir, bu nedenle eklentiyi nadiren seçer. İş parçacıklarının Tuist Mac’lerini kullanmasını sağlamak için şunlardan birini yapın:

- **macOS Uydularını kendiniz için kapatın.** Her üye Amp’ın [Ayarlar → Deneysel Özellikler](https://ampcode.com/settings/experimental-features) bölümündeki **Mac Uyduları** altında bunları kapatır.
- **Bunları çalışma alanı için kapatın.** Çalışma alanınızın orb’ları [Tuist üzerinde çalıştığında](#connect), bir çalışma alanı yöneticisi Amp’ın çalışma alanı ayarlarında **Orb’lar** altında **Orb’ların Çalıştığı Yer** seçeneğini **Yalnızca Kendi Sunucunuzda Barındırılan** olarak ayarlayabilir. Ajanlar daha sonra Amp tarafından barındırılan uyduları başlatamaz, ancak üyeler de Amp’ın yerleşik orb’larını kullanamaz; bu nedenle bunu yalnızca tüm iş parçacıklarınız kendi orb sağlayıcılarınızda çalışıyorsa yapın.
- **Tuist Mac’lerini isteyin.** İsteme metnine veya Amp’ın çalışma alanı ayarlarındaki çalışma alanı ajan rehberine "macOS işleri için macOS Uyduları yerine `tuist_mac_*` araçlarını kullan." ifadesini ekleyin, böylece her iş parçacığı buna uyar.
