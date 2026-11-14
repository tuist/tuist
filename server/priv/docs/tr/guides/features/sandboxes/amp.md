---
{
  "title": "Amp",
  "titleTemplate": ":title · Sandboxes · Özellikler · Kılavuzlar · Tuist",
  "description": "Amp çalışma alanınızın orb'larını Linux veya macOS üzerinde çalışan Tuist Sandboxes'ta çalıştırın ya da Tuist Mac eklentisiyle herhangi bir Amp iş parçacığına Xcode derlemeleri için bir Mac sağlayın."
}
---
# Amp {#amp}

> [!IMPORTANT]
> **Davet usulü**
>
> Tuist Sandbox’ları, hem Linux hem de macOS için şu anda davet usulüdür. Hesabınız için erişim talep etmek üzere [bize ulaşın](mailto:contact@tuist.dev) veya [topluluk Slack](https://slack.tuist.dev) kanalında bize yazın.

[Amp](https://ampcode.com), her iş parçacığının araçlarını bir [orb](https://ampcode.com/docs/orbs) içinde çalıştırır; bu, iş parçacığının deposunun çekildiği bir makinedir. Tuist, Amp çalışma alanınızın [kendi kendine barındırılan orb sağlayıcısı](https://ampcode.com/docs/orbs/self-hosted) olabilir: onu seçen her iş parçacığı, Linux veya macOS üzerinde kendi Tuist <.localized_link href="/guides/features/sandboxes">sandbox</.localized_link>’ında çalışır. Kendiniz hiçbir şeyi çalıştırmaz veya barındırmazsınız.

İş parçacıklarınızı mevcut orb’larında tutmak ve yalnızca Apple platformu kodunu bir Mac’te derlemek, test etmek ve çalıştırmak için bunun yerine [Tuist Mac eklentisini](#remote-mac) kullanın.

## Amp’ı Bağla {#connect}

Hem Amp çalışma alanının hem de Tuist hesabının yöneticisi olmanız gerekir.

1. Amp’te çalışma alanınızın **Ayarlar → Orb’lar** bölümünü açın, **Orb Sağlayıcı Ekle** düğmesine tıklayın ve buna örneğin `tuist` adını verin. Üyeler sağlayıcıyı bu ada göre seçer. `aop_live_…` belirtecini kopyalayın; Amp bunu yalnızca bir kez gösterir.
2. Amp’te sağlayıcının **Düzenle** iletişim kutusunda, sunmak istediğiniz **Orb türlerini** ekleyin ve varsayılanı seçin. Linux türleri, [Amp’in kendi orb’larının](https://ampcode.com/docs/orbs/sizes-and-costs) boyutlarıyla eşleşir:

   | Tür | Platform | Şekil |
   | --- | --- | --- |
   | `linux` | Linux | 4 vCPU, 8 GiB RAM, 10 GB çalışma alanı |
   | `linux-tiny` | Linux | 1 vCPU, 2 GiB RAM, 10 GB çalışma alanı |
   | `linux-small` | Linux | 2 vCPU, 4 GiB RAM, 10 GB çalışma alanı |
   | `linux-medium` | Linux | 4 vCPU, 8 GiB RAM, 10 GB çalışma alanı (`linux` ile aynı) |
   | `linux-large` | Linux | 8 vCPU, 16 GiB RAM, 10 GB çalışma alanı |
   | `linux-xxlarge` | Linux | 16 vCPU, 32 GiB RAM, 10 GB çalışma alanı |
   | `linux-3xlarge` | Linux | 16 vCPU, 44 GiB RAM, 10 GB çalışma alanı |
   | `macos` | Xcode ile macOS | 8 vCPU, 8 GiB RAM, 10 GB çalışma alanı |

3. Tuist’te hesabınızın panosunda **Sandbox’lar**’ı açın, Amp kartındaki **Bağlan** düğmesine tıklayın ve belirteci yapıştırın.

Tuist sağlayıcıya hizmet vermeye başladığında kart **Bağlı** durumunu gösterir. Bir Tuist hesabı tek bir sağlayıcıya hizmet verir. Amp’te sağlayıcıyı kullanabilen herkes, orb’ları bağlı Tuist hesabı üzerinden çalıştırır ve bu hesap faturalandırılır. Durdurmak için karttaki **Bağlantıyı Kes** düğmesine tıklayın veya Amp’te sağlayıcıyı kapatın.

## Bir iş parçacığı başlat {#start-a-thread}

Amp’in yeni iş parçacığı oluşturucusunda **Orb**’a tıklayın, **Kendi Kendine Barındırılan** altındaki Tuist sağlayıcısını seçin ve `linux-small` gibi `linux` değerinden daha az kaynak gerektiren bir depo için bir tür seçin veya daha fazla kaynak gerektirenler için `linux-large` seçin. Amp CLI’dan:

```bash
amp -ox "Fix the failing snapshot tests" --orb-provider tuist --orb-size macos
```

Bir iş parçacığı, orb türünü ömrü boyunca korur. Tür belirtilmezse sağlayıcının varsayılanı atanır. Her yeni iş parçacığı için aynı türü kullanmak üzere Amp’in **Ayarlar → Orb’lar** bölümündeki **Varsayılan Orb** altında sağlayıcıyı ve türünü seçin.

Amp depoyu klonlar, `.agents/setup` betiğinizi çalıştırır ve Git kimlik bilgilerini ayarlar; bunu her orb için yapar. Her orb ayrıca hesabınızın Tuist <.localized_link href="/guides/features/cache">önbelleğini</.localized_link> okuyabilir.

## Duraklatma ve saklama {#retention}

Bir iş parçacığı boşta kaldığında Amp orb’unu duraklatır. Sonraki mesaj, dosyaları bozulmamış haldeyken orb’u yeniden başlatır.

- **Linux:** Çalışan süreçler duraklatmadan sonra korunur. Uzun süre duraklatılmış bir orb arşiv depolamaya taşınır ve sonraki mesajda süreçleri olmadan geri yüklenir. Linux orb’ları, Amp iş parçacığının orb’unu silene kadar dosyalarını saklar.
- **macOS:** Duraklatılmış veya hata durumunda 7 gün kalan bir orb silinir. İş parçacığının sonraki mesajı yeni bir orb başlatır ve Amp `.agents/setup` betiğini yeniden çalıştırır. Bir makinedeki ilk macOS orb’u Amp CLI’ını kurar, bu nedenle başlatılması iki dakikaya kadar sürebilir.

Amp tarafından duraklatılmadan boşta kalan bir orb, örneğin duraklatma komutu hiç gelmediyse, neredeyse hiç CPU kullanımı olmadan on dakika sonra duraklatılır.

## Herhangi bir Amp iş parçacığından Mac kullan {#remote-mac}

Tuist Mac eklentisi, Amp iş parçacığına Xcode, iOS simülatörleri ve Homebrew içeren bir macOS sanal alanı sağlar; iş parçacığı çalıştığı yerde, örneğin Amp’in kendi Linux orb’larından birinde çalışmaya devam eder. Amp’ten bu işi istediğinizde, gerektiğinde bir Mac başlatır:

> Ayarlar ekranına karanlık mod geçiş anahtarı ekle, uygulamayı iOS Simülatörü’nde çalıştır ve bana bir ekran görüntüsü göster.

Amp kod düzenlemeyi çalıştığı yerde sürdürür. Mac üzerindeki her komuttan önce eklenti `tuist sandbox sync` komutunu çalıştırır; bu komut Git’in yoksaymadığı dosyaları, commit edilmiş olsun veya olmasın kopyalar ve sonrasında yalnızca değişenleri kopyalar. Mac’in oluşturduğu derleme çıktıları ve diğer yoksayılan dosyalar orada kalır, böylece derlemeler artımlı olur. Eklenti bu araçları ve Amp’e bunları ne zaman ve nasıl kullanacağını söyleyen bir `remote-mac` becerisini ekler:

| Araç | Ne yapar |
| --- | --- |
| `tuist_mac_start` | İş parçacığının Mac’ini oluşturur veya yeniden kullanır ve senkronize eder |
| `tuist_mac_shell` | Senkronize eder, ardından Mac üzerinde bir komut çalıştırır |
| `tuist_mac_screenshot` | Simülatörü veya ekranı iş parçacığında gösterir |
| `tuist_mac_download` | Bir dosyayı geri kopyalar, örneğin derlenmiş bir `.app` |
| `tuist_mac_stop` | İş parçacığının Mac’ini siler |

Bir iş parçacığı tek bir Mac kullanır. Tuist boşta kaldığında onu duraklatır ve sonraki komutla yeniden başlatır. Amp görev tamamlandığında Mac’i siler; geride kalan bir Mac 14 gün duraklatıldıktan sonra silinir. Mac’ler diğer sanal alanlar gibi Tuist hesabınıza yansır.

### Kurulum {#remote-mac-setup}

1. **Eklentiyi kurun.** Tek bir dosyadır: [`tuist-mac.ts`](https://github.com/tuist/tuist/blob/main/.amp/plugins/tuist-mac.ts). Amp çalışma alanınızdaki herkesin kullanımına açmak için çalışma alanı yöneticisi bir iş parçacığında Amp’ten şunu ister:

   > https://raw.githubusercontent.com/tuist/tuist/main/.amp/plugins/tuist-mac.ts adresini çalışma alanı eklentilerimize ekle.

   Amp bunu çalışma alanının [eklenti deposuna](https://ampcode.com/docs/customize/global-plugins-and-skills) commit eder ve göndermeden önce onay ister. Yalnızca kendiniz için kurmak üzere bunun yerine “kişisel eklentilerim” isteyin veya yalnızca orada kullanmak üzere dosyayı bir depoda `.amp/plugins/tuist-mac.ts` olarak kaydedin. Eklenti bir kopyadır; güncellemek için Amp’ten aynı URL’den en son sürümle değiştirmesini isteyin.
2. **Tuist CLI’ını** Amp’in çalıştığı yere kurun. Orb’larda, deponun [`.agents/setup`](https://ampcode.com/docs/orbs/customizing) betiğine ekleyin, örneğin `mise use -g tuist@latest` veya `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist`.
3. **CLI’ın hesabınızın sanal alanlarını kullanmasına izin verin.** Orb’larda, Amp çalışma alanınızı <.localized_link href="/guides/server/authentication#amp-orbs">Amp orb’ları</.localized_link> bölümünde açıklandığı gibi Tuist hesabınıza bağlayın. Orb’lar ardından sanal alanlara erişimle kendi kendilerine oturum açar. Başka yerlerde, örneğin bir Linux makinedeki Amp CLI’ında, bir hesap üyesi olarak `tuist auth login` komutunu çalıştırın veya `TUIST_MAC_TOKEN` değerini `account:sandboxes:write` kapsamına sahip bir <.localized_link href="/guides/server/authentication#account-tokens">hesap token’ına</.localized_link> ayarlayın. Eklenti, `TUIST_TOKEN` yerine `TUIST_MAC_TOKEN` değerini CLI’a iletir; bu nedenle orb’larınızda o kapsama sahip olmayan bir `TUIST_TOKEN` zaten varsa bunu da ayarlayın.
4. **Kullanılacak hesabı belirtin**, eğer depoda `project = "<account>/<project>"` içeren bir `tuist.toml` yoksa. Linux’ta CLI, hesabı `Tuist.swift` dosyasından okuyamaz. Amp projenizin ortam değişkenlerinde `TUIST_MAC_ACCOUNT` değerini hesap adınıza ayarlayın. Bu ayar olmadan Amp, `Tuist.swift` içindeki `fullHandle` değerini `tuist_mac_start` komutuna iletir.

CLI Mac’e yalnızca `tuist.dev` üzerinden erişir; bu nedenle ağ erişimini kısıtlayan bir ortamın yalnızca bu etki alanına izin vermesi gerekir. `PATH` yolunda olmayan bir CLI kullanmak için `TUIST_MAC_CLI` değerini onun yoluna ayarlayın.

Claude Code veya Cursor gibi Amp eklentilerini desteklemeyen ajanlar, aynı işlemi Tuist MCP sunucusu ve CLI aracılığıyla <.localized_link href="/guides/features/sandboxes#coding-agents">Kodlama ajanından Mac üzerinde derleme</.localized_link> bölümünde açıklandığı gibi yapabilir.

### Amp’in macOS Satellites yerine Tuist Mac’lerini kullan {#remote-mac-satellites}

Amp ayrıca kendi bulut Mac’lerine, [macOS Satellites](https://ampcode.com/docs/orbs/mac), sahiptir; bekleme listesine katılan çalışma alanları için beta aşamasındadır. Bir iş parçacığı her ikisini de başlatabildiğinde, Amp’in yerleşik talimatları macOS işlerini uydularına yönlendirir, bu nedenle eklentiyi nadiren seçer. İş parçacıklarının Tuist Mac’lerini kullanmasını sağlamak için şunlardan birini yapın:

- **macOS Satellites’i kendiniz için kapatın.** Her üye, Amp’in [Ayarlar → Deneysel Özellikler](https://ampcode.com/settings/experimental-features) bölümündeki **Mac Satellites** altında bunları kapatır.
- **Bunları çalışma alanı için kapatın.** Çalışma alanınızın orb’ları [Tuist üzerinde çalıştığında](#connect), bir çalışma alanı yöneticisi Amp’in çalışma alanı ayarlarında, **Orb’lar** altında **Orb’ların Çalıştığı Yer** seçeneğini **Yalnızca Kendi Kendine Barındırılan** olarak ayarlayabilir. Ajanlar ardından Amp tarafından barındırılan uyduları başlatamaz, ancak üyeler de Amp’in yerleşik orb’larını kullanamaz; bu nedenle bunu yalnızca tüm iş parçacıklarınız kendi orb sağlayıcılarınızda çalışıyorsa yapın.
- **Tuist Mac’lerini isteyin.** İsteme metnine veya Amp’in çalışma alanı ayarlarındaki çalışma alanı ajan rehberine “macOS işleri için macOS Satellites yerine `tuist_mac_*` araçlarını kullan.” ifadesini ekleyin, böylece her iş parçacığı buna uyar.
