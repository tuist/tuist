---
{
  "title": "Amp",
  "titleTemplate": ":title · Sandboxes · Özellikler · Kılavuzlar · Tuist",
  "description": "Amp çalışma alanınızın orb'larını Tuist Sandboxes üzerinde, Linux veya macOS'ta çalıştırın ya da Tuist Mac eklentisiyle herhangi bir Amp iş parçacığına Xcode derlemeleri için bir Mac sağlayın."
}
---
# Amp {#amp}

> [!IMPORTANT]
> **Davet usulü erişim**
>
> Tuist Sandboxes, hem Linux hem de macOS için şu anda davet usulü erişime açıktır. Hesabınız için erişim talep etmek üzere [bize ulaşın](mailto:contact@tuist.dev) veya [topluluk Slack](https://slack.tuist.dev) kanalından bize yazın.

[Amp](https://ampcode.com), her iş parçacığının araçlarını bir [orb](https://ampcode.com/docs/orbs) içinde çalıştırır; bu, iş parçacığının deposunun klonlandığı bir makinedir. Tuist, Amp çalışma alanınızın [kendi kendine barındırılan orb sağlayıcısı](https://ampcode.com/docs/orbs/self-hosted) olabilir: onu seçen her iş parçacığı, Linux veya macOS üzerinde kendi Tuist <.localized_link href="/guides/features/sandboxes">sandbox</.localized_link> ortamında çalışır. Kendi başınıza hiçbir şey çalıştırmaz veya barındırmazsınız.

İş parçacıklarınızı mevcut orb'larınızda tutmak ve yalnızca Apple platformu kodunu bir Mac üzerinde derlemek, test etmek ve çalıştırmak için bunun yerine [Tuist Mac eklentisini](#remote-mac) kullanın.

## Amp'i Bağla {#connect}

Hem Amp çalışma alanının hem de Tuist hesabının yöneticisi olmanız gerekir.

1. Amp'te çalışma alanınızın **Ayarlar → Orbs** bölümünü açın, **Orb Sağlayıcı Ekle** seçeneğine tıklayın ve buna örneğin `tuist` adını verin. Üyeler sağlayıcıyı bu ada göre seçer. `aop_live_…` token'ını kopyalayın; Amp bunu yalnızca bir kez gösterir.
2. Amp'teki sağlayıcının **Düzenle** iletişim kutusunda, sunmak istediğiniz **Orb türlerini** ekleyin ve varsayılanı seçin. Linux türleri, [Amp'in kendi orb'larının](https://ampcode.com/docs/orbs/sizes-and-costs) belleğiyle eşleşir. Her biri, GiB başına çeyrek vCPU garantisi alır ve makinesinde boşta çekirdekler olduğunda 16 vCPU'ya kadar çıkar (bkz. <.localized_link href="/guides/features/sandboxes#guaranteed-cpu">Garantili CPU</.localized_link>):

   | Tür | Yapılandırma |
   | --- | --- |
   | `linux` | Linux, 8 GiB RAM, 2 garantili vCPU |
   | `linux-tiny` | Linux, 2 GiB RAM, 0.5 garantili vCPU |
   | `linux-small` | Linux, 4 GiB RAM, 1 garantili vCPU |
   | `linux-medium` | `linux` ile aynı |
   | `linux-large` | Linux, 16 GiB RAM, 4 garantili vCPU |
   | `linux-xxlarge` | Linux, 32 GiB RAM, 8 garantili vCPU |
   | `linux-3xlarge` | Linux, 44 GiB RAM, 11 garantili vCPU |
   | `macos` | macOS, varsayılan Xcode ile, 8 vCPU, 8 GiB RAM |
   | `macos-xcode-<version>` | macOS, belirtilen [Xcode](#xcode) ile, 8 vCPU, 8 GiB RAM |

   Linux türlerinde 10 GB çalışma alanı, macOS türlerinde 30 GB çalışma alanı bulunur.

3. Tuist'te hesabınızın kontrol panelinde **Sandboxes** bölümünü açın, Amp kartındaki **Bağlan** düğmesine tıklayın ve token'ı yapıştırın.

Tuist sağlayıcıyı sunduğunda kart **Bağlı** durumunu gösterir. Bir Tuist hesabı tek bir sağlayıcıya hizmet verir. Amp'te sağlayıcıyı kullanabilen herkes, orb'ları bağlı Tuist hesabı üzerinden çalıştırır ve faturalandırılır. Durdurmak için karttaki **Bağlantıyı Kes** düğmesine tıklayın veya Amp'te sağlayıcıyı kapatın.

## Bir iş parçacığı başlat {#start-a-thread}

Amp'in yeni iş parçacığı oluşturucusunda **Orb** seçeneğine tıklayın, **Kendi Kendine Barındırılan** altındaki Tuist sağlayıcısını seçin ve bir tür belirleyin; örneğin, `linux-small` türü `linux` türünden daha az kaynak gerektiren bir depo için, `linux-large` türü ise daha fazla kaynak gerektiren bir depo için uygundur. Amp CLI'dan:

```bash
amp -ox "Fix the failing snapshot tests" --orb-provider tuist --orb-size macos
```

Bir iş parçacığı, ömrü boyunca orb türünü korur. Bir tür belirtilmezse, sağlayıcının varsayılanı atanır. Her yeni iş parçacığı için aynı türü kullanmak üzere, Amp'in **Ayarlar → Orbs** bölümündeki **Varsayılan Orb** altında sağlayıcıyı ve türünü seçin.

### Bir Xcode seç {#xcode}

`macos`, varsayılan <.localized_link href="/guides/features/sandboxes#xcode">Xcode</.localized_link> sürümünü çalıştırır. Başka bir sürüm için, adına göre bir orb türü ekleyin ve noktaları tire ile değiştirin: `macos-xcode-26-1-1`, Xcode 26.1.1'i çalıştırır; `macos-xcode-27-0`, Xcode 27.0'ı çalıştırır. Depolarınızın sabitlediği her Xcode sürümü için bir tür ekleyin ve diğer türlerde olduğu gibi iş parçacığı başına seçin:

```bash
amp -ox "Fix the failing snapshot tests" --orb-provider tuist --orb-size macos-xcode-26-1-1
```

Tuist'in sunmadığı bir Xcode için tanımlanan bir tür, yeni bir orb başlatıldığında başarısız olur. Tuist'in o Xcode'u sunmayı durdurmasından sonra bile, üzerinde zaten başlatılmış olan bir orb çalışmaya devam eder.

Amp, depoyu klonlar, `.agents/setup` betiğinizi çalıştırır ve Git kimlik bilgilerini ayarlar; bunu her orb için yapar. Her orb ayrıca hesabınızın Tuist <.localized_link href="/guides/features/cache">önbelleğine</.localized_link> de erişebilir.

## Duraklatma ve saklama {#retention}

Bir iş parçacığı boşta kaldığında, Amp orb'unu duraklatır. Sonraki mesaj, dosyaları bozulmadan kalarak orb'u yeniden başlatır.

- **Linux:** Çalışan süreçler duraklatmadan etkilenmez. Uzun süre duraklatılmış bir orb, arşiv depolamaya taşınır ve sonraki mesajda süreçleri olmadan geri yüklenir. Linux orb'ları, Amp iş parçacığının orb'unu silene kadar dosyalarını korur.
- **macOS:** 7 gün boyunca duraklatılan veya hata durumunda kalan bir orb silinir. İş parçacığının sonraki mesajı yeni bir orb başlatır ve Amp `.agents/setup` betiğini tekrar çalıştırır. Bir makinedeki ilk macOS orb'u, Amp CLI'yi kurar; bu nedenle başlatılması iki dakikaya kadar sürebilir.

Amp tarafından duraklatılmadan boşta kalan bir orb, örneğin duraklatma komutu hiç gelmediyse, neredeyse hiç CPU kullanımı olmadan on dakika sonra duraklatılır.

## Herhangi bir Amp iş parçacığından Mac kullan {#remote-mac}

Tuist Mac eklentisi, bir Amp iş parçacığına Xcode, iOS simülatörleri ve Homebrew içeren bir macOS sandbox ortamı sağlar; iş parçacığı çalıştığı yerde, örneğin Amp'in kendi Linux orb'larından birinde çalışmaya devam eder. Amp'ten işi istediğinizde, ihtiyaç duyduğunda bir Mac başlatır:

> Ayarlar ekranına karanlık mod anahtarı ekle, uygulamayı iOS Simülatöründe çalıştır ve bana bir ekran görüntüsü göster.

Amp, kod düzenlemeyi çalıştığı yerde sürdürür. Mac üzerindeki her komuttan önce eklenti `tuist sandbox sync` komutunu çalıştırır; bu komut, Git'in yoksaymadığı dosyaları (commit edilmiş olsun veya olmasın) kopyalar ve sonrasında yalnızca değişenleri kopyalar. Mac'in oluşturduğu derleme ürünleri ve diğer yoksayılan dosyalar orada kalır, böylece derlemeler artımlı olarak devam eder. Eklenti bu araçları ve Amp'e bunları ne zaman ve nasıl kullanacağını söyleyen bir `remote-mac` becerisini ekler:

| Araç | Ne yapar |
| --- | --- |
| `tuist_mac_start` | İş parçacığının Mac'ini oluşturur veya yeniden kullanır ve senkronize eder |
| `tuist_mac_shell` | Senkronize eder, ardından Mac üzerinde bir komut çalıştırır |
| `tuist_mac_screenshot` | Simülatörü veya ekranı iş parçacığında gösterir |
| `tuist_mac_download` | Derlenmiş bir `.app` gibi bir dosyayı geri kopyalar |
| `tuist_mac_stop` | İş parçacığının Mac'ini siler |

Mac'te Tuist CLI bulunur ve proje mise aracılığıyla bir sürüm sabitlediğinde projenin kendi sürümünü çalıştırır; `tuist_mac_shell`, mise'nin shim'lerini `PATH` yolunun başına ekler. Mac üzerindeki her komut, Tuist 4.218.0 veya sonraki sürümlerle kendi başına <.localized_link href="/guides/features/sandboxes#tuist-in-sandbox">hesabınızın önbelleğine giriş yapar</.localized_link>; 4.215.0 ile 4.217.x arasında Amp önce `tuist auth login` komutunu çalıştırır.

Bir iş parçacığı tek bir Mac kullanır. Amp, `tuist_mac_start` komutuna depo tarafından sabitlenen <.localized_link href="/guides/features/sandboxes#xcode">Xcode</.localized_link> sürümünü (örneğin `.xcode-version` dosyasında belirtilen) iletir veya siz bir sürüm isteyebilirsiniz ("Xcode 26.1.1 kullan"); bir sürüm belirtilmezse Mac varsayılanı çalıştırır. Mac Xcode sürümünü korur, bu nedenle değiştirmek onu durdurup başka birini başlatmayı gerektirir. Tuist boşta kaldığında onu duraklatır ve sonraki komutla yeniden başlatır. Amp görev tamamlandığında onu siler; geride kalan bir Mac 14 gün duraklatıldıktan sonra silinir. Mac'ler, diğer sandbox'lar gibi Tuist hesabınıza yansır.

### Kurulum {#remote-mac-setup}

1. **Eklentiyi yükleyin.** Tek bir dosyadır: [`tuist-mac.ts`](https://github.com/tuist/tuist/blob/main/.amp/plugins/tuist-mac.ts). Amp çalışma alanınızdaki herkesin kullanımına açmak için bir çalışma alanı yöneticisi bir iş parçacığında Amp'e şunu sorar:

   > https://raw.githubusercontent.com/tuist/tuist/main/.amp/plugins/tuist-mac.ts adresini çalışma alanı eklentilerimize ekle.

   Amp, bunu çalışma alanının [eklenti deposuna](https://ampcode.com/docs/customize/global-plugins-and-skills) commit eder ve push etmeden önce onay ister. Yalnızca kendiniz yüklemek için bunun yerine "kişisel eklentilerim" isteyin veya yalnızca belirli bir depoda kullanmak üzere dosyayı `.amp/plugins/tuist-mac.ts` olarak kaydedin. Eklenti bir kopyadır; güncellemek için Amp'ten aynı URL'den en son sürümle değiştirmesini isteyin.
2. **Tuist CLI'yi** Amp'in çalıştığı yere yükleyin. Orb'larda, deponun [`.agents/setup`](https://ampcode.com/docs/orbs/customizing) betiğine ekleyin, örneğin `mise use -g tuist@latest` veya `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist`.
3. **CLI'nin hesabınızın sandbox'larını kullanmasına izin verin.** Orb'larda, Amp çalışma alanınızı <.localized_link href="/guides/server/authentication#amp-orbs">Amp orb'ları</.localized_link> bölümünde açıklandığı gibi Tuist hesabınıza bağlayın. Orb'lar daha sonra sandbox erişimiyle kendi başlarına giriş yapar. Başka yerlerde, örneğin bir Linux makinesindeki Amp CLI'sında, bir hesap üyesi olarak `tuist auth login` komutunu çalıştırın veya Mac'in önbelleği kullanabilmesi için `account:sandboxes:write` kapsamına sahip bir <.localized_link href="/guides/server/authentication#account-tokens">hesap jetonu</.localized_link> artı `ci` ile `TUIST_MAC_TOKEN` değerini ayarlayın. Eklenti, `TUIST_TOKEN` yerine CLI'ye `TUIST_MAC_TOKEN` iletir; bu nedenle orb'larınızda bu kapsama sahip olmayan bir `TUIST_TOKEN` zaten varsa bunu da ayarlayın.
4. Depoda `project = "<account>/<project>"` içeren bir `tuist.toml` yoksa **kullanılacak hesabı belirtin**. Linux'ta CLI, hesabı `Tuist.swift` dosyasından okuyamaz. Amp projenizin ortam değişkenlerinde `TUIST_MAC_ACCOUNT` değerini hesap adınıza ayarlayın. Bu yapılmazsa Amp, `Tuist.swift` içindeki `fullHandle` değerini `tuist_mac_start` komutuna iletir.

CLI, Mac'e yalnızca `tuist.dev` üzerinden erişir; bu nedenle ağ erişimini kısıtlayan bir ortamın yalnızca bu alana izin vermesi gerekir. `PATH` üzerinde olmayan bir CLI kullanmak için `TUIST_MAC_CLI` değerini onun yoluna ayarlayın.

Claude Code veya Cursor gibi Amp eklentilerini desteklemeyen ajanlar, <.localized_link href="/guides/features/sandboxes#coding-agents">Kodlama ajanından Mac'te derleme</.localized_link> bölümünde açıklandığı gibi Tuist MCP sunucusu ve CLI aracılığıyla aynı işlemi yapabilir.

### Amp'in macOS Satellites yerine Tuist Mac'leri kullan {#remote-mac-satellites}

Amp ayrıca bekleyen listeye katılan çalışma alanları için beta aşamasında olan kendi bulut Mac'lerine, [macOS Satellites](https://ampcode.com/docs/orbs/mac)'e sahiptir. Bir iş parçacığı her ikisini de başlatabildiğinde, Amp'in yerleşik talimatları macOS işlerini uydularına gönderir, bu nedenle eklenti nadiren seçilir. İş parçacıklarının Tuist Mac'leri kullanmasını sağlamak için şunlardan birini yapın:

- **macOS Satellites'i kendiniz için kapatın.** Her üye, Amp'in [Ayarlar → Deneysel Özellikler](https://ampcode.com/settings/experimental-features) bölümündeki **Mac Satellites** altında bunları kapatır.
- **Bunları çalışma alanı için kapatın.** Çalışma alanınızın orb'ları [Tuist üzerinde çalıştığında](#connect), bir çalışma alanı yöneticisi Amp'in çalışma alanı ayarlarında, **Orbs** altında **Orb'ların Çalışma Yeri** seçeneğini **Yalnızca Kendi Sunucularım** olarak ayarlayabilir. Ajanlar daha sonra Amp tarafından barındırılan uyduları başlatamaz, ancak üyeler Amp'in yerleşik orb'larını da kullanamaz; bu nedenle bunu yalnızca tüm iş parçacıklarınız kendi orb sağlayıcılarınızda çalışıyorsa yapın.
- **Tuist Mac'leri isteyin.** İsteme (prompt) metnine veya Amp'in çalışma alanı ayarlarındaki çalışma alanı ajan rehberine "macOS işleri için macOS Satellites yerine `tuist_mac_*` araçlarını kullan." ifadesini ekleyin, böylece her iş parçacığı buna uyar.
