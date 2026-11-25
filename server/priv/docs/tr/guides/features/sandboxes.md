---
{
  "title": "Sanal Ortamlar",
  "titleTemplate": ":title · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist Sanal Ortamları, Amp ve Claude gibi kodlama ajanları için kalıcı Linux ve macOS sanal makinelerdir. Her ajan oturumu kendi makinesine sahiptir; ajan boşta kaldığında makine duraklatılır ve dosyaları bozulmadan kaldığı yerden devam eder."
}
---
# Sandboxlar {#sandboxes}

> [!IMPORTANT]
> **Yalnızca davetle**
>
> Tuist Sandboxları, hem Linux hem de macOS için, kapasiteyi ölçeklendirirken şu anda yalnızca davetle erişilebilir. Hesabınız için erişim talep etmek üzere [bize ulaşın](mailto:contact@tuist.dev) veya [topluluk Slack](https://slack.tuist.dev) kanalında bize mesaj atın. Fiyatlandırma, Sandboxlar genel kullanıma sunulduğunda duyurulacaktır.

Sandbox, bir kodlama aracısının komutlarını çalıştırdığı ve dosyalarını düzenlediği sanal bir makinedir. Her aracı oturumu kendi sandboxını alır; bu sandbox, oturum süresi boyunca checkout durumunu, derleme ürünlerini ve yüklü araçları saklar. Aracı boşta kaldığında sandbox duraklatılır; sonraki mesaj geldiğinde işlem kaldığı yerden devam eder.

Sandboxlar, <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> ile aynı altyapıda, ekibinizin <.localized_link href="/guides/features/cache">önbelleğinin</.localized_link> yanında çalışır; böylece bir aracının derlemeleri, CI ve yerel makinelerinizle aynı önbelleğe alınmış yapıtları kullanabilir.

Sandboxları şuradan kullanabilirsiniz:

- **<.localized_link href="/guides/features/sandboxes/amp">Amp</.localized_link>**: Amp çalışma alanınızın orb'larını Tuist üzerinde çalıştırın veya <.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac eklentisi</.localized_link> ile herhangi bir Amp thread'ine Xcode derlemeleri için bir Mac tahsis edin.
- **<.localized_link href="/guides/features/sandboxes/claude">Claude</.localized_link>**: Claude Managed Agents oturumlarını ve Claude Code bulut oturumlarını (claude.ai, masaüstü ve mobil uygulamalar ve `claude --cloud`) Tuist üzerinde çalıştırın.
- **[Tuist CLI](#cli)**: Terminalinizden veya API üzerinden kendi araçlarınızdan sandbox oluşturun ve içinde komutlar çalıştırın.

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

Linux için `--platform` seçeneğini atlayın. Belirli bir [Xcode](#xcode) sürümüne sahip bir Mac için, örneğin `--xcode 26.1.1` gibi bir sürümle birlikte `--xcode` parametresini geçin; bu, `--platform macos` anlamına gelir. Daha büyük bir [yapılandırma](#platforms) için `--vcpus` ile birlikte `--memory-gb` parametresini, bir Linux sandboxı için daha fazla [CPU](#guaranteed-cpu) garantisi vermek üzere `--guaranteed-vcpus` parametresini ve daha büyük bir disk için `--workspace-gb` parametresini geçin. Sandbox, oluşturulduktan sonra iki saat boyunca çalışır ve her yeniden başlatmada süre sıfırlanır; 5 dakika ile bir gün arasında bir süre için `--lifetime-minutes` parametresini geçin. Ömrü sona erdiğinde, çalışan komutlar iptal edilir, sandbox duraklatılır ve arşivlenir; dosyaları korunur, böylece unutulmuş bir sandbox hesabınızın kapasitesini kullanmayı bırakır. Komut, sandbox çalışmaya başladığında geri döner ve ID'si dahil olmak üzere ayrıntılarını yazdırır. Tüm hostlar meşgul olduğunda, örneğin CI işleri paylaşılan Mac'leri tutarken, sunucu oluşturma işlemi `fleet_busy` hatasıyla başarısız olmadan önce 25 saniye bekler; en fazla 5 dakikaya kadar (en fazla bir saat) denemeye devam etmek için `--wait-timeout 5m` parametresini geçin; neden yaklaşık dakikada bir stderr'de tekrarlanır. Geçerli dizindeki Tuist projesinin hesabını kullanır; başka birini seçmek için `--account` parametresini geçin.

### 3. Komutları çalıştırın {#cli-exec}

```bash
tuist sandbox exec <sandbox-id> -- xcodebuild -version
```

Komut, sandbox içinde `bash -l` ile çalışır; duraklatılmışsa önce yeniden başlatılır. `tuist`, ne kadar uzun sürerse sürsün çıktısını akış olarak verir ve komutun durumuyla çıkar; Ctrl-C ile sandbox içindeki işlem iptal edilir. Gerektiğinde `--cwd`, `--env NAME=VALUE` ve `--timeout` (en fazla altı saat) parametrelerini geçin.

Komut `tuist` bağlantısından bağımsız çalışır, böylece bağlantı kopmasından etkilenmez. Uzun bir derlemeyi, bir aracı gibi zaman sınırlı bir araç çağrısına sığdırmak için `--wait <seconds>` parametresini geçin: süre önce dolduğunda, `tuist` komutu çalışır halde bırakır, 75 koduyla çıkar ve çıktısının kaldığı yerden devam edip komutun durumuyla çıkmasını sağlayan `tuist sandbox exec <sandbox-id> --attach <command-id> --stdout-offset … --stderr-offset …` komutunu yazdırır.

### Yaygın görevler {#cli-tasks}

| Görev | Komut |
| --- | --- |
| Sandboxları listele | `tuist sandbox list` |
| Bir tane göster | `tuist sandbox show <id>` |
| Duraklat veya devam ettir | `tuist sandbox pause <id>`, `tuist sandbox resume <id>` |
| Süresi dolmasına rağmen çalışır halde tut | `tuist sandbox extend <id> --lifetime-minutes 240` |
| Yerel Git çalışma ağacındaki dosyaları yansıt | `tuist sandbox sync <id>` |
| Başlatılmış iOS Simülatörünün veya bir macOS sandboxının tüm ekranının ekran görüntüsünü al | `tuist sandbox screenshot <id> --out shot.png`, `tuist sandbox screenshot <id> --screen --out screen.png` |
| Dosyaları içeri veya dışarı kopyala | `tuist sandbox cp <id>:<path> <local-path>`, `tuist sandbox cp <local-path> <id>:<path>` |
| Sil | `tuist sandbox delete <id> --yes` |
| Kullanımı gör | `tuist sandbox analytics` |

Makine tarafından okunabilir çıktı için `--json` ekleyin. Tüm seçenekler için <.localized_link href="/cli/sandbox">CLI referansına</.localized_link> bakın. Bunun yerine kodla sandboxları yönetmek istiyorsanız, aynı işlemleri `/api/accounts/{account_handle}/sandboxes` altında [Tuist API](https://tuist.dev/api/docs) üzerinden kullanın veya bir aracının <.localized_link href="/guides/features/agentic-coding/mcp">MCP</.localized_link> üzerinden bunları kullanmasına izin verin.

Etkileşimli giriş yapamayan araçlar, örneğin bir macOS sandboxında derleme yapan bir aracı eklentisi, bunun yerine `account:sandboxes:write` kapsamına sahip bir <.localized_link href="/guides/server/authentication#account-tokens">hesap token'ı</.localized_link> ile kimlik doğrulaması yapabilir. Hesabın bir üyesinin yapabileceği her şeyi yapabilir: sandbox oluşturabilir, içinde komutlar çalıştırabilir ve bunları duraklatabilir, devam ettirebilir, arşivleyebilir ve silebilir. Entegrasyon ayarları ve bir entegrasyona hizmet veren sandboxlarda komut çalıştırma yetkisi hesap yöneticilerinde kalır.

### Sandbox içindeki Tuist {#tuist-in-sandbox}

macOS sandboxları Tuist CLI ile birlikte gelir. Projeniz Tuist'i mise aracılığıyla sabitliyorsa (`mise.toml` veya `.tool-versions`), `tuist` bunun yerine o sürümü çalıştırır; ilk kez bir komut ihtiyaç duyduğunda yüklenir. `tuist sandbox exec` ile başlattığınız her komutta, mise'nin shim'leri (`$HOME/.local/share/mise/shims`) `PATH` üzerinde ilk sırada ve imajdaki Tuist son sırada yer alır; böylece `tuist` ve diğer mise araçlarınız komutlarınızda ve Xcode derleme aşamalarında, örneğin bir şemanın post-action'larında çalışır. Her Mac ayrıca `/opt/tuist/agent-guide.md` konumunda kodlama ajanları için bir kılavuz taşır; bu kılavuz imajından oluşturulur: Xcode ve simülatörler, deposunun nerede olduğu ve hazır bir snapshot'un neleri içerdiği. Mac üzerinde çalışan Claude Code, Codex ve Amp bunu talimat dosyalarından bulur.

`tuist sandbox exec` ile başlattığınız her komut ayrıca bir Tuist runner'ın sahip olduğu everything'a sahip olur, böylece sandbox'taki derlemeler kimlik bilgilerini geçmenize gerek kalmadan hesabınızın <.localized_link href="/guides/features/cache">önbelleğini</.localized_link> kullanır:

- `TUIST_URL` ve, sandbox host'unun buna erişebildiği durumlarda, örneğin macOS'ta, aynı raftaki önbelleğin `TUIST_CACHE_ENDPOINT` değeri.
- `TUIST_OIDC_TOKEN`, o komut için kısa ömürlü bir kimlik token'ı. Tuist CLI 4.218.0 ve sonrası bununla otomatik olarak giriş yapar; 4.215.0 ile 4.217.x arasında, aynı komut içinde önce `tuist auth login` çalıştırın.

Token her komut için basılır ve yalnızca o komut çalışırken bir Tuist token'ı ile değiştirilebilir; bu nedenle bir sandbox asla uzun ömürlü bir kimlik bilgisini tutmaz. Asla, komutu başlatan kişinin veya token'ın önbellekle yapabileceğinden daha fazlasını sağlamaz: yalnızca token'ların yazabildiği bir önbelleğe sahip hesabın üyeleri okuma erişimi alır ve bir hesap token'ının, sandbox'ın önbelleği hiç kullanabilmesi için `account:sandboxes:write` yanına `ci` gibi önbellek kapsamlarına ihtiyacı vardır. `--env` ile geçtiğiniz değişkenler önceliklidir.

## Bir kodlama aracısından Mac üzerinde derleme yapın {#coding-agents}

Linux üzerinde çalışan bir kodlama aracısı, örneğin bir bulut aracı oturumu, dosyaları çalıştığı yerde düzenlemeye devam ederken Apple platform kodunu bir macOS sandboxında derleyebilir, test edebilir ve çalıştırabilir. Amp'te <.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac eklentisini</.localized_link> yükleyin. Claude Code veya Cursor gibi diğer ajanlar için:

1. Aracıyı Tuist <.localized_link href="/guides/features/agentic-coding/mcp">MCP sunucusuna</.localized_link> bağlayın. `create_sandbox` aracı, aracıya Mac'i nasıl yöneteceğini söyler.
2. Tuist CLI'yi aracının çalıştığı yere yükleyin, örneğin ortamın kurulum betiğinde: `mise use -g tuist@latest`, veya `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist` (ARM üzerinde `tuist-linux-aarch64`).
3. CLI'de kimlik doğrulaması yapın. MCP sunucusunun oturum açma işlemi buna aktarılmaz; bu nedenle ya bir hesap üyesi olarak `tuist auth login` komutunu çalıştırın ya da `TUIST_TOKEN` değerini `account:sandboxes:write` kapsamına sahip bir <.localized_link href="/guides/server/authentication#account-tokens">hesap token'ı</.localized_link> olarak ayarlayın.
4. Ortam ağ erişimini kısıtlıyorsa, `tuist.dev` adresine izin verin. CLI dosyaları Mac'e bunun üzerinden yükler, bu nedenle başka bir alan adına ihtiyacı yoktur.
5. İsteğe bağlı olarak, aracının her seferinde sormadan Mac'leri oluşturup silmesine izin verin. Aracılar, bir Mac hesabınızın limitlerine dahil edildiği için `create_sandbox` çağrısından önce ve geri alınamadığı için `delete_sandbox` işleminden önce onay ister. Claude Code'da, MCP sunucusunu kaydettiğiniz adı kullanarak (`tuist` burada) ikisine de `.claude/settings.json` içinde izin verin:

   ```json
   {
     "permissions": {
       "allow": ["mcp__tuist__create_sandbox", "mcp__tuist__delete_sandbox"]
     }
   }
   ```

Kurulumu aracının yapması için ona şu istemi verin:

```text
Set up this environment so you can build and test this project on a Tuist macOS sandbox.

Read https://tuist.dev/en/docs/guides/features/sandboxes#coding-agents and follow its "Build on a Mac from a coding agent" section. It's the current Tuist guide for this, so prefer it over anything you remember about Tuist.

You're done when you have created a Mac with create_sandbox, synced this repository to it with tuist sandbox sync, run the project's build there with tuist sandbox exec, and deleted the Mac.

Ask me before anything that needs my login or approval, such as tuist auth login. If a step fails or is blocked, stop and tell me which step you reached and the exact error, without secrets.
```

Aracı, görev başına bir Mac oluşturur ve projenin sabitlediği [Xcode](#xcode) sürümünü kullanır: `create_sandbox`, seçebileceği Xcode sürümlerini listeler ve aracıya projenin sabitlemesini, örneğin `.xcode-version` dosyasını okumasını söyler. Her komuttan önce `tuist sandbox sync` çalıştırır. Git'in yoksaymadığı dosyaları, commit edilmiş olsun veya olmasın kopyalar ve sonrasında yalnızca değişenleri kopyalar. Mac'te zaten [Tuist](#tuist-in-sandbox), proje bir sürüm sabitlediğinde o sabitlenmiş sürüm, hesabınızın önbelleğinde oturum açmış durumda bulunur ve aracı Mac'in rehberini bir kez okur. Aracı daha sonra `tuist sandbox exec` ile `xcodebuild` gibi komutları çalıştırır, uygulamayı Simülatör'de başlatır ve size MCP sunucusunun `get_sandbox_screenshot` özelliği veya `tuist sandbox screenshot` ile gösterir, derlenmiş uygulama gibi sonuçları `tuist sandbox cp` ile geri kopyalar ve görev bittiğinde Mac'i siler. Bir Mac, son komutundan sonra 10 dakika boyunca çalışır durumda kalır, böylece sonraki komut hemen başlar; `tuist sandbox pause` onu daha erken geri verir. Geride bırakılan bir Mac duraklatılır, iki saatlik ömrü dolduğunda arşivlenir ve 14 gün sonra silinir; aracı uzun bir derlemeden önce ömrü uzatır.

## Linux ve macOS {#platforms}

**Linux** sandbox'ları Ubuntu 24.04 çalıştırır. Her Linux sandbox'ında 16 vCPU bulunur ve çalıştığı makinenin boşta kalan çekirdeklerine kadar genişler, bu nedenle şekli belleğini belirler:

- 2 GiB RAM (`--vcpus 1 --memory-gb 2`)
- 4 GiB RAM (`--vcpus 2 --memory-gb 4`, varsayılan)
- 8 GiB RAM (`--vcpus 4 --memory-gb 8`)
- 16 GiB RAM (`--vcpus 8 --memory-gb 16`)
- 32 GiB RAM (`--vcpus 16 --memory-gb 32`)
- 44 GiB RAM (`--vcpus 16 --memory-gb 44`)

**macOS** sandbox'ları Apple silicon üzerinde Xcode ile çalışır:

- 8 vCPU, 8 GiB RAM (varsayılan)
- 8 vCPU, 16 GiB RAM
- 8 vCPU, 24 GiB RAM

### Garantili CPU {#guaranteed-cpu}

Bir Linux sandbox'ına belleğinin her GiB'si için bir vCPU'nun dörtte biri garanti edilir, örneğin 8 GiB için 2 vCPU, ve makinesinde boşta olan kadar ekstra kaynak kullanır, maksimum 16 vCPU'ya kadar. Bu, çoğunlukla bekleyen ve ardından ani yüklerle derleme yapan bir aracı için uygundur. Yoğun bir makinede bile derleme daha kararlı CPU'ya ihtiyaç duyduğunda, sandbox oluşturulurken 1, 2, 4 veya 8 vCPU garanti edin; sandbox, bu değer ile bellek garantisi arasındaki daha büyük olanı alır:

| Nerede | Nasıl |
| --- | --- |
| CLI | `tuist sandbox create --guaranteed-vcpus 4` |
| API ve MCP `create_sandbox` | `"guaranteed_vcpus": 4` |

- **Garanti bir alt sınırdır, üst sınır değildir.** 4 garantili vCPU'ya sahip bir sandbox, çekirdekler boşta olduğunda yine de 16'ya kadar genişler. Rekabet altında, her sandbox garantisine orantılı olarak CPU alır.
- **Minimum olarak faturalandırılır.** Çalışan bir sandbox, kullandığı CPU için faturalandırılır ancak asla garantisinden daha azı için faturalandırılmaz.
- **Bir sandbox garantisini ömrü boyunca korur.** Değiştirmek için yeni bir sandbox oluşturun.
- **macOS sandbox'ları her zaman tüm şekillerine sahiptir**, bu nedenle garanti almazlar.

### Bir Xcode seçin {#xcode}

Her macOS sandbox'ı, oluşturulurken seçtiğiniz tek bir Xcode sürümü çalıştırır. O Xcode için <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> profiliyle aynı imajı önyükler, böylece bir aracı CI'nızla aynı araç zinciri ve simülatörlerle derleme yapar. tuist.dev üzerinde macOS sandbox'ları şu anda şunları sunar:

- `26.6` (varsayılan)
- `26.1.1`
- `27.0`
- `27.1`
- `27.2`

Runner profillerinin yaptığı gibi, tam sürümü kullanarak `xcode_version` ile (CLI'da `--xcode`) birini seçin:

| Nerede | Nasıl |
| --- | --- |
| CLI | `tuist sandbox create --xcode 26.1.1` |
| API ve MCP `create_sandbox` | `"xcode_version": "26.1.1"` |
| Amp için Tuist Mac eklentisi | `xcode` ile `tuist_mac_start` |
| Amp orb'ları | Orb türü `macos-xcode-26-1-1` (bkz. <.localized_link href="/guides/features/sandboxes/amp#xcode">Amp</.localized_link>) |
| Claude Code ve Claude Yönetilen Aracılar | Ortamda `xcode_version`, veya Yönetilen Aracı oturumu başına (bkz. <.localized_link href="/guides/features/sandboxes/claude#xcode">Claude</.localized_link>) |

- **Sürüm belirtilmezse**, Mac varsayılanı alır.
- **Tuist'in sunmadığı bir sürüm reddedilir** ve hata, seçebileceğiniz sürümleri listeler, böylece şu anda nelerin mevcut olduğunu bilirsiniz.
- **Tuist, deponuzun `.xcode-version` dosyasını okumaz.** Sürümü siz veya Mac'i talep eden aracı seçer. MCP aracı ve Tuist Mac eklentisi, aracılara projenin sabitlediği sürümü eşleştirmelerini söyler.
- **Bir sandbox Xcode'unu ömrü boyunca korur.** Başka bir Xcode ile derleme yapmak için yeni bir sandbox oluşturun. `xcodebuild -version` bir Mac'in hangi Xcode'u çalıştırdığını gösterir.

## Güvenlik {#security}

- Her sandbox kendi sanal makinesidir. Sandbox'lar birbirleriyle veya CI işleriyle dosya sistemi, bellek veya işlem paylaşmaz.
- Sandbox'lar bir hesaba aittir ve hesabın herhangi bir üyesi bunları kullanabilir ve yönetebilir. Bir Amp orb'u veya bir Claude Code oturumu gibi bir entegrasyona hizmet veren sandbox'lar, o oturumun çalışmalarını ve kimlik bilgilerini barındırır: üyeler bunları görebilir, duraklatabilir, devam ettirebilir, arşivleyebilir ve silebilir, ancak yalnızca yöneticiler bunlarda komut çalıştırabilir veya dosya yükleyebilir. Entegrasyonları yalnızca yöneticiler bağlar. Bir entegrasyondan gelen oturumlar yalnızca entegrasyonun bağlı olduğu hesabın sandbox'larına erişebilir.
- Bir entegrasyonu bağlamak için Tuist'e verdiğiniz kimlik bilgileri, örneğin bir Amp sağlayıcı jetonu veya bir Claude ortam anahtarı, şifrelenmiş olarak saklanır ve bir daha asla gösterilmez.
- Bir sandbox internete erişebilir. Bir aracının ondan erişebileceği şeyleri, bir CI işine对待 ettiğiniz şekilde对待 edin.
