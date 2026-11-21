---
{
  "title": "Sandboxlar",
  "titleTemplate": ":title · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist Sandboxlar, Amp ve Claude gibi kodlama ajanları için kalıcı Linux ve macOS sanal makinelerdir. Her ajan oturumu kendi makinesine sahiptir; ajan boşta kaldığında duraklatılır ve dosyaları bozulmadan kaldığı yerden devam eder."
}
---
# Sandboxlar {#sandboxes}

> [!IMPORTANT]
> **Yalnızca davetiyeyle**
>
> Tuist Sandboxlar, hem Linux hem de macOS için, kapasiteyi ölçeklendirirken şu anda yalnızca davetiyeyle erişilebilir durumdadır. Hesabınız için erişim talep etmek üzere [bize ulaşın](mailto:contact@tuist.dev) veya [topluluk Slack kanalında](https://slack.tuist.dev) bize mesaj atın. Sandboxlar genel kullanıma sunulduğunda fiyatlandırma duyurulacaktır.

Sandbox, bir kodlama aracısının komutlarını çalıştırdığı ve dosyalarını düzenlediği sanal bir makinedir. Her aracı oturumu kendi sandboxını alır; bu sandbox, oturum süresince checkout’ını, derleme ürünlerini ve yüklü araçları saklar. Aracı boşta kaldığında sandbox duraklatılır; sonraki mesaj geldiğinde kaldığı yerden devam eder.

Sandboxlar, <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> ile aynı altyapıda, ekibinizin <.localized_link href="/guides/features/cache">önbelleğinin</.localized_link> yanında çalışır; böylece bir aracının derlemeleri, CI ve yerel makinelerinizle aynı önbelleğe alınmış yapıtları kullanabilir.

Sandboxları şuradan kullanabilirsiniz:

- **<.localized_link href="/guides/features/sandboxes/amp">Amp</.localized_link>**: Amp çalışma alanınızın orb’larını Tuist üzerinde çalıştırın veya <.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac eklentisi</.localized_link> ile herhangi bir Amp sohbetine Xcode derlemeleri için bir Mac sağlayın.
- **<.localized_link href="/guides/features/sandboxes/claude">Claude</.localized_link>**: Claude Managed Agents oturumlarını ve Claude Code bulut oturumlarını (claude.ai, masaüstü ve mobil uygulamalar ve `claude --cloud`) Tuist üzerinde çalıştırın.
- **[Tuist CLI](#cli)**: Terminalinizden sandbox oluşturun ve içinde komutlar çalıştırın veya API üzerinden kendi araçlarınızdan kullanın.

## CLI ile başlayın {#cli}

Terminalinizden `tuist sandbox` kullanarak bir sandbox oluşturun ve içinde komutlar çalıştırın.

### 1. Giriş yapın {#cli-log-in}

Hesabın herhangi bir üyesi sandboxlarını oluşturup yönetebilir:

```bash
tuist auth login
```

### 2. Bir sandbox oluşturun {#cli-create}

```bash
tuist sandbox create --platform macos
```

Linux için `--platform` seçeneğini atlayın. Belirli bir [Xcode](#xcode) sürümüne sahip bir Mac için `--xcode` seçeneğini sürümle birlikte geçin, örneğin `--xcode 26.1.1`; bu seçenek `--platform macos` anlamına gelir. Daha büyük bir [yapılandırma](#platforms) için `--vcpus` ile `--memory-gb` geçin, bir Linux sandboxına daha fazla [CPU](#guaranteed-cpu) garantisi vermek için `--guaranteed-vcpus` geçin ve daha büyük bir disk için `--workspace-gb` geçin. Komut, sandbox çalışmaya başladığında döner ve kimliği dahil olmak üzere ayrıntılarını yazdırır. Geçerli dizindeki Tuist projesinin hesabını kullanır; başka bir hesap seçmek için `--account` geçin.

### 3. Komutları çalıştırın {#cli-exec}

```bash
tuist sandbox exec <sandbox-id> -- xcodebuild -version
```

Komut, sandbox içinde `bash -l` ile çalışır; duraklatılmışsa önce onu sürdürür. `tuist` ne kadar uzun çalışırsa çalışsın çıktısını akış olarak verir ve komutun durumuyla çıkar; Ctrl-C ile sandbox içindeki işlemi iptal edebilirsiniz. Gerektiğinde `--cwd`, `--env NAME=VALUE` ve `--timeout` (en fazla altı saat) geçin.

Komut `tuist` ile bağlantısız çalışır, bu nedenle bağlantı kopsa bile devam eder. Uzun bir derlemeyi zaman sınırlı bir araç çağrısına, örneğin bir aracı çağrısına sığdırmak için `--wait <seconds>` geçin: süre dolduğunda `tuist` komutu çalışır durumda bırakır, 75 çıkış koduyla çıkar ve çıktısının kaldığı yerden devam edip komutun durumuyla çıkan `tuist sandbox exec <sandbox-id> --attach <command-id> --stdout-offset … --stderr-offset …` komutunu yazdırır.

### Yaygın görevler {#cli-tasks}

| Görev | Komut |
| --- | --- |
| Sandboxları listele | `tuist sandbox list` |
| Birini göster | `tuist sandbox show <id>` |
| Duraklat veya sürdür | `tuist sandbox pause <id>`, `tuist sandbox resume <id>` |
| Yerel Git çalışma ağacının dosyalarını yansıt | `tuist sandbox sync <id>` |
| Dosyaları içeri veya dışarı kopyala | `tuist sandbox cp <id>:<path> <local-path>`, `tuist sandbox cp <local-path> <id>:<path>` |
| Sil | `tuist sandbox delete <id> --yes` |
| Kullanımı gör | `tuist sandbox analytics` |

Makine tarafından okunabilir çıktı için `--json` ekleyin. Tüm seçenekler için <.localized_link href="/cli/sandbox">CLI referansına</.localized_link> bakın. Bunun yerine kodla sandboxları yönetmek isterseniz, aynı işlemleri `/api/accounts/{account_handle}/sandboxes` altında [Tuist API](https://tuist.dev/api/docs) üzerinden kullanın veya bir aracının <.localized_link href="/guides/features/agentic-coding/mcp">MCP</.localized_link> üzerinden kullanmasına izin verin.

Etkileşimli olarak giriş yapamayan araçlar, örneğin bir macOS sandboxında derleme yapan bir aracı eklentisi, bunun yerine `account:sandboxes:write` kapsamına sahip bir <.localized_link href="/guides/server/authentication#account-tokens">hesap token’ı</.localized_link> ile kimlik doğrulaması yapabilir. Hesabın bir üyesinin yapabileceği her şeyi yapabilir: sandbox oluşturabilir, içinde komutlar çalıştırabilir ve bunları duraklatabilir, sürdürebilir, arşivleyebilir ve silebilir. Entegrasyon ayarları hesap yöneticilerinde kalır.

### Sandbox içinde Tuist {#tuist-in-sandbox}

macOS sandboxlar Tuist CLI ile gelir. Projeniz Tuist’i mise aracılığıyla sabitlediğinde (`mise.toml` veya `.tool-versions`), `tuist` bunun yerine o sürümü çalıştırır; bir komut ilk ihtiyaç duyduğunda yüklenir. `tuist sandbox exec` ile başlattığınız her komutta mise’in shim’leri (`$HOME/.local/share/mise/shims`) `PATH` üzerinde ilk sırada ve imajdaki Tuist en sonda yer alır; böylece `tuist` ve diğer mise araçlarınız komutlarınızda ve Xcode derleme aşamalarında, örneğin bir şemanın post-actions’larında çalışır. Her Mac ayrıca kodlama ajanları için `/opt/tuist/agent-guide.md` konumunda bir rehber taşır; bu rehber imajından üretilir: Xcode ve simülatörleri, deposunun nerede olduğunu ve hazır bir anlık görüntünün neler içerdiğini gösterir. Mac üzerinde çalışan Claude Code, Codex ve Amp bunu talimat dosyalarından bulur.

`tuist sandbox exec` ile başlattığınız her komut ayrıca bir Tuist runner’ın aldığı her şeyi alır, böylece sandbox’taki derlemeler kimlik bilgilerini geçmenize gerek kalmadan hesabınızın <.localized_link href="/guides/features/cache">önbelleğini</.localized_link> kullanır:

- `TUIST_URL` ve sandbox’un ana bilgisayarının erişebildiği durumlarda, örneğin macOS’ta, aynı raftaki önbelleğin `TUIST_CACHE_ENDPOINT` değeri.
- `TUIST_OIDC_TOKEN`, o komut için kısa ömürlü bir kimlik token’ıdır. Tuist CLI 4.218.0 ve sonrası bununla otomatik olarak giriş yapar; 4.215.0 ile 4.217.x arasında, aynı komut içinde önce `tuist auth login` çalıştırın.

Token her komut için basılır ve yalnızca o komut çalışırken bir Tuist token’ı ile değiştirilebilir; bu nedenle bir sandbox asla uzun ömürlü bir kimlik bilgisi tutmaz. Token, komutu başlatan kişinin veya token’ın önbellekle yapabileceğinden fazlasını asla vermez: Yalnızca yazma yetkisi olan token’lara sahip hesap üyeleri okuma erişimi alır ve sandbox’ın önbelleği kullanabilmesi için bir hesap token’ının `account:sandboxes:write` yanında `ci` gibi önbellek kapsamlarına ihtiyacı vardır. `--env` ile geçtiğiniz değişkenler önceliklidir.

## Bir kodlama aracısından Mac üzerinde derleme yapın {#coding-agents}

Linux üzerinde çalışan bir kodlama aracı, örneğin bir bulut aracı oturumu, dosyaları çalıştığı yerde düzenlemeye devam ederken Apple platformu kodunu bir macOS sandboxında derleyebilir, test edebilir ve çalıştırabilir. Amp’te <.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac eklentisini</.localized_link> yükleyin. Claude Code veya Cursor gibi diğer ajanlar için:

1. Aracıyı Tuist <.localized_link href="/guides/features/agentic-coding/mcp">MCP sunucusuna</.localized_link> bağlayın. Sunucunun `create_sandbox` aracı, aracıya Mac’i nasıl yöneteceğini söyler.
2. Tuist CLI’yi aracının çalıştığı yere yükleyin, örneğin ortamın kurulum betiğinde: `mise use -g tuist@latest` veya `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist` (ARM’de `tuist-linux-aarch64`).
3. CLI’yi kimlik doğrulayın. MCP sunucusunun oturum açma işlemi buna aktarılmaz; bu nedenle ya bir hesap üyesi olarak `tuist auth login` çalıştırın ya da `TUIST_TOKEN` değerini `account:sandboxes:write` kapsamına sahip bir <.localized_link href="/guides/server/authentication#account-tokens">hesap token’ı</.localized_link> olarak ayarlayın.
4. Ortam ağ erişimini kısıtlıyorsa, `tuist.dev` alanına izin verin. CLI dosyaları Mac’e bunun üzerinden yükler, bu nedenle başka bir etki alanına ihtiyaç duymaz.

Aracı, görev başına bir Mac oluşturur ve projenin sabitlediği [Xcode](#xcode) sürümünü kullanır: `create_sandbox`, seçebileceği Xcode sürümlerini listeler ve aracıya projenin sabitlemesini, örneğin `.xcode-version` değerini okumasını söyler. Her komuttan önce `tuist sandbox sync` çalıştırır. Git’in yoksaymadığı dosyaları, taahhüt edilmiş olsun veya olmasın kopyalar ve sonrasında yalnızca değişenleri kopyalar. Mac’te zaten [Tuist](#tuist-in-sandbox) bulunur; proje bir sürüm sabitliyorsa o sürüm kuruludur ve hesabınızın önbelleğinde oturum açılmıştır; aracı Mac’in kılavuzunu bir kez okur. Aracı ardından `tuist sandbox exec` ile `xcodebuild` gibi komutları çalıştırır, ekran görüntüleri veya derlenmiş bir uygulama gibi sonuçları `tuist sandbox cp` ile geri kopyalar ve görev bittiğinde Mac’i siler. Bir Mac, son komutundan sonra 10 dakika boyunca çalışır durumda kalır, böylece sonraki komut hemen başlar; `tuist sandbox pause` onu daha erken geri verir. Geride bırakılan bir Mac duraklatılır ve 14 gün duraklatıldıktan sonra silinir.

## Linux ve macOS {#platforms}

**Linux** sandbox’ları Ubuntu 24.04 çalıştırır. Her Linux sandbox’ında 16 vCPU bulunur ve çalıştığı makinenin boşta kalan çekirdeklerine kadar genişleyebilir; bu nedenle şekli belleğini belirler:

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

Bir Linux sandbox’ına belleğinin her GiB’si için bir vCPU’nun dörtte biri garanti edilir; örneğin 8 GiB için 2 vCPU. Makinede boşta kalan kaynaklardan yararlanarak 16 vCPU’ya kadar çıkabilir. Bu durum, çoğunlukla bekleyen ve ardından ani derleme yapan bir aracı için uygundur. Yoğun bir makinede bile daha kararlı CPU’ya ihtiyaç duyulduğunda, sandbox oluşturulurken 1, 2, 4 veya 8 vCPU garanti edilebilir; sandbox, bu değer ile bellek garantisi arasında daha büyük olanı alır:

| Nerede | Nasıl |
| --- | --- |
| CLI | `tuist sandbox create --guaranteed-vcpus 4` |
| API ve MCP `create_sandbox` | `"guaranteed_vcpus": 4` |

- **Garanti bir alt sınırdır, üst sınır değildir.** 4 garantili vCPU’ya sahip bir sandbox, çekirdekler boşta olduğunda yine de 16’ya kadar genişler. Rekabet durumunda her sandbox, garantisine orantılı olarak CPU alır.
- **Minimum olarak faturalandırılır.** Çalışan bir sandbox, kullandığı CPU için faturalandırılır ancak garantisinden daha az için asla faturalandırılmaz.
- **Bir sandbox garantisini ömrü boyunca korur.** Değiştirmek için yeni bir sandbox oluşturun.
- **macOS sandbox’ları her zaman tüm şekline sahiptir**, bu nedenle garanti almazlar.

### Bir Xcode seçin {#xcode}

Her macOS sandbox’ı, oluşturulurken seçtiğiniz tek bir Xcode çalıştırır. O Xcode için <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> profiliyle aynı imajı başlatır, böylece bir aracı CI’nızla aynı araç zinciri ve simülatörlerle derleme yapar. tuist.dev üzerinde macOS sandbox’ları şu anda şunları sunar:

- `26.6` (varsayılan)
- `26.1.1`
- `27.0`
- `27.1`
- `27.2`

Runner profillerinde olduğu gibi tam sürümü kullanarak `xcode_version` (CLI’da `--xcode`) ile birini seçin:

| Nerede | Nasıl |
| --- | --- |
| CLI | `tuist sandbox create --xcode 26.1.1` |
| API ve MCP `create_sandbox` | `"xcode_version": "26.1.1"` |
| Amp için Tuist Mac eklentisi | `xcode` ile `tuist_mac_start` |
| Amp orb’ları | Orb türü `macos-xcode-26-1-1` (bkz. <.localized_link href="/guides/features/sandboxes/amp#xcode">Amp</.localized_link>) |
| Claude Code ve Claude Yönetilen Ajanlar | Ortamda `xcode_version` veya Yönetilen Ajanlar oturumu başına (bkz. <.localized_link href="/guides/features/sandboxes/claude#xcode">Claude</.localized_link>) |

- **Sürüm belirtilmezse**, Mac varsayılanı alır.
- **Tuist’in sunmadığı bir sürüm reddedilir** ve hata mesajı seçebileceğiniz sürümleri listeler, böylece şu anda nelerin mevcut olduğunu bilirsiniz.
- **Tuist, deponuzdaki `.xcode-version` dosyasını okumaz.** Sürümü siz veya Mac’i talep eden aracı seçer. MCP aracı ve Tuist Mac eklentisi, ajanlara projenin sabitlediği sürümle eşleşmelerini söyler.
- **Bir sandbox Xcode’unu ömrü boyunca korur.** Başka bir Xcode ile derleme yapmak için yeni bir sandbox oluşturun. `xcodebuild -version`, bir Mac’in hangi Xcode’u çalıştırdığını gösterir.

## Güvenlik {#security}

- Her sandbox kendi sanal makinesidir. Sandbox’lar birbirleriyle veya CI işleriyle dosya sistemi, bellek veya işlem paylaşmaz.
- Sandbox’lar bir hesaba aittir ve hesabın herhangi bir üyesi, entegrasyona hizmet veren sandbox’lar dahil olmak üzere bunları kullanabilir ve yönetebilir. Entegrasyonları yalnızca yöneticiler bağlar. Bir entegrasyondan gelen oturumlar yalnızca entegrasyonun bağlı olduğu hesabın sandbox’larına erişebilir.
- Bir entegrasyonu bağlamak için Tuist’e verdiğiniz kimlik bilgileri, örneğin bir Amp sağlayıcı jetonu veya bir Claude ortam anahtarı, şifrelenmiş olarak saklanır ve bir daha asla gösterilmez.
- Bir sandbox internete erişebilir. Bir aracının ondan erişebileceği şeyleri, bir CI işine对待 ettiğiniz gibi değerlendirin.
