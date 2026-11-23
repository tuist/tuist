---
{
  "title": "Sanal Alanlar",
  "titleTemplate": ":title · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist Sanal Alanları, Amp ve Claude gibi kodlama ajanları için kalıcı Linux ve macOS sanal makinelerdir. Her ajan oturumu kendi makinesine sahiptir; ajan boşta kaldığında duraklatılır ve dosyaları bozulmadan kaldığı yerden devam eder."
}
---
# Sandboxlar {#sandboxes}

> [!IMPORTANT]
> **Davetiyeyle erişim**
>
> Tuist Sandbox’ları, hem Linux hem de macOS için, kapasiteyi ölçeklendirirken şu anda yalnızca davetiyeyle erişilebilir. Hesabınız için erişim talep etmek üzere [bize ulaşın](mailto:contact@tuist.dev) veya [topluluk Slack](https://slack.tuist.dev) kanalında bize mesaj atın. Sandbox’lar genel kullanıma sunulduğunda fiyatlandırma duyurulacaktır.

Sandbox, bir kodlama aracısının komutlarını çalıştırdığı ve dosyalarını düzenlediği sanal bir makinedir. Her aracı oturumu kendi sandbox’ını alır; bu sandbox, oturum süresince checkout’unu, derleme ürünlerini ve yüklü araçlarını saklar. Aracı boşta kaldığında sandbox duraklatılır; sonraki mesaj geldiğinde kaldığı yerden devam eder.

Sandbox’lar, <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> ile aynı filoda, ekibinizin <.localized_link href="/guides/features/cache">önbelleği</.localized_link> yanında çalışır; böylece bir aracının derlemeleri, CI ve yerel makinelerinizle aynı önbelleğe alınmış yapıtları kullanabilir.

Sandbox’ları şuradan kullanabilirsiniz:

- **<.localized_link href="/guides/features/sandboxes/amp">Amp</.localized_link>**: Amp çalışma alanınızın orb’larını Tuist üzerinde çalıştırın veya herhangi bir Amp sohbetine <.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac eklentisi</.localized_link> ile Xcode derlemeleri için bir Mac sağlayın.
- **<.localized_link href="/guides/features/sandboxes/claude">Claude</.localized_link>**: Claude Managed Agents oturumlarını ve Claude Code bulut oturumlarını (claude.ai, masaüstü ve mobil uygulamalar ve `claude --cloud`) Tuist üzerinde çalıştırın.
- **[Tuist CLI](#cli)**: terminalinizden sandbox’lar oluşturun ve bunlarda komutlar çalıştırın veya API üzerinden kendi araçlarınızla yapın.

## CLI ile başlayın {#cli}

Bir sandbox oluşturun ve içinde `tuist sandbox` kullanarak terminalinizden komutlar çalıştırın.

### 1. Giriş yapın {#cli-log-in}

Hesabın herhangi bir üyesi sandbox’larını oluşturup yönetebilir:

```bash
tuist auth login
```

### 2. Bir sandbox oluşturun {#cli-create}

```bash
tuist sandbox create --platform macos
```

Linux için `--platform` seçeneğini atlayın. Belirli bir [Xcode](#xcode) sürümüne sahip bir Mac için, örneğin `--xcode 26.1.1` gibi bir sürümle `--xcode` geçirin; bu seçenek `--platform macos` anlamına gelir. Daha büyük bir [şekil](#platforms) için `--vcpus` ile birlikte `--memory-gb` geçirin, bir Linux sandbox’ı için daha fazla [CPU](#guaranteed-cpu) garantilemek üzere `--guaranteed-vcpus` geçirin ve daha büyük bir disk için `--workspace-gb` geçirin. Sandbox, oluşturulduktan sonra iki saat çalışır ve her devam ettirmede süre yeniden başlar; 5 dakika ile bir gün arasında bir süre için `--lifetime-minutes` geçirin. Ömrü sona erdiğinde çalışan komutları iptal edilir, duraklatılır ve arşivlenir; dosyaları korunur, böylece unutulmuş bir sandbox hesabınızın kapasitesini tüketmeyi bırakır. Komut, sandbox çalışmaya başladığında döner ve kimliği dahil ayrıntılarını yazdırır. Geçerli dizindeki Tuist projesinin hesabını kullanır; başka bir hesap seçmek için `--account` geçirin.

### 3. Komutları çalıştırın {#cli-exec}

```bash
tuist sandbox exec <sandbox-id> -- xcodebuild -version
```

Komut, sandbox içinde `bash -l` ile çalışır; duraklatılmışsa önce devam ettirilir. `tuist` ne kadar uzun çalışırsa çalışsın çıktısını akış olarak verir ve komutun durumuyla çıkar; Ctrl-C ile sandbox içindeki işlemi iptal edebilirsiniz. Gerektiğinde `--cwd`, `--env NAME=VALUE` ve `--timeout` (en fazla altı saat) geçirin.

Komut `tuist` ile bağlantısı kesilmiş şekilde çalışır, bu sayede bağlantı kopsa bile devam eder. Uzun bir derlemeyi, bir aracı gibi zaman sınırı olan bir araç çağrısına sığdırmak için `--wait <seconds>` geçirin: öncelik onlara geçtiğinde, `tuist` komutu çalışır durumda bırakır, 75 koduyla çıkar ve çıktısının kaldığı yerden devam edip komutun durumuyla çıkmasını sağlayan `tuist sandbox exec <sandbox-id> --attach <command-id> --stdout-offset … --stderr-offset …` komutunu yazdırır.

### Yaygın görevler {#cli-tasks}

| Görev | Komut |
| --- | --- |
| Sandbox’ları listele | `tuist sandbox list` |
| Birini göster | `tuist sandbox show <id>` |
| Duraklat veya devam ettir | `tuist sandbox pause <id>`, `tuist sandbox resume <id>` |
| Süresi dolmasından sonra çalışır durumda tut | `tuist sandbox extend <id> --lifetime-minutes 240` |
| Yerel Git çalışma ağacının dosyalarını yansıt | `tuist sandbox sync <id>` |
| Dosyaları içeri veya dışarı kopyala | `tuist sandbox cp <id>:<path> <local-path>`, `tuist sandbox cp <local-path> <id>:<path>` |
| Sil | `tuist sandbox delete <id> --yes` |
| Kullanımı gör | `tuist sandbox analytics` |

Makine tarafından okunabilir çıktı için `--json` ekleyin. Tüm seçenekler için <.localized_link href="/cli/sandbox">CLI referansına</.localized_link> bakın. Bunun yerine kodla sandbox’ları yönetmek istiyorsanız, aynı işlemleri `/api/accounts/{account_handle}/sandboxes` altında [Tuist API](https://tuist.dev/api/docs) üzerinden kullanın veya bir aracının <.localized_link href="/guides/features/agentic-coding/mcp">MCP</.localized_link> üzerinden kullanmasına izin verin.

Etkileşimli giriş yapamayan araçlar, örneğin bir macOS sandbox’ında derleme yapan bir aracı eklentisi, bunun yerine `account:sandboxes:write` kapsamına sahip bir <.localized_link href="/guides/server/authentication#account-tokens">hesap jetonu</.localized_link> ile kimlik doğrulaması yapabilir. Hesabın bir üyesinin yapabileceği her şeyi yapabilir: sandbox’lar oluşturabilir, içinde komutlar çalıştırabilir ve bunları duraklatabilir, devam ettirebilir, arşivleyebilir ve silebilir. Entegrasyon ayarları hesap yöneticilerinde kalır.

### Sandbox içinde Tuist {#tuist-in-sandbox}

macOS sandbox’ları Tuist CLI ile gelir. Projeniz Tuist’i mise aracılığıyla sabitlediğinde (`mise.toml` veya `.tool-versions`), `tuist` bunun yerine o sürümü çalıştırır; ilk kez bir komut ihtiyaç duyduğunda yüklenir. `tuist sandbox exec` ile başlattığınız her komutta mise’in shim’leri (`$HOME/.local/share/mise/shims`) `PATH` üzerinde ilk sırada ve imajdaki Tuist en sonda yer alır; böylece `tuist` ve diğer mise araçlarınız komutlarınızda ve Xcode derleme aşamalarında, örneğin bir şemanın post-actions’larında çalışır. Her Mac ayrıca kodlama araçları için `/opt/tuist/agent-guide.md` konumunda bir rehber taşır; bu rehber imajından üretilir: Xcode ve simülatörler, deposunun konumu ve hazır bir anlık görüntünün içeriği. Mac üzerinde çalışan Claude Code, Codex ve Amp bunu talimat dosyalarından bulur.

`tuist sandbox exec` ile başlattığınız her komut ayrıca bir Tuist runner’ın aldığı her şeyi alır; böylece sandbox’taki derlemeler, kimlik bilgilerini iletmenize gerek kalmadan hesabınızın <.localized_link href="/guides/features/cache">önbelleğini</.localized_link> kullanır:

- `TUIST_URL` ve sandbox ana bilgisayarının buna erişebildiği durumlarda, örneğin macOS’ta, aynı raftaki önbelleğin `TUIST_CACHE_ENDPOINT` değeri.
- `TUIST_OIDC_TOKEN`, o komut için kısa ömürlü bir kimlik jetonu. Tuist CLI 4.218.0 ve sonrası bununla otomatik olarak giriş yapar; 4.215.0 ile 4.217.x arasında, aynı komutta önce `tuist auth login` çalıştırın.

Jeton her komut için basılır ve yalnızca o komut çalışırken bir Tuist jetonuyla takas edilebilir; bu nedenle bir sandbox asla uzun ömürlü bir kimlik bilgisini tutmaz. Komutu başlatan kişinin veya jetonun önbellekle yapabileceğinden fazlasını asla vermez: yalnızca önbellek jetonlarıyla yazma izni olan hesabın üyeleri okuma erişimi alır ve sandbox’ın önbelleği hiç kullanabilmesi için bir hesap jetonunun `account:sandboxes:write` yanında `ci` gibi önbellek kapsamlarına ihtiyacı vardır. `--env` ile geçtiğiniz değişkenler önceliklidir.

## Bir kodlama aracısından Mac üzerinde derleme {#coding-agents}

Linux üzerinde çalışan bir kodlama aracı, örneğin bir bulut aracı oturumu, dosyaları çalıştığı yerde düzenlemeye devam ederken Apple platformu kodunu bir macOS sandbox’ında derleyebilir, test edebilir ve çalıştırabilir. Amp’te <.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac eklentisini</.localized_link> kurun. Claude Code veya Cursor gibi diğer araçlar için:

1. Aracıyı Tuist <.localized_link href="/guides/features/agentic-coding/mcp">MCP sunucusuna</.localized_link> bağlayın. Sunucunun `create_sandbox` aracı, aracıya Mac’i nasıl yöneteceğini söyler.
2. Aracının çalıştığı yere Tuist CLI’yi kurun; örneğin ortamın kurulum betiğinde: `mise use -g tuist@latest`, ya da `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist` (ARM’da `tuist-linux-aarch64`).
3. CLI’de kimlik doğrulaması yapın. MCP sunucusundaki oturum açma işlemi buraya taşınmaz; bu nedenle ya bir hesap üyesi olarak `tuist auth login` komutunu çalıştırın ya da `TUIST_TOKEN` değerini `account:sandboxes:write` kapsamına sahip bir <.localized_link href="/guides/server/authentication#account-tokens">hesap jetonuna</.localized_link> ayarlayın.
4. Ortam ağ erişimini kısıtlıyorsa, `tuist.dev` alanına izin verin. CLI dosyaları Mac’e bunun üzerinden yükler, başka bir alana gerek yoktur.
5. İsteğe bağlı olarak, aracının her seferinde sormadan Mac oluşturup silmesine izin verin. Aracılar, bir Mac hesabınızın limitlerine dahil olduğu için `create_sandbox` çağrısından önce ve geri alınamadığı için `delete_sandbox` öncesinde onay ister. Claude Code’da, MCP sunucusunu kaydettiğiniz adı kullanarak (`tuist` burada) ikisine de `.claude/settings.json` içinde izin verin:

   ```json
   {
     "permissions": {
       "allow": ["mcp__tuist__create_sandbox", "mcp__tuist__delete_sandbox"]
     }
   }
   ```

Kurulumu aracının yapmasını istiyorsanız, şu istemi verin:

```text
Set up this environment so you can build and test this project on a Tuist macOS sandbox.

Read https://tuist.dev/en/docs/guides/features/sandboxes#coding-agents and follow its "Build on a Mac from a coding agent" section. It's the current Tuist guide for this, so prefer it over anything you remember about Tuist.

You're done when you have created a Mac with create_sandbox, synced this repository to it with tuist sandbox sync, run the project's build there with tuist sandbox exec, and deleted the Mac.

Ask me before anything that needs my login or approval, such as tuist auth login. If a step fails or is blocked, stop and tell me which step you reached and the exact error, without secrets.
```

Aracı, proje tarafından sabitlenen [Xcode](#xcode) ile görev başına bir Mac oluşturur: `create_sandbox` seçebileceği Xcode sürümlerini listeler ve aracıya projenin sabitlemesini, örneğin `.xcode-version` gibi, okumasını söyler. Her komuttan önce `tuist sandbox sync` çalıştırır. Git’in yoksaymadığı, taahhüt edilmiş olsun ya da olmasın tüm dosyaları kopyalar ve sonrasında yalnızca değişenleri kopyalar. Mac’te zaten [Tuist](#tuist-in-sandbox) bulunur; proje bir sürüm sabitlediyse o sürüm kuruludur ve hesabınızın önbelleğine giriş yapılmıştır; aracı Mac’in kılavuzunu bir kez okur. Ardından aracı, `tuist sandbox exec` ile `xcodebuild` gibi komutları çalıştırır, ekran görüntüleri veya derlenmiş bir uygulama gibi sonuçları `tuist sandbox cp` ile geri kopyalar ve görev bittiğinde Mac’i siler. Bir Mac, son komutundan sonra 10 dakika çalışır durumda kalır, böylece sonraki komut hemen başlar; `tuist sandbox pause` onu daha erken serbest bırakır. Geride bırakılan bir Mac duraklatılır, iki saatlik ömrü dolduğunda arşivlenir ve 14 gün sonra silinir; aracı uzun bir derlemeden önce ömrü uzatır.

## Linux ve macOS {#platforms}

**Linux** sandbox’ları Ubuntu 24.04 üzerinde çalışır. Her Linux sandbox’ında 16 vCPU bulunur ve çalıştığı makinenin boşta kalan çekirdeklerine kadar genişleyebilir; bu nedenle şekli belleğini belirler:

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

Bir Linux sandbox’ına belleğinin her GiB’si başına bir vCPU’nun dörtte biri garanti edilir; örneğin 8 GiB için 2 vCPU. Makinede boşta kalan kaynaklardan 16 vCPU’ya kadar ek kapasite kullanabilir. Bu durum, çoğunlukla bekleyen ve ardından patlamalar halinde derleme yapan bir aracı için uygundur. Yoğun bir makinede bile daha istikrarlı CPU gerektiğinde, sandbox oluşturulurken 1, 2, 4 veya 8 vCPU garanti edin; sandbox, bu değer ile bellek garantisi arasında daha büyük olanı alır:

| Nerede | Nasıl |
| --- | --- |
| CLI | `tuist sandbox create --guaranteed-vcpus 4` |
| API ve MCP `create_sandbox` | `"guaranteed_vcpus": 4` |

- **Garanti bir alt sınırdır, üst sınır değildir.** 4 garantili vCPU’ya sahip bir sandbox, çekirdekler boşta olduğunda hâlâ 16’ya kadar genişler. Rekabet altında her sandbox, garantisine orantılı olarak CPU alır.
- **Minimum olarak faturalandırılır.** Çalışan bir sandbox, kullandığı CPU için faturalandırılır ancak asla garantisinden daha az için faturalandırılmaz.
- **Bir sandbox garantisini ömrü boyunca korur.** Değiştirmek için yeni bir sandbox oluşturun.
- **macOS sandbox’ları her zaman tam şeklini alır**, bu nedenle garanti almazlar.

### Bir Xcode seçin {#xcode}

Her macOS sandbox’ı, oluşturulurken seçtiğiniz tek bir Xcode sürümüyle çalışır. O Xcode için <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> profiliyle aynı imajı önyükler; böylece bir aracı, CI’nızla aynı araç zinciri ve simülatörlerle derleme yapar. tuist.dev’de macOS sandbox’ları şu anda şunları sunar:

- `26.6` (varsayılan)
- `26.1.1`
- `27.0`
- `27.1`
- `27.2`

Runner profillerinde olduğu gibi, tam sürümü kullanarak `xcode_version` (CLI’da `--xcode`) ile birini seçin:

| Nerede | Nasıl |
| --- | --- |
| CLI | `tuist sandbox create --xcode 26.1.1` |
| API ve MCP `create_sandbox` | `"xcode_version": "26.1.1"` |
| Amp için Tuist Mac eklentisi | `xcode` ile `tuist_mac_start` |
| Amp orb’ları | Orb türü `macos-xcode-26-1-1` (bkz. <.localized_link href="/guides/features/sandboxes/amp#xcode">Amp</.localized_link>) |
| Claude Code ve Claude Managed Agents | Ortamda `xcode_version` veya Managed Agents oturumu başına (bkz. <.localized_link href="/guides/features/sandboxes/claude#xcode">Claude</.localized_link>) |

- **Sürüm belirtilmezse**, Mac varsayılanı alır.
- **Tuist’in sunmadığı bir sürüm reddedilir** ve hata, seçebileceğiniz sürümleri listeler; böylece şu anda nelerin mevcut olduğunu bilirsiniz.
- **Tuist, deponuzdaki `.xcode-version` dosyasını okumaz.** Sürümü siz veya Mac’i isteyen aracı seçer. MCP aracı ve Tuist Mac eklentisi, aracılara projenin sabitlediği sürümü eşleştirmelerini söyler.
- **Bir sandbox Xcode’unu ömrü boyunca korur.** Başka bir Xcode ile derlemek için yeni bir sandbox oluşturun. `xcodebuild -version`, bir Mac’in hangi Xcode’u çalıştırdığını gösterir.

## Güvenlik {#security}

- Her sandbox kendi sanal makinesidir. Sandbox’lar birbirleriyle veya CI işleriyle dosya sistemi, bellek veya süreç paylaşmaz.
- Sandbox’lar bir hesaba aittir ve hesabın herhangi bir üyesi bunları kullanabilir ve yönetebilir; entegrasyonlara hizmet eden sandbox’lar da buna dahildir. Entegrasyonları yalnızca yöneticiler bağlar. Bir entegrasyondan gelen oturumlar yalnızca entegrasyonun bağlı olduğu hesabın sandbox’larına erişir.
- Bir entegrasyonu bağlamak için Tuist’e verdiğiniz kimlik bilgileri, örneğin bir Amp sağlayıcı belirteci veya bir Claude ortam anahtarı, şifrelenerek saklanır ve bir daha asla gösterilmez.
- Bir sandbox internete erişebilir. Bir aracının oradan erişebileceği şeyleri, bir CI işine nasıl davranıyorsanız aynı şekilde ele alın.
