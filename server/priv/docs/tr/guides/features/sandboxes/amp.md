---
{
  "title": "Amp",
  "titleTemplate": ":title · Sanal Alanlar · Özellikler · Kılavuzlar · Tuist",
  "description": "Amp çalışma alanınızın orb'larını Linux veya macOS üzerinde Tuist Sanal Alanlarında çalıştırın veya Tuist Mac eklentisiyle herhangi bir Amp iş parçacığına Xcode derlemeleri için bir Mac sağlayın."
}
---
# Amp {#amp}

> [!IMPORTANT]
> **Davet usulü**
>
> Tuist Sandboxes, hem Linux hem de macOS için şu anda davet usulüdür. Hesabınız için erişim talep etmek üzere [bize ulaşın](mailto:contact@tuist.dev) veya [topluluk Slack](https://slack.tuist.dev) kanalında bize yazın.

[Amp](https://ampcode.com), her iş parçacığının araçlarını bir [orb](https://ampcode.com/docs/orbs) içinde çalıştırır; bu, iş parçacığının deposunun klonlandığı bir makinedir. Tuist, Amp çalışma alanınızın [kendi kendine barındırılan orb sağlayıcısı](https://ampcode.com/docs/orbs/self-hosted) olabilir: onu seçen her iş parçacığı, Linux veya macOS üzerinde kendi Tuist <.localized_link href="/guides/features/sandboxes">sandbox</.localized_link>’ında çalışır. Kendi başınıza hiçbir şey çalıştırmaz veya barındırmazsınız.

İş parçacıklarınızı mevcut orb’larında tutmak ve yalnızca Apple platformu kodunu bir Mac üzerinde derlemek, test etmek ve çalıştırmak için bunun yerine [Tuist Mac eklentisini](#remote-mac) kullanın.

## Amp’i Bağla {#connect}

Hem Amp çalışma alanının hem de Tuist hesabının yöneticisi olmanız gerekir.

1. Amp’te çalışma alanınızın **Ayarlar → Orbs** bölümünü açın, **Orb Sağlayıcı Ekle** düğmesine tıklayın ve buna örnek olarak `tuist` adını verin. Üyeler sağlayıcıyı bu ada göre seçer. `aop_live_…` jetonunu kopyalayın; Amp bunu yalnızca bir kez gösterir.
2. Amp’te sağlayıcının **Düzenle** iletişim kutusunda, sunmak istediğiniz **Orb türlerini** ekleyin ve varsayılanı seçin. Linux türleri, [Amp’in kendi orb’larının](https://ampcode.com/docs/orbs/sizes-and-costs) belleğiyle eşleşir. Her biri, GiB başına bir vCPU’nun dörtte biri kadar garantili CPU alır ve makinesinde boşta çekirdek olduğunda 16 vCPU’ya kadar burst yapar (bkz. <.localized_link href="/guides/features/sandboxes#guaranteed-cpu">Garantili CPU</.localized_link>):

   | Tür | Yapılandırma |
   | --- | --- |
   | `linux` | Linux, 8 GiB RAM, 2 garantili vCPU |
   | `linux-tiny` | Linux, 2 GiB RAM, 0,5 garantili vCPU |
   | `linux-small` | Linux, 4 GiB RAM, 1 garantili vCPU |
   | `linux-medium` | `linux` ile aynı |
   | `linux-large` | Linux, 16 GiB RAM, 4 garantili vCPU |
   | `linux-xxlarge` | Linux, 32 GiB RAM, 8 garantili vCPU |
   | `linux-3xlarge` | Linux, 44 GiB RAM, 11 garantili vCPU |
   | `macos` | Varsayılan Xcode ile macOS, 8 vCPU, 8 GiB RAM |
   | `macos-xcode-<version>` | Şu [Xcode](#xcode) ile macOS, 8 vCPU, 8 GiB RAM |

   Linux türleri 10 GB çalışma alanına, macOS türleri 30 GB çalışma alanına sahiptir.

3. Tuist’te hesabınızın panosunda **Sandboxes** öğesini açın, Amp kartındaki **Bağlan** düğmesine tıklayın ve jetonu yapıştırın.

Tuist sağlayıcıyı sunduğunda kart **Bağlı** olarak görünür. Bir Tuist hesabı tek bir sağlayıcıya hizmet verir. Amp’te sağlayıcıyı kullanabilen herkes, orb’ları bağlı Tuist hesabı üzerinden çalıştırır ve faturalandırılır. Durdurmak için karttaki **Bağlantıyı Kes** düğmesine tıklayın veya Amp’te sağlayıcıyı kapatın.

## Bir iş parçacığı başlat {#start-a-thread}

Amp’in yeni iş parçacığı oluşturucusunda **Orb**’a tıklayın, **Kendi Kendine Barındırılan** altındaki Tuist sağlayıcısını seçin ve bir tür belirleyin; örneğin, `linux-small` `linux` değerinden daha az kaynak gerektiren bir depo için, `linux-large` ise daha fazla kaynak gerektiren bir depo için uygundur. Amp CLI’dan:

```bash
amp -ox "Fix the failing snapshot tests" --orb-provider tuist --orb-size macos
```

Bir iş parçacığı, ömrü boyunca orb türünü korur. Tür belirtilmezse sağlayıcının varsayılanı atanır. Her yeni iş parçacığı için aynı türü kullanmak üzere Amp’in **Ayarlar → Orbs** bölümündeki **Varsayılan Orb** altında sağlayıcıyı ve türünü seçin.

### Bir Xcode seçin {#xcode}

`macos`, varsayılan <.localized_link href="/guides/features/sandboxes#xcode">Xcode</.localized_link> sürümünü çalıştırır. Başka bir sürüm için, noktaların tire ile değiştirildiği ada sahip bir orb türü ekleyin: `macos-xcode-26-1-1` Xcode 26.1.1’i, `macos-xcode-27-0` ise Xcode 27.0’ı çalıştırır. Depolarınızın sabitlediği her Xcode için bir tür ekleyin ve diğer türler gibi iş parçacığı başına seçin:

```bash
amp -ox "Fix the failing snapshot tests" --orb-provider tuist --orb-size macos-xcode-26-1-1
```

Tuist’in sunmadığı bir Xcode için tanımlanmış tür, yeni bir orb başlatıldığında başarısız olur. Tuist o Xcode’u sunmayı durdurduktan sonra bile, üzerinde zaten başlatılmış olan bir orb çalışmaya devam eder.

Amp depoyu klonlar, `.agents/setup` betiğinizi çalıştırır ve her orb için yaptığı gibi Git kimlik bilgilerini ayarlar. Her orb ayrıca hesabınızın Tuist <.localized_link href="/guides/features/cache">önbelleğine</.localized_link> de erişebilir.

## Duraklatma ve saklama {#retention}

Bir iş parçacığı boşta kaldığında Amp orb’unu duraklatır. Sonraki mesaj, dosyaları bozulmamış haldeyken orb’u yeniden başlatır.

- **Linux:** Çalışan süreçler duraklamadan etkilenmez. Uzun süre duraklatılmış bir orb arşiv depolamaya taşınır ve sonraki mesajda süreçleri olmadan geri yüklenir. Linux orb’ları, Amp iş parçacığının orb’unu silene kadar dosyalarını korur.
- **macOS:** Duraklatılmış veya hata durumunda 7 gün kalan bir orb silinir. İş parçacığının sonraki mesajı yeni bir orb başlatır ve Amp `.agents/setup` betiğini tekrar çalıştırır. Bir makinedeki ilk macOS orb’u Amp CLI’yı kurar, bu nedenle başlatılması iki dakikaya kadar sürebilir.

Amp tarafından duraklatılmadan boşta kalan bir orb (örneğin duraklatma komutu hiç gelmediyse), neredeyse hiç CPU kullanımı olmadan on dakika sonra duraklatılır.

## Herhangi bir Amp iş parçacığından Mac kullanın {#remote-mac}

Tuist Mac eklentisi, iş parçacığı kendi konumunda (örneğin Amp’in kendi Linux orb’larından birinde) çalışmaya devam ederken ona Xcode, iOS simülatörleri ve Homebrew içeren bir macOS sandbox sağlar. Amp’ten işi isteyin; gerektiğinde bir Mac başlatır:

> Ayarlar ekranına koyu mod anahtarı ekleyin, uygulamayı iOS Simülatöründe çalıştırın ve bana bir ekran görüntüsü gösterin.

Amp kod düzenlemeyi çalıştığı yerde sürdürür. Mac üzerindeki her komuttan önce eklenti `tuist sandbox sync` çalıştırır; bu, Git’in yoksaymadığı dosyaları (commit edilmiş olsun veya olmasın) kopyalar ve sonrasında yalnızca değişenleri kopyalar. Mac’in oluşturduğu derleme ürünleri ve diğer yoksayılan dosyalar orada kalır, böylece derlemeler artımlı kalır. Eklenti bu araçları ve Amp’e bunları ne zaman ve nasıl kullanacağını söyleyen bir `remote-mac` becerisini ekler:

| Araç | Ne yapar |
| --- | --- |
| `tuist_mac_start` | İş parçacığının Mac’ini oluşturur veya yeniden kullanır ve senkronize eder |
| `tuist_mac_shell` | Senkronize eder, ardından Mac üzerinde bir komut çalıştırır |
| `tuist_mac_screenshot` | Simülatörü veya ekranı iş parçacığında gösterir |
| `tuist_mac_download` | Bir dosyayı geri kopyalar, örneğin derlenmiş bir `.app` |
| `tuist_mac_stop` | İş parçacığının Mac’ini siler |

Mac’in kendi Tuist CLI’si yoktur: ilk senkronizasyondan sonra Amp, projenin sabitlenmiş Tuist sürümünün yüklenmesi için depo kökünde `mise install` çalıştırır ve `tuist_mac_shell` mise shims’lerini `PATH` üzerine ekler. Mac üzerindeki her komut, Tuist 4.218.0 veya sonraki sürümlerle kendi başına <.localized_link href="/guides/features/sandboxes#tuist-in-sandbox">hesabınızın önbelleğine giriş yapar</.localized_link>; 4.215.0 ile 4.217.x arasında Amp önce `tuist auth login` çalıştırır.

Bir iş parçacığı tek bir Mac kullanır. Amp, `tuist_mac_start` aracılığıyla deponun sabitlediği <.localized_link href="/guides/features/sandboxes#xcode">Xcode</.localized_link> sürümünü (örneğin `.xcode-version` içinde) iletir veya siz bir tane isteyebilirsiniz (“Xcode 26.1.1 kullan”); belirtilmezse Mac varsayılanı çalıştırır. Mac Xcode’unu korur, bu nedenle değiştirmek onu durdurup başka birini başlatmak anlamına gelir. Tuist boşta kaldığında onu duraklatır ve sonraki komutla yeniden başlatır. Amp görev tamamlandığında onu siler; geride kalan bir Mac 14 gün duraklatıldıktan sonra silinir. Mac’ler diğer sandbox’lar gibi Tuist hesabınıza yansır.

### Kurulum {#remote-mac-setup}

1. **Eklentiyi yükleyin.** Tek bir dosyadır: [`tuist-mac.ts`](https://github.com/tuist/tuist/blob/main/.amp/plugins/tuist-mac.ts). Amp çalışma alanınızdaki herkesin kullanımına açmak için bir çalışma alanı yöneticisi bir iş parçacığında Amp’e şunu sorar:

   > Add https://raw.githubusercontent.com/tuist/tuist/main/.amp/plugins/tuist-mac.ts to our workspace plugins.

   Amp bunu çalışma alanının [eklenti deposuna](https://ampcode.com/docs/customize/global-plugins-and-skills) commit eder ve push etmeden önce onay ister. Yalnızca kendiniz için yüklemek yerine “my personal plugins” isteyin veya yalnızca orada kullanmak üzere dosyayı bir depoda `.amp/plugins/tuist-mac.ts` olarak kaydedin. Eklenti bir kopyadır; güncellemek için Amp’ten aynı URL’deki en son sürümle değiştirmesini isteyin.
2. **Tuist CLI’yı** Amp’in çalıştığı yere yükleyin. Orb’larda, deponun [`.agents/setup`](https://ampcode.com/docs/orbs/customizing) betiğine ekleyin, örneğin `mise use -g tuist@latest` veya `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist`.
3. **CLI’nın hesabınızın sandbox’larını kullanmasına izin verin.** Orb’larda, Amp çalışma alanınızı <.localized_link href="/guides/server/authentication#amp-orbs">Amp orb’ları</.localized_link> bölümünde açıklandığı gibi Tuist hesabınıza bağlayın. Orb’lar daha sonra sandbox erişimiyle kendi başlarına giriş yapar. Başka yerlerde, örneğin bir Linux makinedeki Amp CLI’sında, bir hesap üyesi olarak `tuist auth login` çalıştırın veya `TUIST_MAC_TOKEN` değerini `account:sandboxes:write` kapsamına sahip bir <.localized_link href="/guides/server/authentication#account-tokens">hesap token’ına</.localized_link>, ayrıca Mac’in önbelleği kullanabilmesi için `ci` değerine ayarlayın. Eklenti, `TUIST_TOKEN` yerine CLI’a `TUIST_MAC_TOKEN` iletir, bu nedenle orb’larınızda o kapsama sahip olmayan bir `TUIST_TOKEN` zaten varsa bunu da ayarlayın.
4. **Kullanılacak hesabı belirtin**; eğer depoda `project = "<account>/<project>"` içeren bir `tuist.toml` yoksa. Linux’ta CLI hesabı `Tuist.swift` üzerinden okuyamaz. Amp projenizin ortam değişkenlerinde `TUIST_MAC_ACCOUNT` değerini hesap tanıtıcınıza ayarlayın. Bu olmadan Amp, `Tuist.swift` içindeki `fullHandle` değerini `tuist_mac_start` adresine iletir.

CLI Mac’e yalnızca `tuist.dev` üzerinden ulaşır, bu nedenle ağ erişimini kısıtlayan bir ortamın yalnızca bu alana izin vermesi gerekir. `PATH` üzerinde olmayan bir CLI kullanmak için `TUIST_MAC_CLI` değerini yoluna ayarlayın.

Claude Code veya Cursor gibi Amp eklentilerini desteklemeyen ajanlar, <.localized_link href="/guides/features/sandboxes#coding-agents">Kodlama ajanından Mac üzerinde derleme</.localized_link> bölümünde açıklandığı gibi Tuist MCP sunucusu ve CLI aracılığıyla aynı işlemi yapabilir.

### Amp’in macOS Satellites yerine Tuist Mac’leri kullanın {#remote-mac-satellites}

Amp’in ayrıca bekleyen listeye katılan çalışma alanları için beta aşamasında olan kendi bulut Mac’leri, [macOS Satellites](https://ampcode.com/docs/orbs/mac), vardır. Bir iş parçacığı her ikisini de başlatabildiğinde, Amp’in yerleşik talimatları macOS işini uydularına yönlendirir, bu nedenle eklentiyi nadiren seçer. İş parçacıklarının Tuist Mac’leri kullanmasını sağlamak için şunlardan birini yapın:

- **macOS Satellites’i kendiniz için kapatın.** Her üye, Amp’in [Ayarlar → Deneysel Özellikler](https://ampcode.com/settings/experimental-features) bölümündeki **Mac Satellites** altında bunları kapatır.
- **Bunları çalışma alanı için kapatın.** Çalışma alanınızın orb’ları [Tuist üzerinde çalıştığında](#connect), bir çalışma alanı yöneticisi Amp’in çalışma alanı ayarlarında, **Orbs** altında **Where Orbs Run** seçeneğini **Self-Hosted Only** olarak ayarlayabilir. Ajanlar daha sonra Amp tarafından barındırılan uyduları başlatamaz, ancak üyeler de Amp’in yerleşik orb’larını kullanamaz; bu nedenle bunu yalnızca tüm iş parçacıklarınız kendi orb sağlayıcılarınızda çalışıyorsa yapın.
- **Tuist Mac’leri isteyin.** İsteme veya Amp’in çalışma alanı ayarlarında çalışma alanınızın ajan rehberine “macOS işleri için macOS Satellites yerine `tuist_mac_*` araçlarını kullan.” ifadesini ekleyin, böylece her iş parçacığı buna uyar.
