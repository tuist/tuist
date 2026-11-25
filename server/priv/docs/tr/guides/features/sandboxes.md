---
{
  "title": "Sandboxlar",
  "titleTemplate": ":title · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist Sandboxları, Amp ve Claude gibi kodlama ajanları için kalıcı Linux ve macOS sanal makineleridir. Her ajan oturumu kendi makinesine sahiptir; ajan boşta kaldığında duraklatılır ve dosyaları bozulmadan kaldığı yerden devam eder."
}
---
# Sandboxlar {#sandboxes}

> [!IMPORTANT]
> **Sadece davetle**
>
> Tuist Sandbox’ları, hem Linux hem de macOS için, kapasiteyi ölçeklendirirken şu anda yalnızca davetle erişilebilir. Hesabınız için erişim istemek üzere [bize ulaşın](mailto:contact@tuist.dev) veya [topluluk Slack](https://slack.tuist.dev) kanalında bize yazın. Fiyatlandırma, Sandbox’lar genel kullanıma sunulduğunda duyurulacaktır.

Sandbox, bir kodlama aracısının komutlarını çalıştırdığı ve dosyalarını düzenlediği sanal bir makinedir. Her aracı oturumu kendi sandbox’ını alır; bu sandbox, oturum süresince checkout’ını, derleme ürünlerini ve yüklü araçları saklar. Aracı boşta kaldığında sandbox duraklatılır; sonraki mesaj geldiğinde kaldığı yerden devam eder.

Sandbox’lar, <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> ile aynı filo üzerinde ve ekibinizin <.localized_link href="/guides/features/cache">önbelleği</.localized_link> yanında çalışır; böylece bir aracının derlemeleri, CI ve yerel makinelerinizle aynı önbelleklenmiş yapıtları kullanabilir.

Sandbox’ları şuradan kullanabilirsiniz:

- **<.localized_link href="/guides/features/sandboxes/amp">Amp</.localized_link>**: Amp çalışma alanınızın orb’larını Tuist üzerinde çalıştırın veya herhangi bir Amp ileti dizisine <.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac eklentisi</.localized_link> ile Xcode derlemeleri için bir Mac atayın.
- **<.localized_link href="/guides/features/sandboxes/claude">Claude</.localized_link>**: Claude Managed Agents oturumlarını ve Claude Code bulut oturumlarını (claude.ai, masaüstü ve mobil uygulamalar ve `claude --cloud`) Tuist üzerinde çalıştırın.
- **[Tuist CLI](#cli)**: Terminalinizden sandbox’lar oluşturun ve bunlarda komutlar çalıştırın veya kendi araçlarınızdan API aracılığıyla kullanın.

## CLI ile başlayın {#cli}

Terminalinizden `tuist sandbox` kullanarak bir sandbox oluşturun ve içinde komutlar çalıştırın.

### 1. Giriş yapın {#cli-log-in}

Hesabın herhangi bir üyesi sandbox’larını oluşturup yönetebilir:

```bash
tuist auth login
```

### 2. Bir sandbox oluşturun {#cli-create}

```bash
tuist sandbox create --platform macos
```

Linux için `--platform` seçeneğini atlayın. Belirli bir [Xcode](#xcode) sürümüne sahip bir Mac için, örneğin `--xcode 26.1.1` gibi bir sürümle birlikte `--xcode` geçirin; bu seçenek `--platform macos` anlamına gelir. Daha büyük bir [yapılandırma](#platforms) için `--vcpus` ile birlikte `--memory-gb` geçirin, bir Linux sandbox’ı için daha fazla [CPU](#guaranteed-cpu) garantilemek üzere `--guaranteed-vcpus` geçirin ve daha büyük bir disk için `--workspace-gb` geçirin. Sandbox, oluşturulduktan sonra iki saat boyunca çalışır ve her yeniden başlatmada süre yeniden başlar; 5 dakika ile bir gün arasında bir süre için `--lifetime-minutes` geçirin. Ömrü sona erdiğinde çalışan komutları iptal edilir, duraklatılır ve arşivlenir; dosyaları korunur, böylece unutulmuş bir sandbox hesabınızın kapasitesini tüketmeyi bırakır. Komut, sandbox çalışmaya başladığında geri döner ve kimliği dahil olmak üzere ayrıntılarını yazdırır. Geçerli dizindeki Tuist projesinin hesabını kullanır; başka bir hesap seçmek için `--account` geçirin.

### 3. Komutları çalıştırın {#cli-exec}

```bash
tuist sandbox exec <sandbox-id> -- xcodebuild -version
```

Komut, sandbox içinde `bash -l` ile çalışır; duraklatılmışsa önce yeniden başlatılır. `tuist` ne kadar uzun çalışırsa çalışsın çıktısını akış olarak verir ve komutun durumuyla çıkar; Ctrl-C ile sandbox içindeki işlemi iptal edebilirsiniz. Gerektiğinde `--cwd`, `--env NAME=VALUE` ve `--timeout` (en fazla altı saat) geçirin.

Komut `tuist` öğesinden bağımsız çalışır, bu nedenle bağlantı kopsa bile devam eder. Uzun bir derlemeyi zaman sınırlı bir araç çağrısına, örneğin bir aracının çağrısına sığdırmak için `--wait <seconds>` geçirin: bu süre önce dolduğunda, `tuist` komutu çalışır durumda bırakır, 75 çıkış koduyla çıkar ve çıktının kaldığı yerden devam edip komutun durumuyla çıkan `tuist sandbox exec <sandbox-id> --attach <command-id> --stdout-offset … --stderr-offset …` komutunu yazdırır.

### Yaygın görevler {#cli-tasks}

| Görev | Komut |
| --- | --- |
| Sandbox’ları listele | `tuist sandbox list` |
| Birini göster | `tuist sandbox show <id>` |
| Duraklat veya devam ettir | `tuist sandbox pause <id>`, `tuist sandbox resume <id>` |
| Süresi dolmasına rağmen çalışır durumda tut | `tuist sandbox extend <id> --lifetime-minutes 240` |
| Yerel Git çalışma ağacının dosyalarını yansıt | `tuist sandbox sync <id>` |
| Dosyaları içeri veya dışarı kopyala | `tuist sandbox cp <id>:<path> <local-path>`, `tuist sandbox cp <local-path> <id>:<path>` |
| Sil | `tuist sandbox delete <id> --yes` |
| Kullanımı gör | `tuist sandbox analytics` |

Makine tarafından okunabilir çıktı için `--json` ekleyin. Tüm seçenekler için <.localized_link href="/cli/sandbox">CLI referansına</.localized_link> bakın. Bunun yerine kodla sandbox’ları yönetmek isterseniz, aynı işlemleri `/api/accounts/{account_handle}/sandboxes` altında [Tuist API](https://tuist.dev/api/docs) aracılığıyla kullanın veya bir aracının bunları <.localized_link href="/guides/features/agentic-coding/mcp">MCP</.localized_link> üzerinden kullanmasına izin verin.

Etkileşimli olarak giriş yapamayan araçlar, örneğin bir macOS sandbox’ında derleme yapan bir aracı eklentisi, bunun yerine `account:sandboxes:write` kapsamına sahip bir <.localized_link href="/guides/server/authentication#account-tokens">hesap belirteci</.localized_link> ile kimlik doğrulaması yapabilir. Hesabın bir üyesinin yapabileceği her şeyi yapabilir: sandbox’lar oluşturabilir, içinde komutlar çalıştırabilir ve bunları duraklatabilir, devam ettirebilir, arşivleyebilir ve silebilir. Entegrasyon ayarları ve bir entegrasyona hizmet veren sandbox’larda komut çalıştırmak hesap yöneticilerine aittir.

### Sandbox içindeki Tuist {#tuist-in-sandbox}

macOS sandbox’ları Tuist CLI ile birlikte gelir. Projeniz mise aracılığıyla Tuist’i sabitliyorsa (`mise.toml` veya `.tool-versions`), `tuist` bunun yerine o sürümü çalıştırır; bir komut ilk kez ihtiyaç duyduğunda yüklenir. `tuist sandbox exec` ile başlattığınız her komutta mise’nin shims’leri (`$HOME/.local/share/mise/shims`) `PATH` yolunun başında ve imajdaki Tuist en sonda yer alır; böylece `tuist` ve diğer mise araçlarınız komutlarınızda ve Xcode derleme aşamalarında, örneğin bir şemanın post-actions’larında çalışır. Her Mac ayrıca kodlama ajanları için `/opt/tuist/agent-guide.md` konumunda bir rehber taşır; bu rehber imajından oluşturulur: üzerindeki Xcode ve simülatörler, deposunun konumu ve hazır bir anlık görüntünün neleri içerdiği. Mac üzerinde çalışan Claude Code, Codex ve Amp bunu talimat dosyalarından bulur.

`tuist sandbox exec` ile başlattığınız her komut ayrıca bir Tuist runner’ın aldığı olanaklara da sahiptir; böylece sandbox’taki derlemeler, kimlik bilgilerini geçmenize gerek kalmadan hesabınızın <.localized_link href="/guides/features/cache">önbelleğini</.localized_link> kullanır:

- `TUIST_URL` ve sandbox barındırıcısının erişebildiği durumlarda, örneğin macOS’ta, aynı raftaki önbelleğin `TUIST_CACHE_ENDPOINT` değeri.
- `TUIST_OIDC_TOKEN`, o komut için kısa ömürlü bir kimlik belirtecidir. Tuist CLI 4.218.0 ve sonrası bununla otomatik olarak giriş yapar; 4.215.0 ile 4.217.x sürümlerinde önce aynı komut içinde `tuist auth login` çalıştırın.

Belirteç her komut için basılır ve yalnızca o komut çalışırken bir Tuist belirtecine dönüştürülebilir; bu nedenle bir sandbox asla uzun ömürlü bir kimlik bilgisini tutmaz. Asla, komutu başlatan kişinin veya belirtecin önbellekle yapabileceklerinden fazlasını vermez: yalnızca önbellek belirteçleriyle yazma izni olan bir hesabın üyeleri okuma erişimi alır ve sandbox’ın önbelleği kullanabilmesi için bir hesap belirtecinin `account:sandboxes:write` yanına `ci` gibi önbellek kapsamları gerekir. `--env` ile geçtiğiniz değişkenler önceliklidir.

## Kodlama aracısından Mac üzerinde derleme {#coding-agents}

Linux üzerinde çalışan bir kodlama aracısı, örneğin bir bulut aracı oturumu, dosyaları çalıştığı yerde düzenlemeye devam ederken Apple platformu kodunu bir macOS sandbox’ında derleyebilir, test edebilir ve çalıştırabilir. Amp’te <.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac eklentisini</.localized_link> yükleyin. Claude Code veya Cursor gibi diğer ajanlar için:

1. Aracıyı Tuist <.localized_link href="/guides/features/agentic-coding/mcp">MCP sunucusuna</.localized_link> bağlayın. Sunucunun `create_sandbox` aracı, aracıya Mac’i nasıl yöneteceğini söyler.
2. Aracının çalıştığı yere Tuist CLI’yi yükleyin; örneğin ortamın kurulum betiğinde: `mise use -g tuist@latest` veya `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist` (ARM’de `tuist-linux-aarch64`).
3. CLI’yi kimlik doğrulayın. MCP sunucusundaki oturum açma işlemi buraya taşınmaz, bu nedenle ya bir hesap üyesi olarak `tuist auth login` çalıştırın ya da `TUIST_TOKEN` değerini `account:sandboxes:write` kapsamına sahip bir <.localized_link href="/guides/server/authentication#account-tokens">hesap belirteci</.localized_link> olarak ayarlayın.
4. Ortam ağ erişimini kısıtlıyorsa, `tuist.dev` adresine izin verin. CLI dosyaları Mac’e bunun üzerinden yükler, başka bir alan adına gerek yoktur.
5. İsteğe bağlı olarak, aracının her seferinde sormadan Mac’leri oluşturup silmesine olanak tanıyın. Aracılar, bir Mac hesabınızın limitlerine sayıldığı için `create_sandbox` çağrısından önce ve geri alınamadığı için `delete_sandbox` öncesinde onay ister. Claude Code’da, MCP sunucusunu kaydettiğiniz adı kullanarak (`tuist` burada) ikisine de `.claude/settings.json` içinde izin verin:

   ```json
   {
     "permissions": {
       "allow": ["mcp__tuist__create_sandbox", "mcp__tuist__delete_sandbox"]
     }
   }
   ```

Kurulumu aracının yapması için şu istemi verin:

```text
Set up this environment so you can build and test this project on a Tuist macOS sandbox.

Read https://tuist.dev/en/docs/guides/features/sandboxes#coding-agents and follow its "Build on a Mac from a coding agent" section. It's the current Tuist guide for this, so prefer it over anything you remember about Tuist.

You're done when you have created a Mac with create_sandbox, synced this repository to it with tuist sandbox sync, run the project's build there with tuist sandbox exec, and deleted the Mac.

Ask me before anything that needs my login or approval, such as tuist auth login. If a step fails or is blocked, stop and tell me which step you reached and the exact error, without secrets.
```

Aracı, görev başına bir Mac oluşturur ve projenin sabitlediği [Xcode](#xcode) sürümünü kullanır: `create_sandbox`, seçebileceği Xcode sürümlerini listeler ve aracıya projenin sabitlemesini, örneğin `.xcode-version` dosyasını okumasını söyler. Her komuttan önce `tuist sandbox sync` çalıştırır. Git’in yoksaymadığı dosyaları, taahhüt edilmiş olsun veya olmasın kopyalar; sonrasında yalnızca değişenleri kopyalar. Mac zaten [Tuist](#tuist-in-sandbox) ile gelir; proje bir sürüm sabitliyorsa o sürüm kurulur, hesabınızın önbelleğine giriş yapmıştır ve aracı Mac’in kılavuzunu bir kez okur. Ardından aracı, `tuist sandbox exec` ile `xcodebuild` gibi komutları çalıştırır, ekran görüntüleri veya derlenmiş bir uygulama gibi sonuçları `tuist sandbox cp` ile geri kopyalar ve görev bittiğinde Mac’i siler. Bir Mac, son komutundan sonra 10 dakika çalışır durumda kalır, böylece sonraki komut hemen başlar; `tuist sandbox pause` onu daha erken serbest bırakır. Geride bırakılan bir Mac duraklatılır, iki saatlik ömrü dolduğunda arşivlenir ve 14 gün sonra silinir; aracı uzun bir derlemeden önce ömrü uzatır.

## Linux ve macOS {#platforms}

**Linux** sandbox’ları Ubuntu 24.04 üzerinde çalışır. Her Linux sandbox’ı 16 sanal CPU’ya sahiptir ve çalıştığı makinenin boşta kalan çekirdeklerine kadar patlama yapabilir; bu nedenle şekli belleğini belirler:

- 2 GiB RAM (`--vcpus 1 --memory-gb 2`)
- 4 GiB RAM (`--vcpus 2 --memory-gb 4`, varsayılan)
- 8 GiB RAM (`--vcpus 4 --memory-gb 8`)
- 16 GiB RAM (`--vcpus 8 --memory-gb 16`)
- 32 GiB RAM (`--vcpus 16 --memory-gb 32`)
- 44 GiB RAM (`--vcpus 16 --memory-gb 44`)

**macOS** sandbox’ları Apple silikon üzerinde Xcode ile çalışır:

- 8 vCPU, 8 GiB RAM (varsayılan)
- 8 vCPU, 16 GiB RAM
- 8 vCPU, 24 GiB RAM

### Garantili CPU {#guaranteed-cpu}

Bir Linux sandbox’ı, belleğinin her GiB’si başına bir sanal CPU’nun dörtte biri kadar garantili CPU alır; örneğin 8 GiB için 2 vCPU ve makinesinde boşta olan çekirdekler kadar, en fazla 16 vCPU’ya kadar ek kaynak kullanır. Bu durum, çoğunlukla bekleyen ve ardından patlamalar halinde derleme yapan bir aracı için uygundur. Yoğun bir makinede bile derleme daha kararlı CPU gerektirdiğinde, sandbox oluşturulurken 1, 2, 4 veya 8 vCPU garanti edin; sandbox, bu değer ile bellek garantisi arasındaki daha büyük olanı alır:

| Nerede | Nasıl |
| --- | --- |
| CLI | `tuist sandbox create --guaranteed-vcpus 4` |
| API ve MCP `create_sandbox` | `"guaranteed_vcpus": 4` |

- **Garanti bir tabandır, üst sınır değildir.** 4 garantili vCPU’ya sahip bir sandbox, çekirdekler boşta olduğunda hâlâ 16’ya kadar patlama yapar. Rekabet altında her sandbox, garantisine orantılı olarak CPU alır.
- **Minimum olarak faturalandırılır.** Çalışan bir sandbox, kullandığı CPU için faturalandırılır ancak garantisinin altındaki kullanım için asla daha az faturalandırılmaz.
- **Bir sandbox garantisini ömrü boyunca korur.** Değiştirmek için yeni bir sandbox oluşturun.
- **macOS sandbox’ları her zaman tüm şekillerine sahiptir**, bu nedenle garanti almazlar.

### Bir Xcode seçin {#xcode}

Her macOS sandbox’ı tek bir Xcode çalıştırır; bunu oluştururken seçersiniz. O Xcode için <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> profiliyle aynı imajı önyükler, böylece bir aracı CI’nızla aynı araç zinciri ve simülatörlerle derleme yapar. tuist.dev üzerinde macOS sandbox’ları şu anda şunları sunar:

- `26.6` (varsayılan)
- `26.1.1`
- `27.0`
- `27.1`
- `27.2`

Runner profillerinde olduğu gibi tam sürümü kullanarak `xcode_version` ile (CLI’da `--xcode`) birini seçin:

| Nerede | Nasıl |
| --- | --- |
| CLI | `tuist sandbox create --xcode 26.1.1` |
| API ve MCP `create_sandbox` | `"xcode_version": "26.1.1"` |
| Amp için Tuist Mac eklentisi | `xcode` ile `tuist_mac_start` |
| Amp orb’ları | Orb türü `macos-xcode-26-1-1` (bkz. <.localized_link href="/guides/features/sandboxes/amp#xcode">Amp</.localized_link>) |
| Claude Code ve Claude Yönetilen Aracılar | Ortamda `xcode_version` veya Yönetilen Aracı oturumu başına (bkz. <.localized_link href="/guides/features/sandboxes/claude#xcode">Claude</.localized_link>) |

- **Sürüm belirtilmezse**, Mac varsayılanı alır.
- **Tuist’in sunmadığı bir sürüm reddedilir** ve hata, seçebileceğiniz sürümleri listeler; böylece şu anda nelerin mevcut olduğunu bilirsiniz.
- **Tuist, deponuzun `.xcode-version` dosyasını okumaz.** Sürümü siz veya Mac’i talep eden aracı seçer. MCP aracı ve Tuist Mac eklentisi, aracılara projenin sabitlediği sürümü eşleştirmelerini söyler.
- **Bir sandbox Xcode’unu ömrü boyunca korur.** Başka bir Xcode ile derleme yapmak için yeni bir sandbox oluşturun. `xcodebuild -version`, bir Mac’in hangi Xcode’u çalıştırdığını gösterir.

## Güvenlik {#security}

- Her sandbox kendi sanal makinesidir. Sandbox’lar birbirleriyle veya CI işleriyle dosya sistemi, bellek veya işlem paylaşmaz.
- Sandbox’lar bir hesaba aittir ve hesabın herhangi bir üyesi bunları kullanabilir ve yönetebilir. Bir entegrasyona hizmet eden sandbox’lar (örneğin bir Amp orb’u veya bir Claude Code oturumu) o oturumun işini ve kimlik bilgilerini barındırır: üyeler bunları görebilir, duraklatabilir, devam ettirebilir, arşivleyebilir ve silebilir; ancak yalnızca yöneticiler bunlarda komut çalıştırabilir veya dosya yükleyebilir. Entegrasyonları yalnızca yöneticiler bağlar. Bir entegrasyondan gelen oturumlar yalnızca entegrasyonun bağlı olduğu hesabın sandbox’larına erişebilir.
- Bir entegrasyonu bağlamak için Tuist’e verdiğiniz kimlik bilgileri (örneğin bir Amp sağlayıcı jetonu veya bir Claude ortam anahtarı) şifrelenerek saklanır ve bir daha asla gösterilmez.
- Bir sandbox internete erişebilir. Bir aracının ondan erişebileceği şeyleri, bir CI işine对待 edeceğiniz şekilde对待 edin.
