---
{
  "title": "Amp",
  "titleTemplate": ":title · Sandboxlar · Özellikler · Kılavuzlar · Tuist",
  "description": "Amp çalışma alanınızın orb'larını Linux veya macOS üzerinde Tuist Sandboxlarda çalıştırın ya da Tuist Mac eklentisiyle herhangi bir Amp iş parçacığına Xcode derlemeleri için bir Mac sağlayın."
}
---
# Amp {#amp}

> [!IMPORTANT]
> **Yalnızca davetle**
>
> Tuist Sandbox’ları, hem Linux hem de macOS için şu anda yalnızca davetle erişilebilir. Hesabınız için erişim istemek üzere [bize ulaşın](mailto:contact@tuist.dev) veya [topluluk Slack](https://slack.tuist.dev) kanalında bize mesaj atın.

[Amp](https://ampcode.com), her iş parçacığının araçlarını bir [orb](https://ampcode.com/docs/orbs) içinde çalıştırır; bu, iş parçacığının deposunun klonlandığı bir makinedir. Tuist, Amp çalışma alanınızın [kendi kendine barındırılan orb sağlayıcısı](https://ampcode.com/docs/orbs/self-hosted) olabilir: onu seçen her iş parçacığı, kendi Tuist <.localized_link href="/guides/features/sandboxes">sandbox</.localized_link>’ında, Linux veya macOS üzerinde çalışır. Kendiniz hiçbir şeyi çalıştırmaz veya barındırmazsınız.

İş parçacıklarınızı mevcut orb’larında tutmak ve yalnızca Apple platform kodunu Mac üzerinde derlemek, test etmek ve çalıştırmak için bunun yerine [Tuist Mac eklentisini](#remote-mac) kullanın.

## Amp’i Bağla {#connect}

Hem Amp çalışma alanının hem de Tuist hesabının yöneticisi olmanız gerekir.

1. Amp’te çalışma alanınızın **Ayarlar → Orbs** bölümünü açın, **Orb Sağlayıcı Ekle** düğmesine tıklayın ve örneğin `tuist` gibi bir ad verin. Üyeler sağlayıcıyı bu adla seçer. `aop_live_…` jetonunu kopyalayın; Amp bunu yalnızca bir kez gösterir.
2. Amp’te sağlayıcının **Düzenle** iletişim kutusunda, sunmak istediğiniz **Orb türlerini** ekleyin ve varsayılanı seçin. Linux türleri, [Amp’in kendi orb’larının](https://ampcode.com/docs/orbs/sizes-and-costs) boyutlarıyla eşleşir:

   | Tür | Platform | Boyut |
   | --- | --- | --- |
   | `linux` | Linux | 4 vCPU, 8 GiB RAM, 10 GB çalışma alanı |
   | `linux-tiny` | Linux | 1 vCPU, 2 GiB RAM, 10 GB çalışma alanı |
   | `linux-small` | Linux | 2 vCPU, 4 GiB RAM, 10 GB çalışma alanı |
   | `linux-medium` | Linux | 4 vCPU, 8 GiB RAM, 10 GB çalışma alanı (`linux` ile aynı) |
   | `linux-large` | Linux | 8 vCPU, 16 GiB RAM, 10 GB çalışma alanı |
   | `linux-xxlarge` | Linux | 16 vCPU, 32 GiB RAM, 10 GB çalışma alanı |
   | `linux-3xlarge` | Linux | 16 vCPU, 44 GiB RAM, 10 GB çalışma alanı |
   | `macos` | Varsayılan Xcode ile macOS | 8 vCPU, 8 GiB RAM, 30 GB çalışma alanı |
   | `macos-xcode-<version>` | Belirtilen Xcode ile macOS, örneğin Xcode 26.1.1 için `macos-xcode-26-1-1` | 8 vCPU, 8 GiB RAM, 30 GB çalışma alanı |

3. Tuist’te hesabınızın kontrol panelinde **Sandbox’lar**’ı açın, Amp kartındaki **Bağla** düğmesine tıklayın ve jetonu yapıştırın.

Tuist sağlayıcıyı sunduğunda kart **Bağlı** durumunu gösterir. Bir Tuist hesabı tek bir sağlayıcıya hizmet verir. Amp’te sağlayıcıyı kullanabilen herkes, orb’ları bağlı Tuist hesabı üzerinden çalıştırır ve ücretlendirilir. Durdurmak için karttaki **Bağlantıyı Kes** düğmesine tıklayın veya Amp’te sağlayıcıyı kapatın.

## Bir İş Parçacığı Başlat {#start-a-thread}

Amp’in yeni iş parçacığı oluşturucusunda **Orb**’a tıklayın, **Kendi Kendine Barındırılan** altında Tuist sağlayıcısını seçin ve bir tür belirleyin; örneğin, `linux-small` gereksinimi `linux`’den daha az olan bir depo için veya daha fazlasına ihtiyaç duyan bir depo için `linux-large`. Amp CLI’dan:

```bash
amp -ox "Fix the failing snapshot tests" --orb-provider tuist --orb-size macos
```

Bir iş parçacığı, orb türünü ömrü boyunca korur. Bir tür belirtilmezse, sağlayıcının varsayılanı atanır. Her yeni iş parçacığı için aynı türü kullanmak üzere, Amp’in **Ayarlar → Orbs** bölümünde **Varsayılan Orb** altında sağlayıcıyı ve türünü seçin.

### Bir Xcode Seçin {#xcode}

`macos`, varsayılan <.localized_link href="/guides/features/sandboxes#xcode">Xcode</.localized_link>’u çalıştırır. Başka birini kullanmak için, noktaların tire ile değiştirildiği adla bir orb türü ekleyin: `macos-xcode-26-1-1`, Xcode 26.1.1’i çalıştırır; `macos-xcode-27-0`, Xcode 27.0’ı çalıştırır. Depolarınızın sabitlediği her Xcode için bir tür ekleyin ve diğer türler gibi iş parçacığı başına seçin:

```bash
amp -ox "Fix the failing snapshot tests" --orb-provider tuist --orb-size macos-xcode-26-1-1
```

Tuist’in sunmadığı bir Xcode için tanımlanan bir tür, yeni bir orb başlatıldığında başarısız olur. Tuist o Xcode’u sunmayı durdurduktan sonra bile, zaten o Xcode üzerinde başlatılmış bir orb çalışmaya devam eder.

Amp, depoyu klonlar, `.agents/setup` betiğinizi çalıştırır ve Git kimlik bilgilerini ayarlar; bunu her orb için yapar. Her orb ayrıca hesabınızın Tuist <.localized_link href="/guides/features/cache">önbelleğini</.localized_link> okuyabilir.

## Duraklatma ve Saklama {#retention}

Bir iş parçacığı boşta kaldığında, Amp orb’unu duraklatır. Sonraki mesaj, dosyaları bozulmamış halde kalarak onu yeniden başlatır.

- **Linux:** Çalışan süreçler duraklamadan etkilenmez. Uzun süre duraklatılmış bir orb arşiv depolamaya taşınır ve sonraki mesajda süreçleri olmadan geri yüklenir. Linux orb’ları, Amp iş parçacığının orb’unu silene kadar dosyalarını korur.
- **macOS:** 7 gün boyunca duraklatılan veya hata durumunda olan bir orb silinir. İş parçacığının sonraki mesajı yeni bir orb başlatır ve Amp `.agents/setup` betiğini tekrar çalıştırır. Bir makinedeki ilk macOS orb’u Amp CLI’ını kurar, bu nedenle başlatılması iki dakikaya kadar sürebilir.

Amp tarafından duraklatılmadan boşta kalan bir orb, örneğin duraklatma komutu hiç ulaşmadığı için, neredeyse hiç CPU kullanımı olmadan on dakika sonra duraklatılır.

## Herhangi bir Amp iş parçacığından Mac Kullanın {#remote-mac}

Tuist Mac eklentisi, iş parçacığı kendi konumunda çalışmaya devam ederken (örneğin Amp’in kendi Linux orb’larından birinde) ona Xcode, iOS simülatörleri ve Homebrew içeren bir macOS sandbox’ı sağlar. Amp’ten işi istediğinizde, ihtiyaç duyduğunda bir Mac başlatır:

> Ayarlar ekranına karanlık mod anahtarı ekle, uygulamayı iOS Simülatöründe çalıştır ve bana bir ekran görüntüsü göster.

Amp, kod düzenlemeyi çalıştığı yerde sürdürür. Mac üzerindeki her komuttan önce eklenti `tuist sandbox sync` çalıştırır; bu işlem Git’in yoksaymadığı, commit edilmiş olsun veya olmasın tüm dosyaları kopyalar ve sonrasında yalnızca değişenleri kopyalar. Mac’in oluşturduğu derleme ürünleri ve diğer yoksayılan dosyalar orada kalır, böylece derlemeler artımlı olarak devam eder. Eklenti bu araçları ve Amp’e bunları ne zaman ve nasıl kullanacağını söyleyen bir `remote-mac` yeteneği ekler:

| Araç | Ne yapar |
| --- | --- |
| `tuist_mac_start` | İş parçacığının Mac’ini oluşturur veya yeniden kullanır ve senkronize eder |
| `tuist_mac_shell` | Senkronize eder, ardından Mac üzerinde bir komut çalıştırır |
| `tuist_mac_screenshot` | Simülatörü veya ekranı iş parçacığında gösterir |
| `tuist_mac_download` | Bir dosyayı geri kopyalar, örneğin derlenmiş bir `.app` |
| `tuist_mac_stop` | İş parçacığının Mac’ini siler |

Mac’in kendi Tuist CLI’ı yoktur: ilk senkronizasyondan sonra Amp, projenin sabitlenmiş Tuist sürümünün kurulması için depo kök dizininde `mise install` çalıştırır ve `tuist_mac_shell`, mise’nin shim’lerini `PATH` yoluna ekler. Mac üzerindeki her komut, Tuist 4.218.0 veya sonrası ile kendi hesabınızın önbelleğine <.localized_link href="/guides/features/sandboxes#tuist-in-sandbox">oturum açar</.localized_link>; 4.215.0 ile 4.217.x arasında Amp önce `tuist auth login` çalıştırır.

Bir iş parçacığı tek bir Mac kullanır. Amp, `tuist_mac_start` aracılığıyla deponun sabitlediği <.localized_link href="/guides/features/sandboxes#xcode">Xcode</.localized_link> sürümünü (örneğin `.xcode-version` içinde belirtildiği gibi) iletir veya siz bir tane isteyebilirsiniz (“Xcode 26.1.1 kullan”); belirtilmezse Mac varsayılanı çalıştırır. Mac Xcode’unu korur, bu nedenle değiştirmek onu durdurup başka birini başlatmak anlamına gelir. Tuist boşta kaldığında onu duraklatır ve sonraki komutla yeniden başlatır. Amp görev tamamlandığında onu siler; geride kalan bir Mac 14 gün duraklatıldıktan sonra silinir. Mac’ler, diğer sandbox’lar gibi Tuist hesabınıza dahil edilir.

### Kurulum {#remote-mac-setup}

1. **Eklentiyi yükleyin.** Tek bir dosyadır: [`tuist-mac.ts`](https://github.com/tuist/tuist/blob/main/.amp/plugins/tuist-mac.ts). Amp çalışma alanınızdaki herkesin kullanımına sunmak için, bir çalışma alanı yöneticisi bir iş parçacığında Amp’ten şunu ister:

   > https://raw.githubusercontent.com/tuist/tuist/main/.amp/plugins/tuist-mac.ts adresini çalışma alanı eklentilerimize ekle.

   Amp, dosyayı çalışma alanının [eklenti deposuna](https://ampcode.com/docs/customize/global-plugins-and-skills) commit eder ve push etmeden önce onay ister. Yalnızca kendiniz için yüklemek yerine “kişisel eklentilerim” isteğinde bulunabilir veya yalnızca belirli bir depoda kullanmak üzere dosyayı `.amp/plugins/tuist-mac.ts` olarak kaydedebilirsiniz. Eklenti bir kopyadır; güncellemek için Amp’ten aynı URL’den en son sürümle değiştirmesini isteyin.
2. **Tuist CLI’ını** Amp’in çalıştığı yere yükleyin. Orb’larda, deponun [`.agents/setup`](https://ampcode.com/docs/orbs/customizing) betiğine ekleyin, örneğin `mise use -g tuist@latest` veya `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist`.
3. **CLI’ın hesabınızın sandbox’larını kullanmasına izin verin.** Orb’larda, Amp çalışma alanınızı <.localized_link href="/guides/server/authentication#amp-orbs">Amp orb’ları</.localized_link> bölümünde açıklandığı gibi Tuist hesabınıza bağlayın. Orb’lar daha sonra sandbox erişimiyle kendi başlarına oturum açar. Başka yerlerde, örneğin bir Linux makinesindeki Amp CLI’ında, bir hesap üyesi olarak `tuist auth login` çalıştırın veya Mac’in önbelleği kullanabilmesi için `account:sandboxes:write` kapsamına sahip bir <.localized_link href="/guides/server/authentication#account-tokens">hesap jetonu</.localized_link> ile birlikte `ci` ekleyerek `TUIST_MAC_TOKEN` ayarlayın. Eklenti, `TUIST_TOKEN` yerine `TUIST_MAC_TOKEN` değerini CLI’a iletir; bu nedenle orb’larınızda zaten o kapsama sahip olmayan bir `TUIST_TOKEN` varsa bunu da ayarlayın.
4. **Kullanılacak hesabı belirtin**; eğer depoda `project = "<account>/<project>"` içeren bir `tuist.toml` yoksa. Linux’ta CLI, hesabı `Tuist.swift` üzerinden okuyamaz. Amp projenizin ortam değişkenlerinde `TUIST_MAC_ACCOUNT` değerini hesap adınıza ayarlayın. Aksi takdirde Amp, `Tuist.swift` içindeki `fullHandle` değerini `tuist_mac_start` aracılığıyla iletir.

CLI, Mac’e yalnızca `tuist.dev` üzerinden erişir; bu nedenle ağ erişimini kısıtlayan bir ortamın yalnızca bu alana izin vermesi gerekir. `PATH` üzerinde olmayan bir CLI kullanmak için `TUIST_MAC_CLI` değerini onun yoluna ayarlayın.

Claude Code veya Cursor gibi Amp eklentilerini desteklemeyen ajanlar, <.localized_link href="/guides/features/sandboxes#coding-agents">Kodlama ajanından Mac üzerinde derleme</.localized_link> bölümünde açıklandığı gibi Tuist MCP sunucusu ve CLI aracılığıyla aynı işlemi gerçekleştirebilir.

### Amp’in macOS Satellites yerine Tuist Mac’lerini Kullanın {#remote-mac-satellites}

Amp’in ayrıca bekleme listesine katılan çalışma alanları için beta aşamasında olan kendi bulut Mac’leri, [macOS Satellites](https://ampcode.com/docs/orbs/mac), vardır. Bir iş parçacığı her ikisini de başlatabildiğinde, Amp’in yerleşik talimatları macOS işlerini satellitelere yönlendirir, bu nedenle eklentiyi nadiren seçer. İş parçacıklarının Tuist Mac’lerini kullanmasını sağlamak için şunlardan birini yapın:

- **macOS Satellites’i kendiniz için kapatın.** Her üye, Amp’in [Ayarlar → Deneysel Özellikler](https://ampcode.com/settings/experimental-features) bölümündeki **Mac Satellites** altında bunları kapatır.
- **Bunları çalışma alanı için kapatın.** Çalışma alanınızın orb’ları [Tuist üzerinde çalıştığında](#connect), bir çalışma alanı yöneticisi Amp’in çalışma alanı ayarlarında, **Orbs** altında **Orb’ların Çalıştığı Yer** seçeneğini **Yalnızca Kendi Kendine Barındırılan** olarak ayarlayabilir. Ajanlar daha sonra Amp tarafından barındırılan satellitleri başlatamaz, ancak üyeler de Amp’in yerleşik orb’larını kullanamaz; bu nedenle bunu yalnızca tüm iş parçacıklarınız kendi orb sağlayıcılarınızda çalışıyorsa yapın.
- **Tuist Mac’lerini talep edin.** İsteme “macOS işleri için macOS Satellites yerine `tuist_mac_*` araçlarını kullan.” ifadesini ekleyin veya her iş parçacığının bunu takip etmesi için Amp’in çalışma alanı ayarlarında çalışma alanınızın ajan rehberine ekleyin.
